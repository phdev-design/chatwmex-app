import 'package:app/features/chat/providers/pip_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// 浮動 PiP 視窗 Widget
///
/// 由 [PipController] 透過 [OverlayEntry] 插入至根 Overlay。
/// 支援拖曳移動、吸附角落、播放/暫停、展開、關閉。
class PipOverlay extends ConsumerStatefulWidget {
  const PipOverlay({super.key});

  @override
  ConsumerState<PipOverlay> createState() => _PipOverlayState();
}

class _PipOverlayState extends ConsumerState<PipOverlay> {
  bool _hasError = false;
  YoutubePlayerController? _cachedController;

  void _onControllerUpdate() {
    if (_cachedController?.value.hasError == true && !_hasError) {
      if (mounted) {
        setState(() => _hasError = true);
        // 自動關閉 PiP Session
        ref.read(pipControllerProvider.notifier).closePip();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // 監聽 controller 錯誤（延後至 frame 結束後，確保 ref 可用）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cachedController =
          ref.read(pipControllerProvider.notifier).playerController;
      _cachedController?.addListener(_onControllerUpdate);
    });
  }

  @override
  void dispose() {
    _cachedController?.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pipState = ref.watch(pipControllerProvider);
    final pipNotifier = ref.read(pipControllerProvider.notifier);
    final controller = pipNotifier.playerController;

    if (!pipState.isActive) return const SizedBox.shrink();

    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          left: pipState.overlayPosition.dx,
          top: pipState.overlayPosition.dy,
          width: kPipWidth,
          height: kPipHeight,
          child: GestureDetector(
            onPanUpdate: (details) {
              pipNotifier.updatePosition(
                pipState.overlayPosition + details.delta,
              );
            },
            onPanEnd: (_) {
              pipNotifier.snapToCorner(MediaQuery.of(context).size);
            },
            child: _buildPipWindow(context, pipState, pipNotifier, controller),
          ),
        ),
      ],
    );
  }

  Widget _buildPipWindow(
    BuildContext context,
    PipState pipState,
    PipController pipNotifier,
    YoutubePlayerController? controller,
  ) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: kPipWidth,
        height: kPipHeight,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Video player or error state
            if (_hasError || controller == null)
              _buildErrorState()
            else
              _buildVideoPlayer(controller),

            // Control buttons overlay — shown whenever PiP is active
            _buildControls(context, pipState, pipNotifier),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(YoutubePlayerController controller) {
    return SizedBox(
      width: kPipWidth,
      height: kPipHeight,
      child: YoutubePlayer(
        controller: controller,
        aspectRatio: 16 / 9,
        showVideoProgressIndicator: false,
      ),
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Icon(
        Icons.error_outline,
        color: Colors.white,
        size: 32,
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    PipState pipState,
    PipController pipNotifier,
  ) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Close button — top-left
          Positioned(
            top: 4,
            left: 4,
            child: _ControlButton(
              key: const Key('pip_close_button'),
              icon: Icons.close,
              onTap: () => pipNotifier.closePip(),
            ),
          ),

          // Play/Pause button — center
          Center(
            child: _ControlButton(
              key: const Key('pip_play_pause_button'),
              icon: pipState.isPlaying ? Icons.pause : Icons.play_arrow,
              onTap: () => pipNotifier.togglePlayPause(),
              size: 32,
            ),
          ),

          // Expand button — top-right
          Positioned(
            top: 4,
            right: 4,
            child: _ControlButton(
              key: const Key('pip_expand_button'),
              icon: Icons.open_in_full,
              onTap: () => pipNotifier.expandPip(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small icon button used in PiP overlay controls.
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const _ControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: size,
        ),
      ),
    );
  }
}
