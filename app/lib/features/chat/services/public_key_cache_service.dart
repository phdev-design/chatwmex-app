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

  /// 清除所有快取的 public key（換帳號登入時呼叫，避免用舊 key 解密）
  Future<void> clearAllCache() async {
    _memoryCache.clear();
    _inFlightRequests.clear();
    await _localDbService.clearAllPublicKeys();
  }
}

final publicKeyCacheServiceProvider = Provider<PublicKeyCacheService>((ref) {
  final chatRepo = ref.watch(chatRepositoryProvider);
  final localDb = LocalDbService();
  return PublicKeyCacheService(chatRepo, localDb);
});
