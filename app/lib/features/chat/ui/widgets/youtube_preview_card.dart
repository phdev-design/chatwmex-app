import 'package:app/core/media/cached_network_image_widget.dart';
import 'package:app/features/chat/providers/pip_controller.dart';
import 'package:app/features/chat/ui/youtube_player_screen.dart';
import 'package:app/features/chat/utils/youtube_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// YouTube 影片縮圖預覽卡片
///
/// 顯示影片縮圖與播放按鈕，點擊後導航至 [YouTubePlayerScreen]。
/// 若有進行中的 PiP Session，會先關閉再導航。
class YouTubePreviewCard extends ConsumerStatefulWidget {
  /// YouTube 影片 ID（11 個字元）
  final String videoId;

  /// 是否為自己發送的訊息（保留供未來主題色使用）
  final bool isMe;

  /// 縮圖最大寬度（通常為 MediaQuery.of(context).size.width * 0.65）
  final double maxWidth;

  const YouTubePreviewCard({
    super.key,
    required this.videoId,
    required this.isMe,
    required this.maxWidth,
  });

  @override
  ConsumerState<YouTubePreviewCard> createState() =>
      _YouTubePreviewCardState();
}

class _YouTubePreviewCardState extends ConsumerState<YouTubePreviewCard> {
  @override
  Widget build(BuildContext context) {
    return _buildThumbnail();
  }

  Widget _buildThumbnail() {
    final thumbnailUrl = YouTubeDetector.thumbnailUrl(widget.videoId);
    final height = widget.maxWidth * 9 / 16;

    return GestureDetector(
      onTap: () {
        final pipState = ref.read(pipControllerProvider);
        if (pipState.isActive) {
          ref.read(pipControllerProvider.notifier).closePip();
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => YouTubePlayerScreen(videoId: widget.videoId),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: widget.maxWidth,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 縮圖
              CachedNetworkImageWidget(
                imageUrl: thumbnailUrl,
                width: widget.maxWidth,
                height: height,
                fit: BoxFit.cover,
                errorWidget: Container(
                  width: widget.maxWidth,
                  height: height,
                  color: Colors.grey[900],
                  child: const Center(
                    child: Icon(
                      Icons.smart_display,
                      color: Colors.red,
                      size: 48,
                    ),
                  ),
                ),
              ),
              // 播放按鈕疊加層
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_circle_filled,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
