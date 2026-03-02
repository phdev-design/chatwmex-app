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

  Future<List<Message>> getMessages(
    String roomId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final cached = await _localDb.getMessagesByRoom(
      roomId,
      limit: limit,
      offset: offset,
    );

    if (cached.length >= limit) {
      return cached;
    }

    if (offset == 0) {
      Future(() async {
        try {
          final response = await _networkService.client.get(
            '/messages/history',
            queryParameters: {
              'contact_id': roomId,
              'limit': limit,
              'offset': offset,
            },
          );
          final List<dynamic> list = response.data['data'] ?? [];
          final latest = list.map((e) => Message.fromJson(e)).toList();
          await _localDb.insertMessages(latest);
        } catch (_) {}
      });
    }

    try {
      final response = await _networkService.client.get(
        '/messages/history',
        queryParameters: {
          'contact_id': roomId,
          'limit': limit,
          'offset': offset,
        },
      );
      final List<dynamic> list = response.data['data'] ?? [];
      final latest = list.map((e) => Message.fromJson(e)).toList();
      await _localDb.insertMessages(latest);
      if (latest.isNotEmpty) {
        return latest;
      }
      return cached;
    } catch (e) {
      if (cached.isNotEmpty) {
        return cached;
      }
      throw e;
    }
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return ChatRepository(network, LocalDbService());
});
