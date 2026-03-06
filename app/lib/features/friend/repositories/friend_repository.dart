import 'package:app/core/network/network_service.dart';
import 'package:app/features/friend/models/friend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FriendRepository {
  final NetworkService _networkService;

  FriendRepository(this._networkService);

  Future<void> sendFriendRequest(String usernameOrEmail) async {
    await _networkService.client.post('/friends/request', data: {
      'username_or_email': usernameOrEmail,
    });
  }

  Future<void> acceptFriendRequest(String requestId) async {
    await _networkService.client.post('/friends/accept/$requestId');
  }

  Future<void> rejectFriendRequest(String requestId) async {
    await _networkService.client.post('/friends/reject/$requestId');
  }

  Future<List<FriendRequest>> getPendingRequests() async {
    final response = await _networkService.client.get('/friends/requests');
    final List<dynamic> list = response.data['data'] ?? [];
    return list.map((e) => FriendRequest.fromJson(e)).toList();
  }

  Future<List<Friend>> getFriends() async {
    final response = await _networkService.client.get('/friends/list');
    final List<dynamic> list = response.data['data'] ?? [];
    return list.map((e) => Friend.fromJson(e)).toList();
  }

  Future<void> unfriend(String targetUserId) async {
    await _networkService.client.delete('/friends/unfriend/$targetUserId');
  }
}

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return FriendRepository(network);
});
