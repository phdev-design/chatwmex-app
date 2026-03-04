import 'dart:io';
import 'package:dio/dio.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/features/chat/models/room.dart';
import 'package:app/models/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatRepository {
  final NetworkService _networkService;
  final LocalDbService _localDb;

  ChatRepository(this._networkService, this._localDb);

  Future<List<Room>> getMyRooms() async {
    try {
      final response = await _networkService.client.get('/rooms/my');
      final List<dynamic> list = response.data['data'] ?? [];
      return list.map((e) => Room.fromJson(e)).toList();
    } catch (e) {
      throw e;
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

  Future<String> uploadMedia(File file, String type) async {
    return await _networkService.uploadFile(file, type);
  }

  Future<void> markMessagesAsRead(List<String> messageIds) async {
    if (messageIds.isEmpty) return; // 避免空陣列浪費 API 請求
    try {
      await _networkService.client.post(
        '/messages/read',
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
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return ChatRepository(network, LocalDbService());
});
