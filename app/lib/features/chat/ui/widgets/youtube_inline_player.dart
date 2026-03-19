import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// YouTube 內嵌播放器 Widget
///
/// 使用 youtube_player_flutter 套件在 chat bubble 內嵌入播放器。
/// 支援自動播放、播放控制列、全螢幕切換，並在發生錯誤時通知父 Widget。
class YouTubeInlinePlayer extends StatefulWidget {
  final String videoId;
  final double width;

  /// 播放器發生錯誤時的回調，父 Widget 可用來回退至縮圖狀態
  final VoidCallback? onError;

  const YouTubeInlinePlayer({
    super.key,
    required this.videoId,
    required this.width,
    this.onError,
  });

  @override
  State<YouTubeInlinePlayer> createState() => _YouTubeInlinePlayerState();
}

class _YouTubeInlinePlayerState extends State<YouTubeInlinePlayer> {
  late YoutubePlayerController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        hideControls: false,
        showLiveFullscreenButton: true,
      ),
    )..addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (_controller.value.hasError && !_hasError) {
      setState(() => _hasError = true);
      widget.onError?.call();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerUpdate)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.width * 9 / 16;

    if (_hasError) {
      return SizedBox(
        width: widget.width,
        height: height,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 32),
                SizedBox(height: 8),
                Text(
                  '無法載入影片',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: YoutubePlayerBuilder(
          player: YoutubePlayer(
            controller: _controller,
            width: widget.width,
            aspectRatio: 16 / 9,
            showVideoProgressIndicator: true,
          ),
          builder: (context, player) => player,
        ),
      ),
    );
  }
}
