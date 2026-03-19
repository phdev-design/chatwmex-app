import 'package:app/features/chat/providers/pip_controller.dart';
import 'package:app/features/chat/ui/widgets/pip_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

// ─── Test Doubles ─────────────────────────────────────────────────────────────

/// Fake YoutubePlayerController that avoids platform channel calls.
class _FakeYoutubePlayerController extends YoutubePlayerController {
  int disposeCount = 0;

  _FakeYoutubePlayerController({String videoId = 'test_video_id'})
      : super(initialVideoId: videoId);

  @override
  void dispose() {
    disposeCount++;
    // Do NOT call super.dispose() to avoid platform channel calls in tests
  }
}

// ─── Fake PipController ───────────────────────────────────────────────────────

/// A PipController subclass that records method calls for verification.
class _RecordingPipController extends PipController {
  int closePipCallCount = 0;
  int expandPipCallCount = 0;
  int snapToCornerCallCount = 0;
  int updatePositionCallCount = 0;

  _RecordingPipController();

  /// Returns null so YoutubePlayer is not rendered (avoids platform channel issues in tests)
  @override
  YoutubePlayerController? get playerController => null;

  @override
  void closePip() {
    closePipCallCount++;
    // Update state without disposing the fake controller
    state = const PipState();
  }

  @override
  void expandPip(BuildContext context) {
    expandPipCallCount++;
  }

  @override
  void snapToCorner(Size screenSize) {
    snapToCornerCallCount++;
    super.snapToCorner(screenSize);
  }

  @override
  void updatePosition(Offset position) {
    updatePositionCallCount++;
    super.updatePosition(position);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Pumps a [PipOverlay] inside a [ProviderScope] with an active PiP session.
Future<_RecordingPipController> _pumpPipOverlay(
  WidgetTester tester, {
  bool isPlaying = true,
}) async {
  final fakeController = _FakeYoutubePlayerController();
  final pipController = _RecordingPipController();

  // Activate the PiP session via injectControllerForTest.
  // _RecordingPipController.playerController returns null, so YoutubePlayer
  // is never rendered (avoids platform channel issues in tests).
  pipController.injectControllerForTest(fakeController, 'test_video_id');
  if (!isPlaying) {
    pipController.setPlayingForTest(false);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pipControllerProvider.overrideWith((_) => pipController),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PipOverlay(),
            ],
          ),
        ),
      ),
    ),
  );

  // Pump once to settle layout
  await tester.pump();

  return pipController;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('PipOverlay Widget 測試', () {
    // Requirements: 3.2, 3.3, 3.4, 3.5

    testWidgets('顯示播放/暫停、展開、關閉按鈕', (tester) async {
      await _pumpPipOverlay(tester);

      expect(find.byKey(const Key('pip_play_pause_button')), findsOneWidget);
      expect(find.byKey(const Key('pip_expand_button')), findsOneWidget);
      expect(find.byKey(const Key('pip_close_button')), findsOneWidget);
    });

    testWidgets('播放中時顯示暫停圖示', (tester) async {
      await _pumpPipOverlay(tester, isPlaying: true);

      // The play/pause button should show pause icon when playing
      final pauseIcon = find.descendant(
        of: find.byKey(const Key('pip_play_pause_button')),
        matching: find.byIcon(Icons.pause),
      );
      expect(pauseIcon, findsOneWidget);
    });

    testWidgets('暫停中時顯示播放圖示', (tester) async {
      await _pumpPipOverlay(tester, isPlaying: false);

      final playIcon = find.descendant(
        of: find.byKey(const Key('pip_play_pause_button')),
        matching: find.byIcon(Icons.play_arrow),
      );
      expect(playIcon, findsOneWidget);
    });

    testWidgets('點擊關閉按鈕呼叫 closePip', (tester) async {
      // Requirements: 3.4
      final pipController = await _pumpPipOverlay(tester);

      await tester.tap(find.byKey(const Key('pip_close_button')));
      await tester.pump();

      expect(pipController.closePipCallCount, equals(1));
    });

    testWidgets('點擊展開按鈕呼叫 expandPip', (tester) async {
      // Requirements: 3.3
      final pipController = await _pumpPipOverlay(tester);

      await tester.tap(find.byKey(const Key('pip_expand_button')));
      await tester.pump();

      expect(pipController.expandPipCallCount, equals(1));
    });

    testWidgets('拖曳後觸發 snapToCorner', (tester) async {
      // Requirements: 3.5
      final pipController = await _pumpPipOverlay(tester);

      // Perform a drag gesture on the PipOverlay
      final overlayFinder = find.byType(PipOverlay);
      expect(overlayFinder, findsOneWidget);

      // Simulate a pan gesture: start, move, end
      final gesture = await tester.startGesture(const Offset(50, 150));
      await gesture.moveBy(const Offset(30, 20));
      await gesture.up();
      await tester.pump();

      expect(pipController.snapToCornerCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets('拖曳中呼叫 updatePosition', (tester) async {
      // Requirements: 3.1
      final pipController = await _pumpPipOverlay(tester);

      final gesture = await tester.startGesture(const Offset(50, 150));
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(pipController.updatePositionCallCount, greaterThanOrEqualTo(1));
    });

    testWidgets('PiP 未啟動時不顯示 overlay', (tester) async {
      final pipController = _RecordingPipController();
      // Do NOT inject controller — state.isActive remains false

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipControllerProvider.overrideWith((_) => pipController),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [PipOverlay()],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Buttons should not be visible when PiP is inactive
      expect(find.byKey(const Key('pip_close_button')), findsNothing);
      expect(find.byKey(const Key('pip_expand_button')), findsNothing);
      expect(find.byKey(const Key('pip_play_pause_button')), findsNothing);
    });

    testWidgets('PipOverlay 尺寸為 200×112.5 (16:9)', (tester) async {
      await _pumpPipOverlay(tester);

      // Find the AnimatedPositioned and verify its size constraints
      final animatedPositioned = tester.widget<AnimatedPositioned>(
        find.byType(AnimatedPositioned),
      );
      expect(animatedPositioned.width, equals(kPipWidth));
      expect(animatedPositioned.height, equals(kPipHeight));
    });
  });
}
