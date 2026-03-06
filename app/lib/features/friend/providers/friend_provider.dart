import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/friend/models/friend.dart';
import 'package:app/features/friend/repositories/friend_repository.dart';

class FriendState {
  final List<Friend> friends;
  final List<FriendRequest> requests;
  final bool isLoading;
  final String? error;

  const FriendState({
    this.friends = const [],
    this.requests = const [],
    this.isLoading = false,
    this.error,
  });

  FriendState copyWith({
    List<Friend>? friends,
    List<FriendRequest>? requests,
    bool? isLoading,
    String? error,
  }) {
    return FriendState(
      friends: friends ?? this.friends,
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class FriendViewModel extends Notifier<FriendState> {
  late final FriendRepository _repository;

  @override
  FriendState build() {
    _repository = ref.watch(friendRepositoryProvider);
    Future.microtask(() => loadAll());
    return const FriendState();
  }

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final friends = await _repository.getFriends();
      final requests = await _repository.getPendingRequests();
      state = state.copyWith(isLoading: false, friends: friends, requests: requests);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> sendRequest(String usernameOrEmail) async {
    try {
      await _repository.sendFriendRequest(usernameOrEmail);
      // Ideally show success message, no state update needed unless we track sent requests
    } catch (e) {
      // Propagate error to UI
      throw e;
    }
  }

  Future<void> acceptRequest(String requestId) async {
    try {
      await _repository.acceptFriendRequest(requestId);
      await loadAll();
    } catch (e) {
      throw e;
    }
  }

  Future<void> rejectRequest(String requestId) async {
    try {
      await _repository.rejectFriendRequest(requestId);
      await loadAll();
    } catch (e) {
      throw e;
    }
  }

  Future<void> unfriend(String targetUserId) async {
    try {
      await _repository.unfriend(targetUserId);
      await loadAll(); // 重新整理好友清單
    } catch (e) {
      throw e;
    }
  }

  Future<void> blockUser(String targetId) async {
    await _repository.blockUser(targetId);
    await loadAll(); // 重新整理好友列表
  }

  Future<void> unblockUser(String targetId) async {
    await _repository.unblockUser(targetId);
    await loadAll();
  }

  Future<bool> isBlocked(String targetId) async {
    return await _repository.isBlocked(targetId);
  }
}

final friendViewModelProvider = NotifierProvider<FriendViewModel, FriendState>(FriendViewModel.new);
