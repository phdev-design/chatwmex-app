import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
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
              final isCipher = _looksLikeCiphertext(messageContent);
              if (previewTitle == null && isCipher) {
                // Async decrypt
                _getDecryptedPreview(messageContent, targetRoomId).then((
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
                    messageContent,
                    previewTitle: previewTitle,
                  ),
                  lastMessageType: previewTitle != null ? 'link' : messageType,
                  lastMessageTime: createdAt ?? DateTime.now(),
                );
              }
            }
          }

          // 如果訊息不是自己發送的，自動回傳 delivered 回執
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
        if (lm != null &&
            lmType != 'image' &&
            lmType != 'audio' &&
            lmType != 'file' &&
            lmType != 'document') {
          if (_looksLikeCiphertext(lm)) {
            // For group rooms, getPublicKey will likely fail and fallback to "🔒 加密訊息"
            final decryptedLM = await _getDecryptedPreview(lm, room.id);
            r = r.copyWith(lastMessage: decryptedLM);
          }
        }

        final override = _unreadOverrides[room.id];
        if (override != null) {
          r = r.copyWith(unreadCount: override);
        }

        // 修復3：如果 API 回來的 lastMessage 是空的，但 state 裡已有值，保留 state 的值
        final existingRoom = state.rooms.firstWhere(
          (existing) => existing.id == room.id,
          orElse: () => room,
        );
        if ((r.lastMessage == null || r.lastMessage!.isEmpty) &&
            existingRoom.lastMessage != null &&
            existingRoom.lastMessage!.isNotEmpty) {
          r = r.copyWith(
            lastMessage: existingRoom.lastMessage,
            lastMessageType: existingRoom.lastMessageType,
            lastMessageTime: existingRoom.lastMessageTime,
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
    final index = updated.indexWhere((r) => r.id == roomId);
    if (index > 0) {
      final room = updated.removeAt(index);
      updated.insert(0, room);
    }
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
      case 'file':
      case 'document':
        return '[檔案]';
      default:
        // 判斷是否為 E2EE 密文（base64 且長度夠長）
        if (_looksLikeCiphertext(content)) {
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
      final decrypted = await cryptoService.decryptMessage(
        content,
        opponentPublicKey,
      );

      // 解密成功且內容改變
      if (decrypted != content) return decrypted;

      // 看起來是密文但解密失敗
      final looksLikeCiphertext = _looksLikeCiphertext(content);
      return looksLikeCiphertext ? '🔒 加密訊息' : content;
    } catch (_) {
      return '🔒 加密訊息';
    }
  }
} // ← 這裡才是正確的 Class 結尾

final roomListViewModelProvider =
    NotifierProvider<RoomListViewModel, RoomListState>(RoomListViewModel.new);
