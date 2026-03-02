import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/models/room.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/core/websocket/websocket_service.dart';

class RoomListState {
  final List<Room> rooms;
  final List<User> searchResults;
  final bool isLoading;
  final String? error;

  const RoomListState({
    this.rooms = const [],
    this.searchResults = const [],
    this.isLoading = false,
    this.error,
  });

  RoomListState copyWith({
    List<Room>? rooms,
    List<User>? searchResults,
    bool? isLoading,
    String? error,
  }) {
    return RoomListState(
      rooms: rooms ?? this.rooms,
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class RoomListViewModel extends Notifier<RoomListState> {
  late final ChatRepository _repository;
  final Map<String, int> _unreadOverrides = {};

  @override
  RoomListState build() {
    _repository = ref.watch(chatRepositoryProvider);
    final wsService = ref.watch(webSocketServiceProvider);

    // Connect WebSocket
    wsService.connect();

    // Listen to WS events
    final subscription = wsService.events.listen((data) {
      if (data is Map) {
        final event = data['event'];
        if (event == 'chat_message') {
          fetchRooms();
        } else if (event == 'read_receipt') {
          final payload = data['data'];
          if (payload is Map && payload['conversation_id'] != null) {
            markRoomRead(payload['conversation_id']);
          }
          fetchRooms();
        }
      }
    });

    ref.onDispose(() {
      subscription.cancel();
    });

    // Initial fetch
    Future.microtask(() => fetchRooms());

    return const RoomListState();
  }

  Future<void> fetchRooms() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rooms = await _repository.getMyRooms();
      final updated = rooms.map((room) {
        final override = _unreadOverrides[room.id];
        if (override != null) {
          return room.copyWith(unreadCount: override);
        }
        return room;
      }).toList();
      for (final room in rooms) {
        if (room.unreadCount == 0) {
          _unreadOverrides.remove(room.id);
        }
      }
      state = state.copyWith(isLoading: false, rooms: updated);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void markRoomRead(String roomId) {
    _unreadOverrides[roomId] = 0;
    final updated = state.rooms.map((room) {
      if (room.id == roomId && room.unreadCount != 0) {
        return room.copyWith(unreadCount: 0);
      }
      return room;
    }).toList();
    state = state.copyWith(rooms: updated);
  }

  Future<void> searchUsers(String query) async {
    if (query.isEmpty) {
      state = state.copyWith(searchResults: []);
      return;
    }
    try {
      final users = await _repository.searchUsers(query);
      state = state.copyWith(searchResults: users);
    } catch (e) {
      print('Search failed: $e');
    }
  }
}

final roomListViewModelProvider =
    NotifierProvider<RoomListViewModel, RoomListState>(RoomListViewModel.new);
