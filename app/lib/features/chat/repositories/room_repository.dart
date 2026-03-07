import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/features/chat/models/room.dart';

class RoomRepository {
  final NetworkService _networkService;

  RoomRepository(this._networkService);

  Future<Room> createRoom(String name, List<String> memberIds) async {
    final response = await _networkService.client.post('/rooms', data: {
      'name': name,
      'member_ids': memberIds,
    });
    return Room.fromJson(response.data['data']);
  }

  Future<void> leaveRoom(String roomId) async {
    await _networkService.client.post('/rooms/$roomId/leave');
  }

  Future<void> deleteRoom(String roomId) async {
    await _networkService.client.delete('/rooms/$roomId');
  }

  Future<void> transferOwnership(String roomId, String newOwnerId) async {
    await _networkService.client.patch('/rooms/$roomId/owner', data: {
      'new_owner_id': newOwnerId,
    });
  }

  Future<List<dynamic>> getRoomMemberProfiles(String roomId) async {
    final response = await _networkService.client.get('/rooms/$roomId/member-profiles');
    return response.data['data'] as List<dynamic>;
  }
}

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  return RoomRepository(networkService);
});
