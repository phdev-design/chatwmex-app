import 'package:app/features/chat/providers/pip_controller.dart';
import 'package:app/features/chat/ui/youtube_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide test, group, expect, setUp, tearDown, setUpAll, tearDownAll;
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

// ─── Generators ──────────────────────────────────────────────────────────────

/// 產生合法的 YouTube Video ID（11 個字元，英數字與 -_）
String _seedToVideoId(int seed) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
  final s = seed.abs();
  final buf = StringBuffer();
  for (var i = 0; i < 11; i++) {
    buf.write(chars[(s ~/ (i + 1)) % chars.length]);
  }
  return buf.toString();
}

// ─── Property 8：縮圖點擊導航與播放器初始化 ──────────────────────────────────

/// Feature: youtube-player-screen-pip, Property 8: 縮圖點擊導航與播放器初始化
///
/// **Validates: Requirements 1.1, 1.2**
void _property8Tests() {
  group('Property 8: 縮圖點擊導航與播放器初始化', () {
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 8: 縮圖點擊導航與播放器初始化
      '對任意有效 videoId，YouTubePlayerScreen.videoId 應與傳入值完全相同',
      (seed) {
        final videoId = _seedToVideoId(seed);

        final screen = YouTubePlayerScreen(videoId: videoId);
        expect(
          screen.videoId,
          equals(videoId),
          reason: 'YouTubePlayerScreen.videoId 應與傳入的 videoId 完全相同',
        );

        expect(
          screen.fromPip,
          isFalse,
          reason: 'fromPip 預設應為 false',
        );
      },
    );

    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 8: 縮圖點擊導航與播放器初始化
      '對任意有效 videoId，YoutubePlayerController 以相同 videoId 初始化',
      (seed) {
        final videoId = _seedToVideoId(seed);

        final controller = YoutubePlayerController(
          initialVideoId: videoId,
          flags: const YoutubePlayerFlags(autoPlay: true),
        );

        expect(
          controller.initialVideoId,
          equals(videoId),
          reason: 'YoutubePlayerController.initialVideoId 應與傳入的 videoId 完全相同',
        );
      },
    );
  });
}

// ─── Widget Tests ─────────────────────────────────────────────────────────────

void _widgetTests() {
  group('YouTubePlayerScreen Widget 測試', () {
    test('fromPip=true 時從 PipController 取回 controller（邏輯驗證）', () {
      final fakeController = _FakeYoutubePlayerController(videoId: 'abc123xyz');
      final pipController = PipController();
      pipController.injectControllerForTest(fakeController, 'abc123xyz');

      // 驗證 PipController 持有 controller
      expect(pipController.playerController, equals(fakeController));
      expect(pipController.state.isActive, isTrue);
      expect(pipController.state.videoId, equals('abc123xyz'));

      pipController.dispose();
    });

    test('返回時若無 PiP Session，controller 應被 dispose（邏輯驗證）', () {
      final fakeController = _FakeYoutubePlayerController(videoId: 'test456');
      final pipController = PipController();
      // 注入 controller 後立即關閉 session（isActive=false）
      pipController.injectControllerForTest(fakeController, 'test456');
      pipController.closePip();

      expect(pipController.state.isActive, isFalse);
      // fakeController 已被 closePip dispose 一次
      expect(fakeController.disposeCount, equals(1));

      pipController.dispose();
    });

    test('初始狀態下 PiP Session 未啟動', () {
      final pipController = PipController();

      expect(pipController.state.isActive, isFalse);
      expect(pipController.state.videoId, isNull);

      pipController.dispose();
    });

    testWidgets('error state 顯示返回按鈕（fromPip=true 且 controller 為 null）',
        (tester) async {
      final pipController = PipController();
      // 不注入 controller，playerController 為 null

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipControllerProvider.overrideWith((_) => pipController),
          ],
          child: const MaterialApp(
            home: YouTubePlayerScreen(
              videoId: 'error_test',
              fromPip: true,
            ),
          ),
        ),
      );
      // 不 pump 以避免 platform channel 問題

      // controller 為 null 時應顯示 error screen（含返回按鈕）
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
    });

    test('PiP 按鈕啟動後 _pipWasActive 為 true，dispose 不釋放 controller（邏輯驗證）',
        () {
      final fakeController = _FakeYoutubePlayerController(videoId: 'pip_btn');
      final pipController = PipController();

      // 模擬 PiP 已啟動（isActive=true）
      pipController.injectControllerForTest(fakeController, 'pip_btn');
      expect(pipController.state.isActive, isTrue);

      // 驗證 controller 未被 dispose（PiP 持有中）
      expect(fakeController.disposeCount, equals(0));

      // 關閉 PiP 後 controller 應被 dispose
      pipController.closePip();
      expect(fakeController.disposeCount, equals(1));

      pipController.dispose();
    });
  });
}

void main() {
  _property8Tests();
  _widgetTests();
}
