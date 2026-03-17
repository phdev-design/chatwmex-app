import 'package:app/core/network/network_service.dart';
import 'package:app/features/friend/models/friend.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FriendRepository {
  final NetworkService _networkService;

  FriendRepository(this._networkService);

  Future<void> sendFriendRequest(String usernameOrEmail) async {
    await _networkService.client.post(
      '/friends/request',
      data: {'username_or_email': usernameOrEmail},
    );
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

  Future<void> blockUser(String targetId) async {
    await _networkService.client.post(
      '/friends/block',
      data: {'target_id': targetId},
    );
  }

  Future<void> unblockUser(String targetId) async {
    await _networkService.client.post(
      '/friends/unblock',
      data: {'target_id': targetId},
    );
  }

  Future<bool> isBlocked(String targetId) async {
    final response = await _networkService.client.get(
      '/friends/block/check',
      queryParameters: {'target_id': targetId},
    );
    return response.data['data']['is_blocked'] == true;
  }

  // TODO(backend): GET /api/v1/friends/blocks 尚未實作，待後端補上後確認
  Future<List<Friend>> getBlockedUsers() async {
    final response = await _networkService.client.get('/friends/blocks');
    final List<dynamic> list = response.data['data'] ?? [];
    return list
        .map((e) => Friend.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 批次查詢多位用戶的在線狀態與最後上線時間
  Future<Map<String, Map<String, dynamic>>> getPresence(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};
    final response = await _networkService.client.post(
      '/online/presence',
      data: {'user_ids': userIds},
    );
    final data = response.data['data'] as Map<String, dynamic>? ?? {};
    return data.map(
      (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
    );
  }
}

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return FriendRepository(network);
});
