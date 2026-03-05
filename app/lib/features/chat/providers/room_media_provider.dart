import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/models/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class RoomMediaState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String nextCursor;
  final List<Message> messages;
  final String? error;

  const RoomMediaState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.nextCursor = '',
    this.messages = const [],
    this.error,
  });

  RoomMediaState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextCursor,
    List<Message>? messages,
    String? error,
  }) {
    return RoomMediaState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: nextCursor ?? this.nextCursor,
      messages: messages ?? this.messages,
      error: error ?? this.error,
    );
  }
}

class RoomMediaNotifier
    extends FamilyNotifier<RoomMediaState, ({String roomId, String type})> {
  late final ChatRepository _repository;

  @override
  RoomMediaState build(({String roomId, String type}) arg) {
    _repository = ref.watch(chatRepositoryProvider);
    return const RoomMediaState();
  }

  Map<String, List<Message>> get groupedMessages {
    final sorted = [...state.messages]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final groups = <String, List<Message>>{};
    for (final message in sorted) {
      final key = DateFormat('MMMM yyyy').format(message.createdAt);
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(message);
    }
    return groups;
  }

  Future<void> loadInitial() async {
    if (state.isLoading) return;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      nextCursor: '',
      messages: [],
      error: null,
    );
    try {
      final result = await _repository.getRoomResources(
        arg.roomId,
        type: arg.type,
        cursor: '',
        limit: 20,
      );
      state = state.copyWith(
        isLoading: false,
        messages: result.messages,
        nextCursor: result.nextCursor,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, error: null);
    try {
      final result = await _repository.getRoomResources(
        arg.roomId,
        type: arg.type,
        cursor: state.nextCursor,
        limit: 20,
      );
      final existingIds = state.messages.map((m) => m.id).toSet();
      final merged = [...state.messages];
      for (final msg in result.messages) {
        if (!existingIds.contains(msg.id)) {
          merged.add(msg);
        }
      }
      state = state.copyWith(
        isLoadingMore: false,
        messages: merged,
        nextCursor: result.nextCursor,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }
}

final roomMediaProvider =
    NotifierProvider.family<
      RoomMediaNotifier,
      RoomMediaState,
      ({String roomId, String type})
    >(RoomMediaNotifier.new);
