import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/settings/providers/linked_devices_provider.dart';

/// QR Code 掃描頁面 — 用於連結新裝置
/// 掃描成功後顯示確認對話框，確認後呼叫 POST /api/v1/auth/qr/confirm
class QrScannerPage extends ConsumerStatefulWidget {
  const QrScannerPage({super.key});

  @override
  ConsumerState<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends ConsumerState<QrScannerPage> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  /// 掃描偵測回呼
  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) return;

    final qrValue = barcodes.first.rawValue!;

    _isProcessing = true;
    await _scannerController.stop();

    // 基本格式驗證：QR Token 為 UUID 格式（36 碼）
    if (qrValue.length != 36) {
      if (!mounted) return;
      _showError('無法辨識 QR Code，請重試');
      await _resumeScanning();
      return;
    }

    if (!mounted) return;

    // 顯示連結確認對話框
    final confirmed = await _showLinkConfirmDialog();

    if (!mounted) return;

    if (confirmed == true) {
      await _confirmLink(qrValue);
    } else {
      await _resumeScanning();
    }
  }

  /// 顯示連結確認對話框（「確認連結」與「取消」按鈕）
  Future<bool?> _showLinkConfirmDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('連結新裝置'),
        content: const Text('確定要連結此網頁端裝置嗎？連結後該裝置將可同步您的聊天訊息。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5856D6),
            ),
            child: const Text('確認連結'),
          ),
        ],
      ),
    );
  }

  /// 呼叫確認連結 API：POST /api/v1/auth/qr/confirm
  Future<void> _confirmLink(String qrToken) async {
    try {
      final network = ref.read(networkServiceProvider);
      final response = await network.client.post(
        '/auth/qr/confirm',
        data: {'qr_token': qrToken},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        // 連結成功 — 回應包含 device_id 與 public_key
        final data = response.data;
        final deviceId = data['device_id'] as String?;
        final publicKey = data['public_key'] as String?;

        // 🔑 Session Key 分發：產生並加密 Session Key 傳送給新裝置
        if (deviceId != null && publicKey != null) {
          await _distributeSessionKey(network, deviceId, publicKey);
        }

        // 重新載入裝置清單
        ref.invalidate(linkedDevicesProvider);

        // 顯示推播通知
        _showLocalNotification('新裝置已連結');

        if (!mounted) return;

        // 顯示成功提示並返回裝置清單
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('裝置連結成功')),
        );
        Navigator.of(context).pop();
      }
    } on DioException catch (e) {
      if (!mounted) return;
      _handleApiError(e);
      await _resumeScanning();
    } catch (e) {
      if (!mounted) return;
      _showError('連結失敗，請重試');
      await _resumeScanning();
    }
  }

  /// 🔑 產生 Session Key 並透過 API 傳送給指定裝置
  Future<void> _distributeSessionKey(
    NetworkService network,
    String deviceId,
    String devicePublicKey,
  ) async {
    try {
      final crypto = ref.read(cryptoServiceProvider);
      final sessionKey = await crypto.generateSessionKey();
      final encryptedSessionKey = await crypto.encryptSessionKeyForDevice(
        sessionKey,
        devicePublicKey,
      );

      await network.client.post(
        '/devices/session-key',
        data: {
          'device_id': deviceId,
          'encrypted_session_key': encryptedSessionKey,
        },
      );
    } catch (e) {
      debugPrint('⚠️ Session Key 分發失敗: $e');
      if (mounted) {
        _showError('金鑰傳遞失敗，請重新連結');
      }
    }
  }

  /// 處理 API 錯誤回應，顯示對應的中文錯誤訊息
  void _handleApiError(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;
    String? errorCode;

    if (data is Map<String, dynamic>) {
      errorCode = data['error'] as String? ?? data['message'] as String?;
    }

    String message;
    switch (statusCode) {
      case 400:
        switch (errorCode) {
          case 'qr_token_expired':
            message = 'QR Code 已過期，請重新掃描';
            break;
          case 'qr_token_already_used':
            message = '此 QR Code 已被使用';
            break;
          case 'qr_token_invalid':
            message = '無效的 QR Code';
            break;
          case 'max_devices_reached':
            message = '已連結裝置數量已達上限 4 台';
            break;
          default:
            message = '連結失敗：請求無效';
        }
        break;
      case 429:
        message = '操作過於頻繁，請稍後再試';
        break;
      default:
        message = '連結失敗，請重試';
    }

    _showError(message);
  }

  /// 顯示錯誤 SnackBar
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 顯示本地推播通知（「新裝置已連結」）
  void _showLocalNotification(String message) {
    // 使用 SnackBar 作為應用內通知
    // 實際推播通知由後端透過 OneSignal 觸發
    debugPrint('🔔 $message');
  }

  /// 恢復掃描
  Future<void> _resumeScanning() async {
    _isProcessing = false;
    if (mounted) {
      await _scannerController.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          '掃描 QR Code',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _scannerController,
            builder: (context, state, child) {
              final torchState = state.torchState;
              return IconButton(
                icon: Icon(
                  torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                  color: torchState == TorchState.on
                      ? Colors.yellow
                      : Colors.white60,
                ),
                onPressed: () => _scannerController.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          // 掃描框覆蓋層
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF5856D6),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // 底部說明文字
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '掃描網頁版 QR Code 以連結裝置',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
