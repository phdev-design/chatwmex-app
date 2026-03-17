import 'dart:async';
import 'package:flutter/foundation.dart';
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
        } else if (event == 'presence_update' && payload is Map) {
          // 即時更新好友在線狀態
          final userId = payload['user_id'];
          final isOnline = payload['is_online'];
          final lastSeenRaw = payload['last_seen'];
          debugPrint('[Presence] WS presence_update: userId=$userId, isOnline=$isOnline, lastSeen=$lastSeenRaw');
          if (userId is String && isOnline is bool) {
            DateTime? lastSeen;
            if (lastSeenRaw is String) {
              lastSeen = DateTime.tryParse(lastSeenRaw);
            }
            _updateFriendPresence(userId, isOnline, lastSeen);
          }
        }
      }
    });

    ref.onDispose(() => subscription.cancel());

    Future.microtask(() => loadAll());
    return const FriendState();
  }

  void _updateFriendAvatar(String userId, String avatarUrl) {
    if (state.friends.isEmpty) return;
    final updated = state.friends.map<Friend>((f) {
      return f.id == userId ? f.copyWith(avatarUrl: avatarUrl) : f;
    }).toList();
    state = state.copyWith(friends: updated);
  }

  void _updateFriendInfo(
    String userId,
    String? firstName,
    String? lastName,
    String? bio,
  ) {
    if (state.friends.isEmpty) return;
    final updated = state.friends.map<Friend>((f) {
      return f.id == userId
          ? f.copyWith(firstName: firstName, lastName: lastName, bio: bio)
          : f;
    }).toList();
    state = state.copyWith(friends: updated);
  }

  void _updateFriendPresence(String userId, bool isOnline, DateTime? lastSeen) {
    if (state.friends.isEmpty) return;
    final updated = state.friends.map<Friend>((f) {
      if (f.id != userId) return f;
      return f.copyWith(
        isOnline: isOnline,
        lastSeen: lastSeen ?? f.lastSeen,
      );
    }).toList();
    state = state.copyWith(friends: updated);
  }

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final friends = await _repository.getFriends();
      final requests = await _repository.getPendingRequests();

      // 批次載入在線狀態
      final friendIds = friends.map((f) => f.id).toList();
      Map<String, Map<String, dynamic>> presenceMap = {};
      if (friendIds.isNotEmpty) {
        presenceMap = await _repository.getPresence(friendIds);
      }

      debugPrint('[Presence] loadAll: friendIds=$friendIds');
      debugPrint('[Presence] loadAll: presenceMap=$presenceMap');

      final friendsWithPresence = friends.map((f) {
        final p = presenceMap[f.id];
        if (p == null) {
          debugPrint('[Presence] ${f.username}(${f.id}): no presence data');
          return f;
        }
        final isOnline = p['is_online'] as bool? ?? false;
        final lastSeenRaw = p['last_seen'];
        DateTime? lastSeen;
        if (lastSeenRaw is String) lastSeen = DateTime.tryParse(lastSeenRaw);
        debugPrint('[Presence] ${f.username}(${f.id}): isOnline=$isOnline, lastSeen=$lastSeenRaw');
        return f.copyWith(isOnline: isOnline, lastSeen: lastSeen);
      }).toList();

      state = state.copyWith(
        isLoading: false,
        friends: friendsWithPresence,
        requests: requests,
      );
    } catch (e) {
      debugPrint('[Presence] loadAll error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> sendRequest(String usernameOrEmail) async {
    try {
      await _repository.sendFriendRequest(usernameOrEmail);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> acceptRequest(String requestId) async {
    try {
      await _repository.acceptFriendRequest(requestId);
      await loadAll();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> rejectRequest(String requestId) async {
    try {
      await _repository.rejectFriendRequest(requestId);
      await loadAll();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> unfriend(String targetUserId) async {
    try {
      await _repository.unfriend(targetUserId);
      await loadAll();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> blockUser(String targetId) async {
    await _repository.blockUser(targetId);
    await loadAll();
  }

  Future<void> unblockUser(String targetId) async {
    await _repository.unblockUser(targetId);
    await loadAll();
  }

  Future<bool> isBlocked(String targetId) async {
    return await _repository.isBlocked(targetId);
  }
}

final friendViewModelProvider = NotifierProvider<FriendViewModel, FriendState>(
  FriendViewModel.new,
);

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

final blacklistProvider = NotifierProvider<BlacklistNotifier, BlacklistState>(
  BlacklistNotifier.new,
);
