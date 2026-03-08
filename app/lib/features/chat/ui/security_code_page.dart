import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:crypto/crypto.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';

final contactPublicKeyProvider = FutureProvider.family<String?, String>((
  ref,
  contactId,
) async {
  final cacheService = ref.watch(publicKeyCacheServiceProvider);
  return await cacheService.getPublicKey(contactId);
});

class SecurityCodePage extends ConsumerWidget {
  final String contactId;
  final String contactName;

  const SecurityCodePage({
    super.key,
    required this.contactId,
    required this.contactName,
  });

  int _compareBytes(List<int> a, List<int> b) {
    int minLength = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < minLength; i++) {
      if (a[i] != b[i]) {
        return a[i].compareTo(b[i]);
      }
    }
    return a.length.compareTo(b.length);
  }

  String _generateSafetyNumber(
    String myPublicKeyBase64,
    String theirPublicKeyBase64,
  ) {
    try {
      final myBytes = base64Decode(myPublicKeyBase64);
      final theirBytes = base64Decode(theirPublicKeyBase64);

      List<int> combined;
      if (_compareBytes(myBytes, theirBytes) <= 0) {
        combined = [...myBytes, ...theirBytes];
      } else {
        combined = [...theirBytes, ...myBytes];
      }

      final digest = sha256.convert(combined);

      final numbers = <String>[];
      final hashBytes = digest.bytes;
      for (int i = 0; i < 30; i += 5) {
        int value = 0;
        for (int j = 0; j < 5 && (i + j) < hashBytes.length; j++) {
          value = (value << 8) | hashBytes[i + j];
        }
        numbers.add((value % 100000).toString().padLeft(5, '0'));
      }
      return numbers.join(' ');
    } catch (e) {
      debugPrint('Failed to generate safety number: $e');
      return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = colorScheme.onSurface;
    final secondaryTextColor = colorScheme.onSurfaceVariant;
    final Color bgColor = isDark
        ? const Color(0xFF0B141A)
        : colorScheme.surface;

    final myPublicKeyAsync = ref.watch(cryptoServiceProvider).publicKeyBase64;
    final theirPublicKeyAsync = ref.watch(contactPublicKeyProvider(contactId));

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('安全碼'),
        backgroundColor: bgColor,
        scrolledUnderElevation: 0,
      ),
      body: theirPublicKeyAsync.when(
        data: (theirPubKey) {
          if (theirPubKey == null ||
              theirPubKey.isEmpty ||
              myPublicKeyAsync == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  '對方尚未啟用端對端加密，安全碼無法產生。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: secondaryTextColor,
                    height: 1.5,
                  ),
                ),
              ),
            );
          }

          final safetyNumber = _generateSafetyNumber(
            myPublicKeyAsync,
            theirPubKey,
          );
          final cleanNumber = safetyNumber.replaceAll(' ', '');

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '如果以下的 60 位安全碼與 $contactName 的裝置上顯示的相符，代表你們的對話受到端對端加密保護。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: primaryTextColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: cleanNumber,
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _buildSafetyNumberGrid(safetyNumber, primaryTextColor),
                  const SizedBox(height: 48),
                  Text(
                    '你可以透過視訊通話親自核對，或讓對方掃描你的 QR Code。若安全碼相符，代表沒有人攔截了你們的對話。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: secondaryTextColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text(
            '取得安全碼失敗: $err',
            style: TextStyle(color: colorScheme.error),
          ),
        ),
      ),
    );
  }

  Widget _buildSafetyNumberGrid(String safeNumber, Color textColor) {
    if (safeNumber.isEmpty) return const SizedBox();

    final groups = safeNumber.split(' ');
    if (groups.length != 12) return const SizedBox();

    return Column(
      children: [
        for (int row = 0; row < 4; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (int col = 0; col < 3; col++)
                  Text(
                    groups[row * 3 + col],
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
