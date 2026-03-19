import 'package:app/features/chat/ui/widgets/pip_overlay.dart';
import 'package:app/features/chat/ui/youtube_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// PiP Session 狀態
class PipState {
  final bool isActive;
  final String? videoId;
  final Duration position;
  final bool isPlaying;
  final Offset overlayPosition;

  const PipState({
    this.isActive = false,
    this.videoId,
    this.position = Duration.zero,
    this.isPlaying = true,
    this.overlayPosition = const Offset(16, 100),
  });

  PipState copyWith({
    bool? isActive,
    String? videoId,
    Duration? position,
    bool? isPlaying,
    Offset? overlayPosition,
    bool clearVideoId = false,
  }) {
    return PipState(
      isActive: isActive ?? this.isActive,
      videoId: clearVideoId ? null : (videoId ?? this.videoId),
      position: position ?? this.position,
      isPlaying: isPlaying ?? this.isPlaying,
      overlayPosition: overlayPosition ?? this.overlayPosition,
    );
  }
}

/// PiP 視窗尺寸常數
const double kPipWidth = 200.0;
const double kPipHeight = 112.5;
const double kPipMargin = 16.0;

/// 計算吸附角落位置（純函式，可獨立測試）
Offset calculateSnapPosition(Offset current, Size screen, Size pip) {
  final cx = current.dx + pip.width / 2;
  final cy = current.dy + pip.height / 2;
  final snapX = cx < screen.width / 2
      ? kPipMargin
      : screen.width - pip.width - kPipMargin;
  final snapY = cy < screen.height / 2
      ? kPipMargin
      : screen.height - pip.height - kPipMargin;
  return Offset(snapX, snapY);
}

/// 將位置夾緊至螢幕邊界（純函式，可獨立測試）
Offset clampToScreen(Offset position, Size screen, Size pip) {
  final dx = position.dx.clamp(0.0, screen.width - pip.width);
  final dy = position.dy.clamp(0.0, screen.height - pip.height);
  return Offset(dx, dy);
}

class PipController extends StateNotifier<PipState>
    with WidgetsBindingObserver {
  OverlayEntry? _overlayEntry;
  YoutubePlayerController? _playerController;

  /// 記錄進入背景前的播放狀態，用於 resumed 時恢復
  bool _wasPlayingBeforePause = false;

  PipController() : super(const PipState()) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// 取得目前的 YoutubePlayerController（供 PipOverlay 使用）
  YoutubePlayerController? get playerController => _playerController;

  /// 啟動 PiP Session
  /// [controller] 為從 YouTubePlayerScreen 傳入的現有控制器（共享，不重建）
  void startPip({
    required String videoId,
    required YoutubePlayerController controller,
    required BuildContext context,
  }) {
    // 若已有 Session，先關閉舊的
    if (state.isActive) {
      closePip();
    }
    _playerController = controller;

    _overlayEntry = OverlayEntry(
      builder: (_) => const PipOverlay(),
    );

    Overlay.of(context).insert(_overlayEntry!);

    state = state.copyWith(
      isActive: true,
      videoId: videoId,
      isPlaying: true,
    );
  }

  /// 展開 PiP → 返回 YouTubePlayerScreen
  void expandPip(BuildContext context) {
    if (!state.isActive) return;
    final videoId = state.videoId;
    if (videoId == null) return;

    // 移除 overlay，但不 dispose controller（controller 移交給 YouTubePlayerScreen）
    _overlayEntry?.remove();
    _overlayEntry = null;

    // 更新狀態：isActive = false，保留 videoId 與 controller 供 Screen 取回
    state = state.copyWith(isActive: false);

    // 導航至 YouTubePlayerScreen（fromPip: true）
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => YouTubePlayerScreen(videoId: videoId, fromPip: true),
      ),
    );
  }

  /// 關閉 PiP Session，釋放資源
  void closePip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _playerController?.dispose();
    _playerController = null;
    _wasPlayingBeforePause = false;
    state = const PipState();
  }

  /// 更新 PiP 視窗位置（拖曳中）
  void updatePosition(Offset position) {
    state = state.copyWith(overlayPosition: position);
  }

  /// 吸附至最近角落
  void snapToCorner(Size screenSize) {
    final snapped = calculateSnapPosition(
      state.overlayPosition,
      screenSize,
      const Size(kPipWidth, kPipHeight),
    );
    state = state.copyWith(overlayPosition: snapped);
  }

  /// 切換播放/暫停
  void togglePlayPause() {
    if (state.isPlaying) {
      _playerController?.pause();
    } else {
      _playerController?.play();
    }
    state = state.copyWith(isPlaying: !state.isPlaying);
  }

  /// 測試用：直接注入 YoutubePlayerController 並設定 active 狀態（繞過 Overlay）
  @visibleForTesting
  void injectControllerForTest(
    YoutubePlayerController controller,
    String videoId,
  ) {
    if (state.isActive) {
      closePip();
    }
    _playerController = controller;
    state = state.copyWith(
      isActive: true,
      videoId: videoId,
      isPlaying: true,
    );
  }

  /// 測試用：直接設定 isPlaying 狀態（繞過 player controller）
  @visibleForTesting
  void setPlayingForTest(bool isPlaying) {
    state = state.copyWith(isPlaying: isPlaying);
  }

  /// 測試用：直接設定播放位置（模擬播放位置追蹤）
  @visibleForTesting
  void setPositionForTest(Duration position) {
    state = state.copyWith(position: position);
  }

  /// 測試用：模擬 expandPip 的 overlay 移除動作（不 dispose controller，
  /// 保留 isPlaying 與 position 狀態供 YouTubePlayerScreen 讀取）
  @visibleForTesting
  void closePipWithoutDispose() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    // 保留 position 與 isPlaying 狀態，僅將 isActive 設為 false
    state = state.copyWith(isActive: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!this.state.isActive) return;
    if (state == AppLifecycleState.paused) {
      // 記錄進入背景前的播放狀態
      _wasPlayingBeforePause = this.state.isPlaying;
      _playerController?.pause();
      this.state = this.state.copyWith(isPlaying: false);
    } else if (state == AppLifecycleState.resumed) {
      // 恢復至進入背景前的播放狀態
      if (_wasPlayingBeforePause) {
        _playerController?.play();
        this.state = this.state.copyWith(isPlaying: true);
      }
      // 若進入背景前已暫停，維持暫停狀態（isPlaying 已為 false）
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Guard against double-dispose (e.g., when ProviderScope also disposes)
    if (!mounted) return;
    closePip();
    super.dispose();
  }
}

final pipControllerProvider =
    StateNotifierProvider<PipController, PipState>((ref) => PipController());
