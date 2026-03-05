import 'dart:io';
import 'package:dio/dio.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/features/chat/models/room.dart';
import 'package:app/models/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaginatedMessages {
  final List<Message> messages;
  final String nextCursor;
  final bool hasMore;

  const PaginatedMessages({
    required this.messages,
    required this.nextCursor,
    required this.hasMore,
  });
}

class ChatRepository {
  final NetworkService _networkService;
  final LocalDbService _localDb;

  ChatRepository(this._networkService, this._localDb);

Future<List<Room>> getMyRooms({String query = ''}) async {
    try {
      final Map<String, dynamic> queryParams = {};
      if (query.isNotEmpty) {
        queryParams['q'] = query;
      }
      
      final response = await _networkService.client.get(
        '/rooms/my',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      final List<dynamic> list = response.data['data'] ?? [];
      return list.map((e) => Room.fromJson(e)).toList();
    } catch (e) {
      throw e; // 實務上建議使用自訂 Exception
    }
  }

  Future<List<User>> searchUsers(String query) async {
    try {
      final response = await _networkService.client.get(
        '/users/search',
        queryParameters: {'q': query},
      );
      final List<dynamic> list = response.data['data'] ?? [];
      return list.map((e) => User.fromJson(e)).toList();
    } catch (e) {
      throw e;
    }
  }

  Future<List<User>> getRoomMemberProfiles(String roomId) async {
    if (roomId.isEmpty) return const [];
    try {
      final response = await _networkService.client.get(
        '/rooms/$roomId/member-profiles',
      );
      final List<dynamic> list = response.data['data'] ?? [];
      return list
          .whereType<Map>()
          .map((e) => User.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      throw e;
    }
  }

  Future<String> uploadMedia(File file, String type) async {
    return await _networkService.uploadFile(file, type);
  }

  Future<PaginatedMessages> getRoomResources(
    String roomId, {
    String type = 'media',
    String cursor = '',
    int limit = 20,
  }) async {
    if (roomId.isEmpty) {
      return const PaginatedMessages(
        messages: [],
        nextCursor: '',
        hasMore: false,
      );
    }

    List<Message> apiMessages = [];
    String nextCursor = '';
    bool hasMore = false;

    try {
      final response = await _networkService.client.get(
        '/rooms/$roomId/media',
        queryParameters: {'type': type, 'cursor': cursor, 'limit': limit},
      );
      final payload = Map<String, dynamic>.from(
        response.data['data'] as Map? ?? {},
      );
      final list = payload['data'] as List<dynamic>? ?? [];

      apiMessages = list.map((e) {
        final msg = Message.fromJson(Map<String, dynamic>.from(e));
        if (msg.roomId == null || msg.roomId!.isEmpty) {
          return msg.copyWith(roomId: roomId);
        }
        return msg;
      }).toList();

      nextCursor = payload['next_cursor']?.toString() ?? '';
      hasMore = payload['has_more'] == true;
    } catch (e) {
      print('⚠️ API 發生錯誤: $e');
    }

    if (apiMessages.isEmpty && cursor.isEmpty) {
      print('⚠️ API 回傳空資料，嘗試從 LocalDB 撈取...');
      final cached = await _localDb.getMessagesByRoom(roomId, limit: 1000);
      final deduped = _dedupeMessages(cached);
      for (final id in deduped.removedIds) {
        await _localDb.deleteMessageLocal(id);
      }
      apiMessages = deduped.messages.where((msg) {
        if (type == 'media') {
          return msg.type == MessageType.image || msg.type == MessageType.video;
        } else if (type == 'doc') {
          return msg.type == MessageType.file;
        } else if (type == 'link') {
          return msg.content.contains('http://') ||
              msg.content.contains('https://');
        }
        return false;
      }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return PaginatedMessages(
      messages: apiMessages,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  Future<void> markMessagesAsRead(List<String> messageIds) async {
    if (messageIds.isEmpty) return; // 避免空陣列浪費 API 請求
    try {
      await _networkService.client.post(
        '/messages/read/batch',
        data: {'message_ids': messageIds},
      );
    } catch (e) {
      throw e;
    }
  }

  Future<String> uploadImage(File imageFile) async {
    final fileName = imageFile.path.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: fileName),
    });
    try {
      final response = await _networkService.client.post(
        '/media/upload',
        data: formData,
      );
      return response.data['data']['url'] ?? response.data['url'];
    } catch (e) {
      throw e;
    }
  }

  Future<void> toggleReaction(String messageId, String emoji) async {
    if (messageId.isEmpty || emoji.isEmpty) return;
    try {
      await _networkService.client.post(
        '/messages/$messageId/reactions',
        data: {'emoji': emoji},
      );
    } catch (e) {
      throw e;
    }
  }

  Future<void> unsendMessage(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      await _networkService.client.patch('/messages/$messageId/unsend');
    } catch (e) {
      throw e;
    }
  }

  Future<void> deleteMessage(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      await _networkService.client.delete('/messages/$messageId');
    } catch (e) {
      throw e;
    }
  }

  Future<List<Message>> getMessages(
    String roomId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      // 1. 永遠優先呼叫後端 API，確保能拿到「最新」的訊息
      final response = await _networkService.client.get(
        '/messages/history',
        queryParameters: {
          'contact_id': roomId,
          'limit': limit,
          'offset': offset,
        },
      );

      final List<dynamic> list = response.data['data'] ?? [];

      // 2. 轉換 JSON 並手動補上 roomId (超級關鍵 🔑)
      final latest = list.map((e) {
        final msg = Message.fromJson(e);
        // 如果後端沒傳 room_id，我們手動幫他補上，這樣 LocalDB 才能正確關聯！
        if (msg.roomId == null || msg.roomId!.isEmpty) {
          return msg.copyWith(roomId: roomId);
        }
        return msg;
      }).toList();

      // 3. 將最新的訊息安全地存入 SQLite，更新本地快取
      if (latest.isNotEmpty) {
        try {
          await _localDb.insertMessages(latest);
          await _cleanupOptimisticDuplicates(latest);
        } catch (dbError) {
          print('⚠️ 寫入 SQLite 失敗，但不影響畫面顯示: $dbError');
        }
      }

      // 4. 回傳最新訊息給畫面
      return latest;
    } catch (e) {
      // 5. 只有在「斷網」或「API 壞掉」時，才退回使用本地的快取訊息
      print('⚠️ API 發生錯誤，退回使用本地快取: $e');

      final cached = await _localDb.getMessagesByRoom(
        roomId,
        limit: limit,
        offset: offset,
      );

      if (cached.isNotEmpty) {
        return cached;
      }

      // 如果連快取都沒有，拋出錯誤讓畫面顯示 Error
      throw e;
    }
  }

  Future<void> _cleanupOptimisticDuplicates(List<Message> latest) async {
    final idsToDelete = <String>{};
    for (final msg in latest) {
      final clientMsgId = msg.clientMsgId;
      if (clientMsgId == null || clientMsgId.isEmpty) continue;
      if (msg.id == clientMsgId) continue;
      idsToDelete.add(clientMsgId);
    }
    for (final id in idsToDelete) {
      await _localDb.deleteMessageLocal(id);
    }
  }

  _DedupedResult _dedupeMessages(List<Message> input) {
    final working = [...input]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final kept = <Message>[];
    final removedIds = <String>{};
    const tolerance = Duration(seconds: 3);

    for (final msg in working) {
      final index = kept.indexWhere((existing) {
        if (_canonicalKey(existing).isNotEmpty &&
            _canonicalKey(existing) == _canonicalKey(msg)) {
          return true;
        }
        return _isPotentialDuplicate(existing, msg, tolerance);
      });
      if (index == -1) {
        kept.add(msg);
        continue;
      }
      final current = kept[index];
      final preferred = _preferServerRecord(current, msg);
      final dropped = identical(preferred, current) ? msg : current;
      if (dropped.id.isNotEmpty) {
        removedIds.add(dropped.id);
      }
      kept[index] = preferred;
    }

    return _DedupedResult(
      messages: kept..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      removedIds: removedIds,
    );
  }

  String _canonicalKey(Message msg) {
    if (msg.clientMsgId != null && msg.clientMsgId!.isNotEmpty) {
      return 'client:${msg.clientMsgId}';
    }
    if (msg.id.isNotEmpty) {
      return 'id:${msg.id}';
    }
    return '';
  }

  bool _isPotentialDuplicate(Message a, Message b, Duration tolerance) {
    if (a.type != b.type) return false;
    if (a.senderId != b.senderId) return false;
    if ((a.roomId ?? '') != (b.roomId ?? '')) return false;
    if ((a.receiverId ?? '') != (b.receiverId ?? '')) return false;
    if (a.content.trim() != b.content.trim()) return false;
    final diff = a.createdAt.difference(b.createdAt).inMilliseconds.abs();
    return diff <= tolerance.inMilliseconds;
  }

  Message _preferServerRecord(Message current, Message incoming) {
    final currentServer = _isServerRecord(current);
    final incomingServer = _isServerRecord(incoming);
    if (incomingServer && !currentServer) return incoming;
    if (currentServer && !incomingServer) return current;
    if (incoming.createdAt.isAfter(current.createdAt)) return incoming;
    return current;
  }

  bool _isServerRecord(Message msg) {
    if (msg.id.isEmpty) return false;
    if (msg.clientMsgId != null &&
        msg.clientMsgId!.isNotEmpty &&
        msg.id == msg.clientMsgId) {
      return false;
    }
    return RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(msg.id);
  }
}

class _DedupedResult {
  final List<Message> messages;
  final Set<String> removedIds;

  const _DedupedResult({required this.messages, required this.removedIds});
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return ChatRepository(network, LocalDbService());
});
