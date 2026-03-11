import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/models/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/core/storage/storage_service.dart';

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
  String? _currentUserId;

  @override
  RoomMediaState build(({String roomId, String type}) arg) {
    _repository = ref.watch(chatRepositoryProvider);
    // 獲取當前用戶 ID
    _initCurrentUserId();
    return const RoomMediaState();
  }

  Future<void> _initCurrentUserId() async {
    final storage = ref.read(storageServiceProvider);
    _currentUserId = await storage.read('user_id');
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

  /// 🔐 正確的 ECDH 解密邏輯：解密媒體訊息內容
  /// 
  /// 明文內容（不解密）：
  /// 1. 完整 URL (http://, https://)
  /// 2. 相對路徑 (/uploads/)
  /// 3. MongoDB ObjectID (24 個十六進制字符)
  /// 4. 長度 < 40 的任何字串
  /// 5. 純十六進制字串（不含 Base64 特殊字符）
  /// 
  /// 加密內容（需解密）：
  /// 1. 長度 >= 40
  /// 2. 包含 Base64 特殊字符 (+, /, =)
  /// 3. 使用 ECDH 公私鑰解密（不是對稱金鑰！）
  Future<List<Message>> _decryptMediaContent(List<Message> messages) async {
    final cryptoService = ref.read(cryptoServiceProvider);
    final cacheService = ref.read(publicKeyCacheServiceProvider);

    // 確保有當前用戶 ID
    if (_currentUserId == null) {
      await _initCurrentUserId();
    }

    final result = <Message>[];
    for (final msg in messages) {
      final content = msg.content;
      
      // ========== 第一步：絕對不解密的明文內容 ==========
      
      // 1. 完整 URL
      if (content.startsWith('http://') || content.startsWith('https://')) {
        result.add(msg);
        continue;
      }
      
      // 2. 相對路徑
      if (content.startsWith('/uploads/')) {
        result.add(msg);
        continue;
      }
      
      // 3. 🚫 長度小於 40 的字串（絕對不解密）
      if (content.length < 40) {
        result.add(msg);
        continue;
      }
      
      // 4. 🚫 MongoDB ObjectID（24 個十六進制字符，絕對不解密）
      if (content.length == 24 && RegExp(r'^[a-f0-9]{24}$', caseSensitive: false).hasMatch(content)) {
        result.add(msg);
        continue;
      }
      
      // 5. 🚫 純十六進制字串（不含 Base64 特殊字符，絕對不解密）
      final isHexOnly = RegExp(r'^[a-f0-9]+$', caseSensitive: false).hasMatch(content);
      if (isHexOnly) {
        result.add(msg);
        continue;
      }
      
      // ========== 第二步：判斷是否為加密內容 ==========
      
      // 加密內容必須同時滿足：
      // 1. 長度 >= 40
      // 2. 包含 Base64 特殊字符 (+, /, =)
      final hasBase64Chars = content.contains('+') || 
                             content.contains('/') || 
                             content.contains('=');
      
      if (!hasBase64Chars) {
        // 不含 Base64 特殊字符，不是加密內容
        result.add(msg);
        continue;
      }
      
      // ========== 第三步：使用 ECDH 公私鑰解密 ==========
      
      try {
        // 🔑 關鍵：判斷 targetPubKey（用於 ECDH 解密的對方公鑰）
        // 
        // ECDH 加密原理：
        // - 發送方用「接收方的公鑰」+ 自己的私鑰 → 生成共享密鑰 → 加密
        // - 接收方用「發送方的公鑰」+ 自己的私鑰 → 生成相同共享密鑰 → 解密
        // 
        // 因此解密時：
        // - 如果是「我發送的訊息」：我當初用「接收方公鑰」加密，現在要解密需要「接收方公鑰」
        // - 如果是「別人發送的訊息」：對方用「我的公鑰」加密，現在要解密需要「發送方公鑰」
        String? targetPubKey;
        
        if (msg.senderId == _currentUserId) {
          // 情況 1：這是我發送的訊息
          // 當初我是用接收方的公鑰加密的
          // 對於群組聊天，接收方是群組本身（使用 roomId）
          // 對於一對一聊天，接收方是 receiverId
          if (msg.roomId != null && msg.roomId!.isNotEmpty) {
            targetPubKey = await cacheService.getPublicKey(msg.roomId!);
          } else if (msg.receiverId != null && msg.receiverId!.isNotEmpty) {
            targetPubKey = await cacheService.getPublicKey(msg.receiverId!);
          }
        } else {
          // 情況 2：這是別人發送的訊息
          // 對方是用我的公鑰加密的，所以我用對方的公鑰解密
          targetPubKey = await cacheService.getPublicKey(msg.senderId);
        }
        
        if (targetPubKey == null || targetPubKey.isEmpty) {
          result.add(msg);
          continue;
        }
        
        // 使用正確的 ECDH 解密方法
        final decrypted = await cryptoService.decryptMessage(content, targetPubKey);
        
        // ========== 第四步：驗證解密結果 ==========
        
        if (decrypted.isEmpty || decrypted == content) {
          result.add(msg);
          continue;
        }
        
        // 檢查解密結果是否為有效的 URL 或路徑
        final isValidUrl = decrypted.startsWith('http://') || 
                          decrypted.startsWith('https://') ||
                          decrypted.startsWith('/uploads/');
        
        if (isValidUrl) {
          result.add(msg.copyWith(content: decrypted));
        } else {
          result.add(msg);
        }
        
      } catch (e) {
        print('⚠️ [RoomMedia] Message ${msg.id} 解密失敗');
        result.add(msg);
      }
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
      final decrypted = await _decryptMediaContent(result.messages);
      state = state.copyWith(
        isLoading: false,
        messages: decrypted,
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
      final decrypted = await _decryptMediaContent(result.messages);
      final existingIds = state.messages.map((m) => m.id).toSet();
      final merged = [...state.messages];
      for (final msg in decrypted) {
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
