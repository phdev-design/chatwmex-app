import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/network/network_service.dart';

class QrScannerPage extends ConsumerStatefulWidget {
  const QrScannerPage({super.key});

  @override
  ConsumerState<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends ConsumerState<QrScannerPage> {
  final MobileScannerController _scannerController = MobileScannerController(
    // 7.x: 設定不重複偵測，避免同一個 QR Code 重複觸發
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final qrValue = barcodes.first.rawValue!;

      // 暫停掃描
      _isProcessing = true;
      await _scannerController.stop();

      // 確認是 UUID（基本長度檢查 36 碼）
      if (qrValue.length == 36) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('登入網頁版'),
            content: const Text('是否允許這個裝置登入網頁版？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('允許'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          try {
            await ref.read(networkServiceProvider).confirmQrLogin(qrValue);
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('授權成功！網頁端即將登入。')));
              Navigator.of(context).pop();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('授權失敗: $e')));
              _isProcessing = false;
              await _scannerController.start();
            }
          }
        } else {
          // 使用者取消
          _isProcessing = false;
          await _scannerController.start();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('無效的 QR Code 格式')));
        }
        await Future.delayed(const Duration(seconds: 2));
        _isProcessing = false;
        await _scannerController.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('掃描 QR Code'),
        actions: [
          // 7.x Breaking Change: torchState 和 cameraFacingState 已從 ValueNotifier
          // 改為透過 _scannerController.stream (MobileScannerState) 取得
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _scannerController,
            builder: (context, state, child) {
              final torchState = state.torchState;
              final cameraIsFront = state.cameraDirection == CameraFacing.front;
              return Row(
                children: [
                  IconButton(
                    icon: Icon(
                      torchState == TorchState.on
                          ? Icons.flash_on
                          : Icons.flash_off,
                      color: torchState == TorchState.on
                          ? Colors.yellow
                          : Colors.grey,
                    ),
                    iconSize: 32.0,
                    onPressed: () => _scannerController.toggleTorch(),
                  ),
                  IconButton(
                    icon: Icon(
                      cameraIsFront ? Icons.camera_front : Icons.camera_rear,
                    ),
                    iconSize: 32.0,
                    onPressed: () => _scannerController.switchCamera(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _scannerController, onDetect: _onDetect),
          // 掃描框覆蓋層
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).primaryColor,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '掃描網頁上的登入 QR Code',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  backgroundColor: Colors.black45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
