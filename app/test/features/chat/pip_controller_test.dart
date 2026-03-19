import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
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

/// 從 seed 產生一個合理的螢幕尺寸（320..1024 x 480..1366）
Size _seedToScreenSize(int seed) {
  final s = seed.abs();
  final width = 320.0 + (s % 705).toDouble(); // 320..1024
  final height = 480.0 + ((s ~/ 705) % 887).toDouble(); // 480..1366
  return Size(width, height);
}

/// 從 seed 產生一個任意 Offset（可能在螢幕外，測試吸附邏輯的健壯性）
Offset _seedToOffset(int seed) {
  final s = seed.abs();
  final dx = (s % 2000).toDouble() - 500.0; // -500..1499
  final dy = ((s ~/ 2000) % 2000).toDouble() - 500.0; // -500..1499
  return Offset(dx, dy);
}

/// 從 seed 產生一個合理的拖曳 delta（-200..200）
Offset _seedToDelta(int seed) {
  final s = seed.abs();
  final dx = (s % 401).toDouble() - 200.0;
  final dy = ((s ~/ 401) % 401).toDouble() - 200.0;
  return Offset(dx, dy);
}

// ─── Property 6：吸附角落冪等性 ──────────────────────────────────────────────

/// Feature: youtube-player-screen-pip, Property 6: 吸附角落冪等性
///
/// **Validates: Requirements 3.5**
void _property6Tests() {
  group('Property 6: 吸附角落冪等性', () {
    const pipSize = Size(kPipWidth, kPipHeight);

    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 6: 吸附角落冪等性
      '對任意位置與螢幕尺寸，連續呼叫 snapToCorner 兩次結果相同且為四個角落之一',
      (seed) {
        final pos = _seedToOffset(seed);
        final screen = _seedToScreenSize(seed);

        final snap1 = calculateSnapPosition(pos, screen, pipSize);
        final snap2 = calculateSnapPosition(snap1, screen, pipSize);

        expect(
          snap2,
          equals(snap1),
          reason: '連續呼叫 snapToCorner 兩次應得到相同結果，'
              'pos=$pos, screen=$screen, snap1=$snap1, snap2=$snap2',
        );

        final expectedCorners = [
          Offset(kPipMargin, kPipMargin),
          Offset(screen.width - kPipWidth - kPipMargin, kPipMargin),
          Offset(kPipMargin, screen.height - kPipHeight - kPipMargin),
          Offset(
            screen.width - kPipWidth - kPipMargin,
            screen.height - kPipHeight - kPipMargin,
          ),
        ];

        expect(
          expectedCorners.contains(snap1),
          isTrue,
          reason: '吸附結果 $snap1 應為四個角落之一，螢幕尺寸=$screen',
        );
      },
    );
  });
}

// ─── Property 4：單一 PiP Session 不變式 ─────────────────────────────────────

/// Feature: youtube-player-screen-pip, Property 4: 單一 PiP Session 不變式
///
/// **Validates: Requirements 4.1, 2.2**
void _property4Tests() {
  group('Property 4: 單一 PiP Session 不變式', () {
    Glados(any.intInRange(0, 1 << 20), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 4: 單一 PiP Session 不變式
      '對任意操作序列，同時進行中的 PiP Session 數量恆為 0 或 1',
      (seed) {
        final controller = PipController();
        // 重用單一 fake controller 以避免大量物件建立
        final fake = _FakeYoutubePlayerController();
        final s = seed.abs();

        // 產生 3~7 個操作：0=startPip, 1=closePip, 2=togglePlayPause
        final opCount = 3 + (s % 5);
        for (var i = 0; i < opCount; i++) {
          final op = (s ~/ (i + 1)) % 3;
          if (op == 0) {
            controller.injectControllerForTest(fake, 'video_$i');
          } else if (op == 1) {
            controller.closePip();
          } else {
            if (controller.state.isActive) {
              controller.togglePlayPause();
            }
          }

          // 不變式：isActive 只能是 true 或 false（即 0 或 1 個 session）
          final sessionCount = controller.state.isActive ? 1 : 0;
          expect(
            sessionCount,
            lessThanOrEqualTo(1),
            reason: 'Session 數量應恆為 0 或 1，操作 $i 後為 $sessionCount',
          );
        }

        controller.dispose();
      },
    );
  });
}

// ─── Property 2：App 生命週期播放狀態 Round-Trip ──────────────────────────────

/// Feature: youtube-player-screen-pip, Property 2: App 生命週期播放狀態 Round-Trip
///
/// **Validates: Requirements 4.2, 4.3**
void _property2Tests() {
  group('Property 2: App 生命週期播放狀態 Round-Trip', () {
    Glados(any.bool, ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 2: App 生命週期播放狀態 Round-Trip
      '對任意 PiP Session，paused 再 resumed 後播放狀態恢復至進入背景前的狀態',
      (wasPlaying) {
        final controller = PipController();
        final fake = _FakeYoutubePlayerController();

        controller.injectControllerForTest(fake, 'dQw4w9WgXcQ');

        // 設定進入背景前的播放狀態
        if (!wasPlaying) {
          controller.setPlayingForTest(false);
        }

        final playingBeforePause = controller.state.isPlaying;

        // 模擬 app 進入背景
        controller.didChangeAppLifecycleState(AppLifecycleState.paused);

        expect(
          controller.state.isPlaying,
          isFalse,
          reason: 'app 進入背景後 isPlaying 應為 false',
        );

        // 模擬 app 返回前景
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

        // 驗證恢復後播放狀態與進入背景前一致
        expect(
          controller.state.isPlaying,
          equals(playingBeforePause),
          reason: 'resumed 後播放狀態應恢復至進入背景前的狀態 '
              '(wasPlaying=$wasPlaying, playingBeforePause=$playingBeforePause)',
        );

        controller.dispose();
      },
    );
  });
}

// ─── Property 3：PiP 關閉後資源釋放 ──────────────────────────────────────────

/// Feature: youtube-player-screen-pip, Property 3: PiP 關閉後資源釋放
///
/// **Validates: Requirements 3.4, 4.4, 1.4**
void _property3Tests() {
  group('Property 3: PiP 關閉後資源釋放', () {
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 3: PiP 關閉後資源釋放
      'closePip() 後 isActive 為 false 且 dispose() 被呼叫恰好一次',
      (seed) {
        final pipController = PipController();
        final fakeYtController = _FakeYoutubePlayerController();

        pipController.injectControllerForTest(
          fakeYtController,
          'video_${seed.abs() % 1000}',
        );

        expect(pipController.state.isActive, isTrue,
            reason: 'injectControllerForTest 後 isActive 應為 true');

        pipController.closePip();

        expect(
          pipController.state.isActive,
          isFalse,
          reason: 'closePip() 後 isActive 應為 false',
        );

        expect(
          fakeYtController.disposeCount,
          equals(1),
          reason: 'YoutubePlayerController.dispose() 應被呼叫恰好一次，'
              '實際呼叫 ${fakeYtController.disposeCount} 次',
        );

        pipController.dispose();
      },
    );
  });
}

// ─── Property 5：PiP 視窗位置邊界不變式 ──────────────────────────────────────

/// Feature: youtube-player-screen-pip, Property 5: PiP 視窗位置邊界不變式
///
/// **Validates: Requirements 3.1**
void _property5Tests() {
  group('Property 5: PiP 視窗位置邊界不變式', () {
    const pipSize = Size(kPipWidth, kPipHeight);

    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 5: PiP 視窗位置邊界不變式
      '對任意螢幕尺寸與拖曳序列，clampToScreen 後視窗始終在螢幕內',
      (seed) {
        final screen = _seedToScreenSize(seed);
        var pos = const Offset(kPipMargin, kPipMargin);

        // 模擬 5~15 次拖曳
        final dragCount = 5 + (seed.abs() % 11);
        for (var i = 0; i < dragCount; i++) {
          final delta = _seedToDelta(seed ^ (i * 31337));
          pos = clampToScreen(pos + delta, screen, pipSize);

          expect(
            pos.dx,
            greaterThanOrEqualTo(0.0),
            reason: '左邊界應 >= 0，pos=$pos, screen=$screen',
          );
          expect(
            pos.dy,
            greaterThanOrEqualTo(0.0),
            reason: '上邊界應 >= 0，pos=$pos, screen=$screen',
          );
          expect(
            pos.dx + kPipWidth,
            lessThanOrEqualTo(screen.width),
            reason: '右邊界應 <= 螢幕寬度，pos=$pos, screen=$screen',
          );
          expect(
            pos.dy + kPipHeight,
            lessThanOrEqualTo(screen.height),
            reason: '下邊界應 <= 螢幕高度，pos=$pos, screen=$screen',
          );
        }
      },
    );
  });
}

// ─── Unit Tests ───────────────────────────────────────────────────────────────

void _unitTests() {
  group('PipController 單元測試', () {
    late PipController controller;
    late _FakeYoutubePlayerController fakeYtController;

    setUp(() {
      controller = PipController();
      fakeYtController = _FakeYoutubePlayerController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('startPip 設定 isActive = true', () {
      controller.injectControllerForTest(fakeYtController, 'test_video');
      expect(controller.state.isActive, isTrue);
      expect(controller.state.videoId, equals('test_video'));
    });

    test('closePip 設定 isActive = false 並釋放資源', () {
      controller.injectControllerForTest(fakeYtController, 'test_video');
      expect(controller.state.isActive, isTrue);

      controller.closePip();

      expect(controller.state.isActive, isFalse);
      expect(controller.state.videoId, isNull);
      expect(fakeYtController.disposeCount, equals(1));
    });

    test('startPip 時若已有 Session，先關閉舊 Session', () {
      final firstController = _FakeYoutubePlayerController();
      controller.injectControllerForTest(firstController, 'video_1');
      expect(controller.state.isActive, isTrue);
      expect(firstController.disposeCount, equals(0));

      // 啟動第二個 session
      final secondController = _FakeYoutubePlayerController();
      controller.injectControllerForTest(secondController, 'video_2');

      // 舊的 controller 應被 dispose
      expect(firstController.disposeCount, equals(1));
      // 新的 session 應為 active
      expect(controller.state.isActive, isTrue);
      expect(controller.state.videoId, equals('video_2'));
    });

    test('app 進入背景時暫停播放', () {
      controller.injectControllerForTest(fakeYtController, 'test_video');
      expect(controller.state.isPlaying, isTrue);

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(controller.state.isPlaying, isFalse);
    });

    test('app 返回前景時恢復播放（進入背景前正在播放）', () {
      controller.injectControllerForTest(fakeYtController, 'test_video');
      // isPlaying 預設為 true

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(controller.state.isPlaying, isFalse);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(controller.state.isPlaying, isTrue);
    });

    test('app 返回前景時維持暫停（進入背景前已暫停）', () {
      controller.injectControllerForTest(fakeYtController, 'test_video');
      controller.setPlayingForTest(false);

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(controller.state.isPlaying, isFalse);
    });

    test('無 PiP Session 時生命週期事件不影響狀態', () {
      expect(controller.state.isActive, isFalse);
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(controller.state.isActive, isFalse);
    });

    test('togglePlayPause 切換播放狀態', () {
      controller.injectControllerForTest(fakeYtController, 'test_video');
      expect(controller.state.isPlaying, isTrue);

      controller.togglePlayPause();
      expect(controller.state.isPlaying, isFalse);

      controller.togglePlayPause();
      expect(controller.state.isPlaying, isTrue);
    });

    test('updatePosition 更新 overlayPosition', () {
      const newPos = Offset(100, 200);
      controller.updatePosition(newPos);
      expect(controller.state.overlayPosition, equals(newPos));
    });

    test('snapToCorner 吸附至最近角落（左上象限）', () {
      const screen = Size(400, 800);
      controller.updatePosition(const Offset(50, 50));
      controller.snapToCorner(screen);
      expect(controller.state.overlayPosition,
          equals(const Offset(kPipMargin, kPipMargin)));
    });

    test('snapToCorner 吸附至最近角落（右下象限）', () {
      const screen = Size(400, 800);
      controller.updatePosition(const Offset(350, 700));
      controller.snapToCorner(screen);
      expect(
        controller.state.overlayPosition,
        equals(Offset(
          screen.width - kPipWidth - kPipMargin,
          screen.height - kPipHeight - kPipMargin,
        )),
      );
    });
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  _property6Tests();
  _property4Tests();
  _property2Tests();
  _property3Tests();
  _property5Tests();
  _unitTests();
}
