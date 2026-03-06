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
}

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  return RoomRepository(networkService);
});
