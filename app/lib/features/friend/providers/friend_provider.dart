import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/friend/models/friend.dart';
import 'package:app/features/friend/repositories/friend_repository.dart';
import 'package:app/core/websocket/websocket_service.dart';

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
  late FriendRepository _repository;

  @override
  FriendState build() {
    _repository = ref.watch(friendRepositoryProvider);
    final wsService = ref.watch(webSocketServiceProvider);

    final subscription = wsService.events.listen((data) {
      if (data is Map) {
        final event = data['event'];
        final payload = data['data'];
        
        if (event == 'user_profile_updated' && payload is Map) {
          final userId = payload['user_id'];
          final avatarUrl = payload['avatar_url'];
          
          if (userId is String && avatarUrl is String) {
            _updateFriendAvatar(userId, avatarUrl);
          }
        } else if (event == 'user_info_updated' && payload is Map) {
          final userId = payload['user_id'];
          final firstName = payload['first_name'];
          final lastName = payload['last_name'];
          final bio = payload['bio'];
          
          if (userId is String) {
           _updateFriendInfo(userId, firstName, lastName, bio);
          }
        }
      }
    });

    ref.onDispose(() {
      subscription.cancel();
    });

    Future.microtask(() => loadAll());
    return const FriendState();
  }

  void _updateFriendAvatar(String userId, String avatarUrl) {
    if (state.friends.isEmpty) return;
    
    final updatedFriends = state.friends.map<Friend>((friend) {
      if (friend.id == userId) {
        return friend.copyWith(avatarUrl: avatarUrl);
      }
      return friend;
    }).toList();
    
    state = state.copyWith(friends: updatedFriends);
  }

  void _updateFriendInfo(String userId, String? firstName, String? lastName, String? bio) {
    if (state.friends.isEmpty) return;
    
    final updatedFriends = state.friends.map<Friend>((friend) {
      if (friend.id == userId) {
        return friend.copyWith(
          firstName: firstName,
          lastName: lastName,
          bio: bio,
        );
      }
      return friend;
    }).toList();
    
    state = state.copyWith(friends: updatedFriends);
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

// ─── Blacklist ───────────────────────────────────────────────────────────────

class BlacklistState {
  final List<Friend> blockedUsers;
  final bool isLoading;
  final String? error;

  const BlacklistState({
    this.blockedUsers = const [],
    this.isLoading = false,
    this.error,
  });

  BlacklistState copyWith({
    List<Friend>? blockedUsers,
    bool? isLoading,
    String? error,
  }) {
    return BlacklistState(
      blockedUsers: blockedUsers ?? this.blockedUsers,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class BlacklistNotifier extends Notifier<BlacklistState> {
  late FriendRepository _repository;

  @override
  BlacklistState build() {
    _repository = ref.watch(friendRepositoryProvider);
    return const BlacklistState();
  }

  Future<void> loadBlockedUsers() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final users = await _repository.getBlockedUsers();
      state = state.copyWith(isLoading: false, blockedUsers: users);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> unblock(String userId) async {
    try {
      await _repository.unblockUser(userId);
      await loadBlockedUsers();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final blacklistProvider =
    NotifierProvider<BlacklistNotifier, BlacklistState>(BlacklistNotifier.new);
