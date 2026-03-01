import 'package:app/core/network/network_service.dart';
import 'package:app/features/chat/models/room.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatRepository {
  final NetworkService _networkService;

  ChatRepository(this._networkService);

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
      final response = await _networkService.client.get('/users/search', queryParameters: {'q': query});
      final List<dynamic> list = response.data['data'] ?? [];
      return list.map((e) => User.fromJson(e)).toList();
    } catch (e) {
      throw e;
    }
  }
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return ChatRepository(network);
});
