import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/core/storage/local_db_service.dart';

class PublicKeyCacheService {
  final ChatRepository _chatRepository;
  final LocalDbService _localDbService;

  final Map<String, String> _memoryCache = {};
  final Map<String, Future<String?>> _inFlightRequests = {};

  PublicKeyCacheService(this._chatRepository, this._localDbService);

  Future<String?> getPublicKey(String userId) async {
    // 1. Check Memory Cache
    if (_memoryCache.containsKey(userId)) {
      final key = _memoryCache[userId];
      return (key != null && key.isNotEmpty) ? key : null;
    }

    // 2. Check SQLite Cache
    final cachedKey = await _localDbService.getPublicKey(userId);
    if (cachedKey != null) {
      _memoryCache[userId] = cachedKey;
      return cachedKey.isNotEmpty ? cachedKey : null;
    }

    // 3. Deduplicate in-flight requests
    if (_inFlightRequests.containsKey(userId)) {
      return await _inFlightRequests[userId];
    }

    // 4. Fetch from API
    final fetchFuture = _chatRepository
        .getUserPublicKey(userId)
        .then((key) async {
          final finalKey = key ?? '';
          _memoryCache[userId] = finalKey;

          // Save to SQLite only if it's a valid key
          // If it's empty, we still keep it in memory cache so we don't hammer the API in this session,
          // but we don't save the empty state to DB so next launch we can try again.
          if (finalKey.isNotEmpty) {
            await _localDbService.savePublicKey(userId, finalKey);
          }

          _inFlightRequests.remove(userId);
          return finalKey.isNotEmpty ? finalKey : null;
        })
        .catchError((e) {
          debugPrint('Fetch public key failed: $e');
          _inFlightRequests.remove(userId);
          return null;
        });

    _inFlightRequests[userId] = fetchFuture;
    return await fetchFuture;
  }

  /// Fetch multiple public keys in parallel
  /// Returns a map of user IDs to their public keys (null for unavailable keys)
  /// Leverages existing getPublicKey method for caching and deduplication
  Future<Map<String, String?>> getPublicKeys(List<String> userIds) async {
    // Fetch all keys in parallel
    final futures = userIds.map((userId) => getPublicKey(userId));
    final keys = await Future.wait(futures);
    
    // Build result map
    final results = <String, String?>{};
    for (int i = 0; i < userIds.length; i++) {
      results[userIds[i]] = keys[i];
    }
    
    return results;
  }

  /// 清除所有快取的 public key（換帳號登入時呼叫，避免用舊 key 解密）
  Future<void> clearAllCache() async {
    _memoryCache.clear();
    _inFlightRequests.clear();
    await _localDbService.clearAllPublicKeys();
  }

  /// 🔐 強制從 API 重新取得指定用戶的公鑰（繞過快取）
  /// 用於解密失敗時，可能是對方已更換金鑰
  Future<String?> refreshPublicKey(String userId) async {
    // 清除該用戶的快取
    _memoryCache.remove(userId);
    _inFlightRequests.remove(userId);

    try {
      final key = await _chatRepository.getUserPublicKey(userId);
      final finalKey = key ?? '';
      _memoryCache[userId] = finalKey;

      if (finalKey.isNotEmpty) {
        await _localDbService.savePublicKey(userId, finalKey);
      }

      return finalKey.isNotEmpty ? finalKey : null;
    } catch (e) {
      debugPrint('Refresh public key failed for $userId: $e');
      return null;
    }
  }
}

final publicKeyCacheServiceProvider = Provider<PublicKeyCacheService>((ref) {
  final chatRepo = ref.watch(chatRepositoryProvider);
  final localDb = LocalDbService();
  return PublicKeyCacheService(chatRepo, localDb);
});
