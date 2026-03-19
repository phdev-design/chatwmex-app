import 'package:flutter/material.dart';
import 'package:glados/glados.dart';
import 'package:test/test.dart';
import 'package:app/features/chat/providers/pip_controller.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

// ─── Test Doubles ─────────────────────────────────────────────────────────────

/// A fake YoutubePlayerController that tracks dispose calls without
/// requiring platform channels.
class _FakeYoutubePlayerController extends YoutubePlayerController {
  int disposeCount = 0;

  _FakeYoutubePlayerController()
      : super(initialVideoId: 'test_video_id');

  @override
  void dispose() {
    disposeCount++;
    // Do NOT call super.dispose() to avoid platform channel calls in tests
  }
}

// ─── Generators ──────────────────────────────────────────────────────────────

/// 從 seed 產生一個合理的播放位置（0..3600 秒）
Duration _seedToPlaybackPosition(int seed) {
  final seconds = seed.abs() % 3601; // 0..3600 秒
  return Duration(seconds: seconds);
}

/// 從 seed 產生一個合理的 Video ID（11 個字元，英數字）
String _seedToVideoId(int seed) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-';
  final s = seed.abs();
  final buffer = StringBuffer();
  for (var i = 0; i < 11; i++) {
    buffer.write(chars[(s ~/ (i + 1)) % chars.length]);
  }
  return buffer.toString();
}

// ─── Property 1：PiP 播放位置 Round-Trip ─────────────────────────────────────

/// Feature: youtube-player-screen-pip, Property 1: PiP 播放位置 Round-Trip
///
/// **Validates: Requirements 6.1, 6.4, 3.3**
///
/// 對任意有效的 Video ID 與任意播放位置 t，從 YouTubePlayerScreen 切換至 PiP
/// 再展開回 YouTubePlayerScreen，PipController 記錄的播放位置與展開後播放器的
/// 起始位置之差應不超過 2 秒。
///
/// 測試策略：
/// - 使用 injectControllerForTest 模擬 startPip（繞過 Overlay）
/// - 使用 setPositionForTest 直接設定 state.position（模擬播放位置追蹤）
/// - 驗證 expandPip 後 state.position 保持不變（誤差 0，遠小於 2 秒上限）
void _property1Tests() {
  group('Property 1: PiP 播放位置 Round-Trip', () {
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 1: PiP 播放位置 Round-Trip
      '對任意播放位置，PiP 切換後 state.position 誤差不超過 2 秒',
      (seed) {
        final controller = PipController();
        final fake = _FakeYoutubePlayerController();
        final videoId = _seedToVideoId(seed);
        final position = _seedToPlaybackPosition(seed);

        // 模擬 startPip：注入 controller 並設定 active 狀態
        controller.injectControllerForTest(fake, videoId);
        expect(controller.state.isActive, isTrue);

        // 模擬播放位置追蹤：設定當前播放位置
        controller.setPositionForTest(position);
        expect(controller.state.position, equals(position));

        // 記錄進入 PiP 時的位置
        final positionAtPipStart = controller.state.position;

        // 模擬 expandPip：關閉 PiP overlay（不 dispose controller），
        // 驗證 state.position 保持不變（供 YouTubePlayerScreen 讀取）
        controller.closePipWithoutDispose();

        // 驗證：position 保持不變，誤差為 0（遠小於 2 秒上限）
        final positionAfterExpand = controller.state.position;
        final diff = (positionAfterExpand - positionAtPipStart).abs();

        expect(
          diff,
          lessThanOrEqualTo(const Duration(seconds: 2)),
          reason: 'PiP round-trip 後播放位置誤差應不超過 2 秒，'
              'videoId=$videoId, position=$position, '
              'positionAtPipStart=$positionAtPipStart, '
              'positionAfterExpand=$positionAfterExpand, diff=$diff',
        );

        controller.dispose();
      },
    );
  });
}

// ─── Property 7：PiP 暫停狀態保持 ────────────────────────────────────────────

/// Feature: youtube-player-screen-pip, Property 7: PiP 暫停狀態保持
///
/// **Validates: Requirements 6.3**
///
/// 對任意 PiP Session，若在 PiP 模式下暫停影片後展開至 YouTubePlayerScreen，
/// 播放器應保持暫停狀態（isPlaying == false），不自動重新播放。
void _property7Tests() {
  group('Property 7: PiP 暫停狀態保持', () {
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 7: PiP 暫停狀態保持
      '在 PiP 模式下暫停後展開，isPlaying 應保持 false',
      (seed) {
        final controller = PipController();
        final fake = _FakeYoutubePlayerController();
        final videoId = _seedToVideoId(seed);

        // 啟動 PiP Session
        controller.injectControllerForTest(fake, videoId);
        expect(controller.state.isActive, isTrue);
        expect(controller.state.isPlaying, isTrue,
            reason: 'PiP 啟動後預設應為播放中');

        // 在 PiP 模式下暫停
        controller.setPlayingForTest(false);
        expect(controller.state.isPlaying, isFalse,
            reason: '設定暫停後 isPlaying 應為 false');

        // 記錄展開前的暫停狀態
        final isPlayingBeforeExpand = controller.state.isPlaying;
        expect(isPlayingBeforeExpand, isFalse);

        // 模擬 expandPip：關閉 PiP overlay，保留 isPlaying 狀態
        // YouTubePlayerScreen 讀取 state.isPlaying 來決定初始播放狀態
        controller.closePipWithoutDispose();

        // 驗證：isPlaying 狀態保持 false（YouTubePlayerScreen 應讀取此值）
        // 注意：closePipWithoutDispose 保留 isPlaying 狀態供 Screen 讀取
        expect(
          controller.state.isPlaying,
          isFalse,
          reason: 'PiP 暫停後展開，isPlaying 應保持 false，不自動重新播放',
        );

        controller.dispose();
      },
    );
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  _property1Tests();
  _property7Tests();
}
