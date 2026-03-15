import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/media/image_cache_service.dart';

/// 帶快取功能的網路圖片 Widget
/// 
/// 自動處理圖片快取，優先從本地讀取，沒有則下載
/// 支援 E2EE 加密圖片的解密
class CachedNetworkImageWidget extends ConsumerStatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Alignment alignment;
  /// 🔐 E2EE: 可選的解密金鑰，若提供則會解密圖片
  final String? fileKey;

  const CachedNetworkImageWidget({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.alignment = Alignment.center,
    this.fileKey,
  });

  @override
  ConsumerState<CachedNetworkImageWidget> createState() =>
      _CachedNetworkImageWidgetState();
}

class _CachedNetworkImageWidgetState
    extends ConsumerState<CachedNetworkImageWidget> {
  File? _cachedFile;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedNetworkImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl || 
        oldWidget.fileKey != widget.fileKey) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _cachedFile = null;
    });

    try {
      final cacheService = ref.read(imageCacheServiceProvider);
      // 🔐 傳遞 fileKey 給 getImage，若有則會解密
      final file = await cacheService.getImage(
        widget.imageUrl,
        fileKey: widget.fileKey,
      );

      if (!mounted) return;

      if (file != null && await file.exists()) {
        setState(() {
          _cachedFile = file;
          _isLoading = false;
        });
      } else {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
    }

    if (_hasError || _cachedFile == null) {
      return widget.errorWidget ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Center(
              child: Icon(Icons.broken_image, color: Colors.grey),
            ),
          );
    }

    return Image.file(
      _cachedFile!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      errorBuilder: (context, error, stackTrace) {
        return widget.errorWidget ??
            SizedBox(
              width: widget.width,
              height: widget.height,
              child: const Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            );
      },
    );
  }
}
