import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/models/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:app/features/chat/providers/chat_room_provider.dart'; // e2eeEnabledProvider
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';

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

  // ✅ 新增：解密媒體訊息的 URL
  Future<List<Message>> _decryptMediaContent(List<Message> messages) async {
    final cryptoService = ref.read(cryptoServiceProvider);
    final cacheService = ref.read(publicKeyCacheServiceProvider);

    final result = <Message>[];
    for (final msg in messages) {
      // 只處理圖片和影片
      if (msg.type != MessageType.image && msg.type != MessageType.video) {
        result.add(msg);
        continue;
      }
      // content 已是正常 URL，不用解密
      if (msg.content.startsWith('http')) {
        result.add(msg);
        continue;
      }
      // 嘗試解密
      try {
        final pubKey = await cacheService.getPublicKey(msg.senderId);
        if (pubKey != null && pubKey.isNotEmpty) {
          final decrypted = await cryptoService.decryptMessage(msg.content, pubKey);
          if (decrypted != msg.content && decrypted.startsWith('http')) {
            result.add(msg.copyWith(content: decrypted));
            continue;
          }
        }
      } catch (_) {}
      result.add(msg); // 解密失敗，保留原樣
    }
    return result;
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
      final decrypted = await _decryptMediaContent(result.messages); // ✅ 加這行
      state = state.copyWith(
        isLoading: false,
        messages: decrypted, // ✅ 改用 decrypted
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
      final decrypted = await _decryptMediaContent(result.messages); // ✅ 加這行
      final existingIds = state.messages.map((m) => m.id).toSet();
      final merged = [...state.messages];
      for (final msg in decrypted) { // ✅ 改用 decrypted
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
