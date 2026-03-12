import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:app/core/media/image_cache_service.dart';

class PhotoScreen extends ConsumerStatefulWidget {
  final String imageUrl;
  final String heroTag;

  const PhotoScreen({super.key, required this.imageUrl, required this.heroTag});

  @override
  ConsumerState<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends ConsumerState<PhotoScreen> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  bool _isProcessing = false;

  /// 如果使用者有剪裁過圖片，就用這個本機檔案來顯示
  File? _croppedFile;

  /// 已下載的暫存檔案路徑（避免重複下載）
  String? _cachedTempPath;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // ─── 雙擊縮放邏輯（原始邏輯保留） ───

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _onDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final tapPosition = _doubleTapDetails?.localPosition;
    if (tapPosition == null) return;

    double targetScale;
    if (currentScale < 1.5) {
      targetScale = 2.0;
    } else if (currentScale < 3.0) {
      targetScale = 4.0;
    } else {
      targetScale = 1.0;
    }

    if (targetScale == 1.0) {
      _transformationController.value = Matrix4.identity();
      return;
    }

    _transformationController.value = Matrix4(
      targetScale,
      0,
      0,
      -tapPosition.dx * (targetScale - 1),
      0,
      targetScale,
      0,
      -tapPosition.dy * (targetScale - 1),
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    );
  }

  // ─── 核心：下載圖片到暫存目錄（優先使用快取）───

  Future<String> _downloadToTemp() async {
    // 如果已經下載過且檔案還在，就直接返回
    if (_cachedTempPath != null && File(_cachedTempPath!).existsSync()) {
      return _cachedTempPath!;
    }

    // 優先從快取獲取
    final cacheService = ref.read(imageCacheServiceProvider);
    final cachedFile = await cacheService.getCachedImage(widget.imageUrl);
    
    if (cachedFile != null && await cachedFile.exists()) {
      _cachedTempPath = cachedFile.path;
      return _cachedTempPath!;
    }

    // 沒有快取，下載並快取
    final tempDir = await getTemporaryDirectory();
    // 從 URL 取得副檔名，如果抓不到就預設 .jpg
    final uri = Uri.parse(widget.imageUrl);
    String ext = p.extension(uri.path);
    if (ext.isEmpty) ext = '.jpg';
    final fileName =
        'photo_${DateTime.now().millisecondsSinceEpoch}$ext';
    final savePath = p.join(tempDir.path, fileName);

    await Dio().download(widget.imageUrl, savePath);
    
    // 快取圖片
    await cacheService.cacheImage(widget.imageUrl, imageData: await File(savePath).readAsBytes());

    _cachedTempPath = savePath;
    return savePath;
  }

  // ─── 分享 ───

  Future<void> _handleShare() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // 優先使用剪裁後的圖片
      final filePath = _croppedFile?.path ?? await _downloadToTemp();
      final xFile = XFile(filePath);
      await Share.shareXFiles([xFile]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─── 剪裁 ───

  Future<void> _handleCrop() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final filePath = _croppedFile?.path ?? await _downloadToTemp();

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: filePath,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁剪圖片',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: Colors.blueAccent,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: '裁剪圖片',
            cancelButtonTitle: '取消',
            doneButtonTitle: '完成',
          ),
        ],
      );

      if (croppedFile != null && mounted) {
        setState(() {
          _croppedFile = File(croppedFile.path);
          // 重置縮放
          _transformationController.value = Matrix4.identity();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('裁剪完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('裁剪失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─── 儲存到相簿 ───

  Future<void> _handleSave() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final filePath = _croppedFile?.path ?? await _downloadToTemp();

      await Gal.putImage(filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已儲存至相簿')),
        );
      }
    } on GalException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗：${e.type.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // 圖片主體
            Positioned.fill(
              child: Center(
                child: Hero(
                  tag: widget.heroTag,
                  child: GestureDetector(
                    onDoubleTapDown: _onDoubleTapDown,
                    onDoubleTap: _onDoubleTap,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 0.8,
                      maxScale: 4.0,
                      child: _croppedFile != null
                          ? Image.file(
                              _croppedFile!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white70,
                                  size: 48,
                                );
                              },
                            )
                          : FutureBuilder<File?>(
                              future: ref.read(imageCacheServiceProvider).getImage(widget.imageUrl),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(color: Colors.white),
                                  );
                                }
                                
                                if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                                  return const Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white70,
                                    size: 48,
                                  );
                                }
                                
                                return Image.file(
                                  snapshot.data!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white70,
                                      size: 48,
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // 底部操作列
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.share,
                      label: '分享',
                      onTap: _handleShare,
                    ),
                    _ActionButton(
                      icon: Icons.crop,
                      label: '裁剪',
                      onTap: _handleCrop,
                    ),
                    _ActionButton(
                      icon: Icons.download,
                      label: '儲存',
                      onTap: _handleSave,
                    ),
                  ],
                ),
              ),
            ),

            // Loading 遮罩
            if (_isProcessing)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 底部操作列的按鈕元件
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
