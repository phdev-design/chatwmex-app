import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:app/core/notification/notification_service.dart';
import 'package:app/features/chat/models/room.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/core/websocket/websocket_service.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/core/backup/backup_manager.dart';
import 'package:app/features/chat/repositories/room_repository.dart';

class RoomListState {
  final List<Room> rooms;
  final List<User> searchResults;
  final bool isLoading;
  final String? error;

  const RoomListState({
    this.rooms = const [],
    this.searchResults = const [],
    this.isLoading = false,
    this.error,
  });

  RoomListState copyWith({
    List<Room>? rooms,
    List<User>? searchResults,
    bool? isLoading,
    String? error,
  }) {
    return RoomListState(
      rooms: rooms ?? this.rooms,
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class RoomListViewModel extends Notifier<RoomListState> {
  late ChatRepository _repository;
  final Map<String, int> _unreadOverrides = {};
  String? _currentUserId;

  @override
  RoomListState build() {
    _repository = ref.watch(chatRepositoryProvider);
    final wsService = ref.watch(webSocketServiceProvider);
    final storage = ref.watch(storageServiceProvider);

    if (_currentUserId == null) {
      Future.microtask(() async {
        _currentUserId = await storage.read('user_id');
      });
    }

    // Connect WebSocket
    wsService.connect();

    // Listen to BackupManager to automatically reload rooms when restore completes
    ref.listen(backupManagerProvider, (previous, next) {
      if (previous?.isBackingUp == true && next.isBackingUp == false) {
        // If a backup or restore just finished without throwing an error
        // we conservatively refresh the room list to show imported conversations
        Future.microtask(() => fetchRooms());
      }
    });

    // Listen to WS events
    final subscription = wsService.events.listen((data) {
      final events = _decodeWsEvents(data);
      for (final eventData in events) {
        final event = eventData['event'];
        if (event == 'chat_message') {
          final payload = eventData['data'];
          if (payload is Map) {
            final message = Map<String, dynamic>.from(payload);
            final roomIdRaw = message['room_id']?.toString() ?? '';
            final senderId = message['sender_id']?.toString() ?? '';
            final receiverId = message['receiver_id']?.toString() ?? '';
            final messageType = message['type']?.toString();
            final messageContent = message['content']?.toString() ?? '';
            String? previewTitle;
            final previewRaw = message['link_preview'];
            if (previewRaw is Map) {
              final previewMap = Map<String, dynamic>.from(previewRaw);
              final title = previewMap['title']?.toString() ?? '';
              if (title.isNotEmpty) {
                previewTitle = title;
              }
            }
            final createdAt = DateTime.tryParse(
              message['created_at']?.toString() ?? '',
            );
            String targetRoomId = roomIdRaw;
            if (targetRoomId.isEmpty) {
              final currentUserId = _currentUserId;
              if (currentUserId != null && senderId == currentUserId) {
                targetRoomId = receiverId;
              } else {
                targetRoomId = senderId;
              }
            }
            if (targetRoomId.isNotEmpty) {
              // 🔐 判斷訊息內容：優先使用 encrypted_contents_fanout 中自己的密文
              String effectiveContent = messageContent;
              final fanoutRaw = message['encrypted_contents_fanout'];
              if (effectiveContent.isEmpty && fanoutRaw is Map && _currentUserId != null) {
                final myCipher = fanoutRaw[_currentUserId]?.toString();
                if (myCipher != null && myCipher.isNotEmpty) {
                  effectiveContent = myCipher;
                }
              }
              
              final isCipher = _looksLikeCiphertext(effectiveContent);
              
              // 🚀 即使內容為空或加密，也要立即更新時間戳和排序
              // 確保聊天室立刻跳到最上方
              if (effectiveContent.isEmpty && !isCipher) {
                // 內容為空且不是密文（可能是 fanout 模式但沒有自己的密文）
                updateRoomLastMessage(
                  targetRoomId,
                  _buildLastMessagePreview(messageType, '', previewTitle: previewTitle),
                  lastMessageType: messageType,
                  lastMessageTime: createdAt ?? DateTime.now(),
                );
              } else if (previewTitle == null && isCipher) {
                // 🔐 先立即顯示「加密訊息」佔位，再異步解密更新
                updateRoomLastMessage(
                  targetRoomId,
                  '🔒 加密訊息',
                  lastMessageType: messageType,
                  lastMessageTime: createdAt ?? DateTime.now(),
                );
                // Async decrypt to replace placeholder
                _getDecryptedPreview(effectiveContent, targetRoomId).then((
                  decrypted,
                ) {
                  updateRoomLastMessage(
                    targetRoomId,
                    _buildLastMessagePreview(
                      messageType,
                      decrypted,
                      previewTitle: previewTitle,
                    ),
                    lastMessageType: messageType,
                    lastMessageTime: createdAt ?? DateTime.now(),
                  );
                });
              } else {
                updateRoomLastMessage(
                  targetRoomId,
                  _buildLastMessagePreview(
                    messageType,
                    effectiveContent,
                    previewTitle: previewTitle,
                  ),
                  lastMessageType: previewTitle != null ? 'link' : messageType,
                  lastMessageTime: createdAt ?? DateTime.now(),
                );
              }
            }
          }

          // 如果訊息不是自己發送的，自動回傳 delivered 回執 + 遞增未讀數
          if (payload is Map) {
            final senderId = payload['sender_id']?.toString() ?? '';
            final msgId = payload['id']?.toString() ?? '';
            final roomIdRaw = payload['room_id']?.toString() ?? '';

            if (senderId.isNotEmpty &&
                senderId != _currentUserId &&
                msgId.isNotEmpty) {
              wsService.send('message_delivered', {
                'message_id': msgId,
                'room_id': roomIdRaw.isEmpty ? null : roomIdRaw,
                'sender_id': senderId,
              });

              // 🚀 本地即時遞增未讀數（不等 API）
              // 如果用戶正在查看該聊天室，不遞增未讀數
              final unreadRoomId = roomIdRaw.isNotEmpty ? roomIdRaw : senderId;
              if (NotificationService.currentActiveRoomId != unreadRoomId) {
                incrementUnreadCount(unreadRoomId);
              }
            }
          }

          // 修復1：移除 Future.microtask(() => fetchRooms());，由 updateRoomLastMessage 管理即時畫面
        } else if (event == 'read_receipt') {
          final payload = eventData['data'];
          if (payload is Map && payload['conversation_id'] != null) {
            markRoomRead(payload['conversation_id'].toString());
          }
          Future.microtask(() => fetchRooms());
        } else if (event == 'messages_read_receipt') {
          final payload = eventData['data'];
          if (payload is Map) {
            final roomId = payload['room_id'];
            final readBy = payload['read_by_user_id'];
            if (roomId is String &&
                readBy is String &&
                _currentUserId != null &&
                readBy == _currentUserId) {
              clearUnreadCount(roomId);
            }
          }
        } else if (event == 'user_profile_updated') {
          final payload = eventData['data'];
          if (payload is Map) {
            final userId = payload['user_id'];
            final avatarUrl = payload['avatar_url'];
            if (userId is String && avatarUrl is String) {
              updateRoomAvatar(userId, avatarUrl);
            }
          }
        } else if (event == 'room_updated') {
          final payload = eventData['data'];
          if (payload is Map) {
            final roomId = payload['room_id'];
            final avatarUrl = payload['avatar_url'];
            final name = payload['name'];
            if (roomId is String) {
              updateRoomDetails(roomId, avatarUrl, name);
            }
          }
        } else if (event == 'ws_reconnected') {
          Future.microtask(() => fetchRooms());
        }
      }
    });

    ref.onDispose(() {
      subscription.cancel();
    });

    // Initial fetch
    Future.microtask(() => fetchRooms());

    return const RoomListState();
  }

  Future<void> fetchRooms({String query = ''}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rooms = await _repository.getMyRooms(query: query);

      final updated = <Room>[];
      for (var room in rooms) {
        Room r = room;
        final lm = room.lastMessage;
        final lmType = room.lastMessageType;

        debugPrint('[fetchRooms] room=${room.id} name=${room.name} type=${room.type} '
            'lm=${lm == null ? "NULL" : (lm.length > 20 ? "${lm.substring(0, 20)}..." : lm)} '
            'senderId=${room.lastMessageSenderId ?? "NULL"}');

        // 先取出 state 中已有的房間資料，用於 fallback
        final existingRoom = state.rooms.firstWhere(
          (existing) => existing.id == room.id,
          orElse: () => room,
        );

        if (lm != null &&
            lmType != 'image' &&
            lmType != 'audio' &&
            lmType != 'file' &&
            lmType != 'document') {
          if (_looksLikeCiphertext(lm)) {
            // 🔐 群組：用發送者公鑰解密（fanout 密文）
            // 🔐 DM：用對方公鑰解密（room.id 就是對方 user ID）
            final decryptKeyId = room.type == 'group'
                ? (room.lastMessageSenderId ?? room.id)
                : room.id;
            debugPrint('[fetchRooms] Decrypting for room=${room.name} type=${room.type} using keyId=$decryptKeyId');
            final decryptedLM = await _getDecryptedPreview(lm, decryptKeyId);
            debugPrint('[fetchRooms] Decrypt result for room=${room.name}: $decryptedLM');

            // ✅ 解密失敗時，優先保留 state 中已有的明文，避免覆蓋
            if (decryptedLM == '🔒 加密訊息') {
              final existingLM = existingRoom.lastMessage;
              if (existingLM != null &&
                  existingLM.isNotEmpty &&
                  !_looksLikeCiphertext(existingLM) &&
                  existingLM != '🔒 加密訊息') {
                r = r.copyWith(
                  lastMessage: existingLM,
                  lastMessageType: existingRoom.lastMessageType ?? lmType,
                  lastMessageTime: existingRoom.lastMessageTime ?? room.lastMessageTime,
                );
              } else {
                r = r.copyWith(lastMessage: decryptedLM);
              }
            } else {
              r = r.copyWith(lastMessage: decryptedLM);
            }
          }
        }

        final override = _unreadOverrides[room.id];
        if (override != null) {
          r = r.copyWith(unreadCount: override);
        }

        // 修復3：如果 API 回來的 lastMessage 是空的，但 state 裡已有值，保留 state 的值
        if ((r.lastMessage == null || r.lastMessage!.isEmpty) &&
            existingRoom.lastMessage != null &&
            existingRoom.lastMessage!.isNotEmpty) {
          r = r.copyWith(
            lastMessage: existingRoom.lastMessage,
            lastMessageType: existingRoom.lastMessageType ?? r.lastMessageType,
            lastMessageTime: existingRoom.lastMessageTime ?? r.lastMessageTime,
          );
        }

        updated.add(r);
      }

      for (final room in rooms) {
        if (room.unreadCount == 0) {
          _unreadOverrides.remove(room.id);
        }
      }

      state = state.copyWith(isLoading: false, rooms: updated);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> leaveRoom(String roomId) async {
    try {
      final roomRepo = ref.read(roomRepositoryProvider);
      await roomRepo.leaveRoom(roomId);
      // Remove the room from the local state
      state = state.copyWith(
        rooms: state.rooms.where((r) => r.id != roomId).toList(),
      );
    } catch (e) {
      debugPrint('Failed to leave room: $e');
      rethrow;
    }
  }

  Future<void> deleteRoom(String roomId) async {
    try {
      final roomRepo = ref.read(roomRepositoryProvider);
      await roomRepo.deleteRoom(roomId);
      // Remove the room from the local state
      state = state.copyWith(
        rooms: state.rooms.where((r) => r.id != roomId).toList(),
      );
    } catch (e) {
      debugPrint('Failed to delete room: $e');
      rethrow;
    }
  }

  Future<void> transferOwnership(String roomId, String newOwnerId) async {
    final roomRepo = ref.read(roomRepositoryProvider);
    await roomRepo.transferOwnership(roomId, newOwnerId);
  }

  Future<List<dynamic>> getRoomMemberProfiles(String roomId) async {
    final roomRepo = ref.read(roomRepositoryProvider);
    return await roomRepo.getRoomMemberProfiles(roomId);
  }

  void markRoomRead(String roomId) {
    _unreadOverrides[roomId] = 0;
    final updated = state.rooms.map((room) {
      if (room.id == roomId && room.unreadCount != 0) {
        return room.copyWith(unreadCount: 0);
      }
      return room;
    }).toList();
    state = state.copyWith(rooms: updated);
  }

  void clearUnreadCount(String roomId) {
    _unreadOverrides[roomId] = 0;
    final updated = state.rooms.map((room) {
      if (room.id == roomId && room.unreadCount != 0) {
        return room.copyWith(unreadCount: 0);
      }
      return room;
    }).toList();
    state = state.copyWith(rooms: updated);
  }

  Future<void> searchUsers(String query) async {
    if (query.isEmpty) {
      state = state.copyWith(searchResults: []);
      return;
    }
    try {
      final users = await _repository.searchUsers(query);
      state = state.copyWith(searchResults: users);
    } catch (e) {
      debugPrint('Search failed: $e');
    }
  }

  // 新增的方法：用於手動更新列表上的最後一則訊息
  void updateRoomLastMessage(
    String roomId,
    String lastMessage, {
    String? lastMessageType,
    DateTime? lastMessageTime,
  }) {
    final updated = state.rooms.map((room) {
      if (room.id == roomId) {
        return room.copyWith(
          lastMessage: lastMessage,
          lastMessageType: lastMessageType,
          lastMessageTime: lastMessageTime ?? room.lastMessageTime,
        );
      }
      return room;
    }).toList();
    // 🚀 按 lastMessageTime 倒序排列，確保最新訊息的房間在最上方
    updated.sort((a, b) {
      final aTime = a.lastMessageTime ?? a.createdAt;
      final bTime = b.lastMessageTime ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    state = state.copyWith(rooms: updated);
  }

  /// 🚀 收到新訊息時遞增未讀數（本地即時更新，不等 API）
  void incrementUnreadCount(String roomId) {
    final current = _unreadOverrides[roomId];
    final existingRoom = state.rooms.firstWhere(
      (r) => r.id == roomId,
      orElse: () => Room(id: '', name: '', createdAt: DateTime.now()),
    );
    final baseCount = current ?? existingRoom.unreadCount;
    _unreadOverrides[roomId] = baseCount + 1;

    final updated = state.rooms.map((room) {
      if (room.id == roomId) {
        return room.copyWith(unreadCount: baseCount + 1);
      }
      return room;
    }).toList();
    state = state.copyWith(rooms: updated);
  }

  void updateRoomAvatar(String userId, String avatarUrl) {
    final updated = state.rooms.map((room) {
      if (room.id == userId) {
        return room.copyWith(avatarUrl: avatarUrl);
      }
      return room;
    }).toList();
    state = state.copyWith(rooms: updated);
  }

  void updateRoomDetails(String roomId, String? avatarUrl, String? name) {
    final updated = state.rooms.map((room) {
      if (room.id == roomId) {
        Room r = room;
        if (avatarUrl != null) {
          r = r.copyWith(avatarUrl: avatarUrl);
        }
        if (name != null) {
          r = r.copyWith(name: name);
        }
        return r;
      }
      return room;
    }).toList();
    state = state.copyWith(rooms: updated);
  }

  List<Map<String, dynamic>> _decodeWsEvents(dynamic data) {
    if (data is Map) {
      return [Map<String, dynamic>.from(data)];
    }
    if (data is! String) {
      return const [];
    }
    final trimmed = data.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final events = <Map<String, dynamic>>[];
    final chunks = trimmed
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    for (final chunk in chunks) {
      try {
        final decoded = jsonDecode(chunk);
        if (decoded is Map) {
          events.add(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        debugPrint('room_list ws decode error: $e');
      }
    }
    return events;
  }

  String _buildLastMessagePreview(
    String? messageType,
    String content, {
    String? previewTitle,
  }) {
    if (previewTitle != null && previewTitle.isNotEmpty) {
      return previewTitle;
    }
    switch (messageType) {
      case 'image':
        return '[圖片]';
      case 'audio':
        return '[語音訊息]';
      case 'video':
        return '[影片]';
      case 'file':
      case 'document':
        return '[檔案]';
      default:
        // 判斷是否為 E2EE 密文（base64 且長度夠長）
        if (_looksLikeCiphertext(content)) {
          return '🔒 加密訊息';
        }
        // 🚀 空內容時顯示加密訊息佔位（避免顯示「尚無訊息」）
        if (content.isEmpty) {
          return '🔒 加密訊息';
        }
        return content;
    }
  }

  bool _looksLikeCiphertext(String content) {
    if (content.length < 40) return false;
    final base64Regex = RegExp(r'^[A-Za-z0-9+/]+=*$');
    return base64Regex.hasMatch(content.trim());
  }

  Future<String> _getDecryptedPreview(String content, String opponentId) async {
    try {
      final cacheService = ref.read(publicKeyCacheServiceProvider);
      final opponentPublicKey = await cacheService.getPublicKey(opponentId);

      if (opponentPublicKey == null || opponentPublicKey.isEmpty) {
        return '🔒 加密訊息';
      }

      final cryptoService = ref.read(cryptoServiceProvider);
      try {
        final decrypted = await cryptoService.decryptMessage(
          content,
          opponentPublicKey,
        );
        if (decrypted != content) return decrypted;
      } catch (_) {
        // 🔐 解密失敗，嘗試刷新公鑰後重試
        final refreshedKey = await cacheService.refreshPublicKey(opponentId);
        if (refreshedKey != null && refreshedKey != opponentPublicKey) {
          try {
            final decrypted = await cryptoService.decryptMessage(
              content,
              refreshedKey,
            );
            if (decrypted != content) return decrypted;
          } catch (_) {
            // 刷新後仍失敗
          }
        }
      }

      final looksLikeCiphertext = _looksLikeCiphertext(content);
      return looksLikeCiphertext ? '🔒 加密訊息' : content;
    } catch (_) {
      return '🔒 加密訊息';
    }
  }
} // ← 這裡才是正確的 Class 結尾

final roomListViewModelProvider =
    NotifierProvider<RoomListViewModel, RoomListState>(RoomListViewModel.new);
