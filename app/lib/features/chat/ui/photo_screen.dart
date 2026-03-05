import 'package:flutter/material.dart';

class PhotoScreen extends StatefulWidget {
  final String imageUrl;
  final String heroTag;

  const PhotoScreen({super.key, required this.imageUrl, required this.heroTag});

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

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
                child: Image.network(
                  widget.imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 48,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
