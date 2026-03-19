import 'package:app/features/chat/providers/pip_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// 獨立 YouTube 播放 Screen
///
/// 透過 [Navigator.push] 開啟，顯示 YouTube 播放器及相關控制項。
/// 支援畫中畫（PiP）模式，點擊 PiP 按鈕後將播放器縮小為浮動視窗。
class YouTubePlayerScreen extends ConsumerStatefulWidget {
  /// YouTube 影片 ID（必要）
  final String videoId;

  /// 是否從 PiP 展開而來（預設 false）
  /// true = 從 PiP 展開，controller 由 PipController 持有
  final bool fromPip;

  const YouTubePlayerScreen({
    super.key,
    required this.videoId,
    this.fromPip = false,
  });

  @override
  ConsumerState<YouTubePlayerScreen> createState() =>
      _YouTubePlayerScreenState();
}

class _YouTubePlayerScreenState extends ConsumerState<YouTubePlayerScreen> {
  YoutubePlayerController? _controller;
  bool _hasError = false;

  late bool _pipWasActive;

  @override
  void initState() {
    super.initState();
    _pipWasActive = false;
    if (widget.fromPip) {
      // 從 PiP 展開：取回 PipController 持有的 controller
      final pipController = ref.read(pipControllerProvider.notifier);
      _controller = pipController.playerController;
    } else {
      // 首次開啟：建立新的 controller
      _controller = YoutubePlayerController(
        initialVideoId: widget.videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          hideControls: false,
          showLiveFullscreenButton: true,
        ),
      );
    }
    _controller?.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (_controller?.value.hasError == true && !_hasError) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    // 若無進行中的 PiP Session，釋放 controller
    if (!_pipWasActive) {
      _controller?.dispose();
    }
    super.dispose();
  }

  void _onPipButtonTapped() {
    final controller = _controller;
    if (controller == null) return;
    final pipController = ref.read(pipControllerProvider.notifier);
    pipController.startPip(
      videoId: widget.videoId,
      controller: controller,
      context: context,
    );
    // 標記 PiP 已啟動，dispose 時不釋放 controller
    _pipWasActive = true;
    // 移除 listener 以避免 dispose 時重複操作
    _controller?.removeListener(_onControllerUpdate);
    _controller = null;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError || _controller == null) {
      return _buildErrorScreen();
    }

    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _controller!,
        aspectRatio: 16 / 9,
        showVideoProgressIndicator: true,
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text(
              'YouTube',
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.picture_in_picture_alt,
                  color: Colors.white,
                ),
                tooltip: '畫中畫',
                onPressed: _onPipButtonTapped,
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 16:9 播放器
              AspectRatio(
                aspectRatio: 16 / 9,
                child: player,
              ),
              // 標題區域
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.videoId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            const Text(
              '無法載入影片',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
