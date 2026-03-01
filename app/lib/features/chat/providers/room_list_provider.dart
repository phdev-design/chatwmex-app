import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/models/room.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';

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

  @override
  RoomListState build() {
    _repository = ref.watch(chatRepositoryProvider);
    // Initial fetch handled by user or when screen mounts
    // We can call it here but better to separate side-effects from build if possible,
    // or use FutureProvider for simple fetching.
    // For Notifier, calling async in build is tricky.
    // Let's just return initial state and let UI trigger fetch or use Future.microtask
    Future.microtask(() => fetchRooms());
    return const RoomListState();
  }

  Future<void> fetchRooms() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rooms = await _repository.getMyRooms();
      state = state.copyWith(isLoading: false, rooms: rooms);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
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

final roomListViewModelProvider = NotifierProvider<RoomListViewModel, RoomListState>(RoomListViewModel.new);
