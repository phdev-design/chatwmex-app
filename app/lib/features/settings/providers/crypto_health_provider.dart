import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/crypto/crypto_service.dart';

/// E2EE 金鑰健康狀態
class CryptoHealth {
  final int historyKeyCount;
  final bool hasRecentOverflow;
  final bool isNearLimit;

  CryptoHealth({
    required this.historyKeyCount,
    required this.hasRecentOverflow,
    required this.isNearLimit,
  });
}

/// E2EE 金鑰健康狀態 Provider
final cryptoHealthProvider = FutureProvider.autoDispose<CryptoHealth>((ref) async {
  final cryptoService = ref.watch(cryptoServiceProvider);

  final historyKeyCount = await cryptoService.getHistoryKeyCount();
  final hasRecentOverflow = await cryptoService.checkAndClearKeyOverflowWarning();
  final isNearLimit = historyKeyCount >= 40; // 80% of 50

  return CryptoHealth(
    historyKeyCount: historyKeyCount,
    hasRecentOverflow: hasRecentOverflow,
    isNearLimit: isNearLimit,
  );
});
