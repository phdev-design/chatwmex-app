import 'package:app/features/chat/providers/pip_controller.dart';
import 'package:app/features/chat/ui/widgets/youtube_preview_card.dart';
import 'package:app/features/chat/utils/youtube_detector.dart';
import 'package:app/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide test, group, expect, setUp, tearDown, setUpAll, tearDownAll;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

// ─── Fake Controller ──────────────────────────────────────────────────────────

class _FakeYoutubePlayerController extends YoutubePlayerController {
  _FakeYoutubePlayerController({String videoId = 'test_video_id'})
      : super(initialVideoId: videoId);

  @override
  void dispose() {
    // Do NOT call super.dispose() to avoid platform channel calls in tests
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// 產生合法的 YouTube Video ID（11 個字元）
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

/// 建立一個含有 YouTube URL 的文字訊息
Message _makeTextMessageWithYouTube(String videoId) {
  return Message(
    id: 'test_id',
    content: 'https://www.youtube.com/watch?v=$videoId',
    senderId: 'sender',
    createdAt: DateTime(2024),
    type: MessageType.text,
    isDecrypted: true,
  );
}

/// 模擬 message_bubble.dart 中的 guard clause 邏輯，返回 youtubeVideoId 或 null
String? _applyGuardClause(Message msg) {
  final isDecryptingRetry = msg.status == MessageStatus.decryptingRetry;
  final looksLikeCiphertext = !msg.isDecrypted &&
      msg.content.length > 40 &&
      !msg.content.contains(' ') &&
      RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(msg.content.trim());
  final isDecryptionFailure =
      msg.content.startsWith('🔒') ||
      msg.status == MessageStatus.failed ||
      looksLikeCiphertext;

  return (!msg.isUnsent &&
          !isDecryptionFailure &&
          !isDecryptingRetry &&
          msg.type == MessageType.text)
      ? YouTubeDetector.extractVideoId(msg.content)
      : null;
}

// ─── Property 9：MessageBubble 狀態保護不變式 ─────────────────────────────────

/// Feature: youtube-player-screen-pip, Property 9: MessageBubble 狀態保護不變式
///
/// **Validates: Requirements 5.3**
void _property9Tests() {
  group('Property 9: MessageBubble 狀態保護不變式', () {
    // isUnsent = true 時，YouTubePreviewCard 不應被渲染
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 9: MessageBubble 狀態保護不變式
      '對任意 isUnsent=true 的訊息，guard clause 應攔截 YouTubeDetector，返回 null',
      (seed) {
        final videoId = _seedToVideoId(seed);
        final msg = _makeTextMessageWithYouTube(videoId).copyWith(
          isUnsent: true,
        );

        expect(
          _applyGuardClause(msg),
          isNull,
          reason: 'isUnsent=true 時 guard clause 應返回 null，不渲染 YouTubePreviewCard',
        );
      },
    );

    // isDecryptionFailure = true 時，YouTubePreviewCard 不應被渲染
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 9: MessageBubble 狀態保護不變式
      '對任意 decryptionFailure 狀態的訊息，guard clause 應攔截 YouTubeDetector，返回 null',
      (seed) {
        final videoId = _seedToVideoId(seed);
        // 使用 🔒 前綴觸發 isDecryptionFailure
        final msg = Message(
          id: 'test_id',
          content: '🔒 https://www.youtube.com/watch?v=$videoId',
          senderId: 'sender',
          createdAt: DateTime(2024),
          type: MessageType.text,
          isDecrypted: true,
        );

        expect(
          _applyGuardClause(msg),
          isNull,
          reason:
              'isDecryptionFailure=true 時 guard clause 應返回 null，不渲染 YouTubePreviewCard',
        );
      },
    );

    // isDecryptingRetry = true 時，YouTubePreviewCard 不應被渲染
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 9: MessageBubble 狀態保護不變式
      '對任意 decryptingRetry 狀態的訊息，guard clause 應攔截 YouTubeDetector，返回 null',
      (seed) {
        final videoId = _seedToVideoId(seed);
        final msg = _makeTextMessageWithYouTube(videoId).copyWith(
          status: MessageStatus.decryptingRetry,
        );

        expect(
          _applyGuardClause(msg),
          isNull,
          reason:
              'isDecryptingRetry=true 時 guard clause 應返回 null，不渲染 YouTubePreviewCard',
        );
      },
    );

    // 非文字訊息時，YouTubePreviewCard 不應被渲染
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 9: MessageBubble 狀態保護不變式
      '對任意非文字訊息（image/voice/video/file），guard clause 應攔截 YouTubeDetector，返回 null',
      (seed) {
        final videoId = _seedToVideoId(seed);
        final nonTextTypes = [
          MessageType.image,
          MessageType.voice,
          MessageType.video,
          MessageType.file,
        ];
        final msgType = nonTextTypes[seed % nonTextTypes.length];
        final msg = Message(
          id: 'test_id',
          content: 'https://www.youtube.com/watch?v=$videoId',
          senderId: 'sender',
          createdAt: DateTime(2024),
          type: msgType,
          isDecrypted: true,
        );

        expect(
          _applyGuardClause(msg),
          isNull,
          reason:
              '非文字訊息（$msgType）時 guard clause 應返回 null，不渲染 YouTubePreviewCard',
        );
      },
    );

    // 正常文字訊息含 YouTube URL 時，應正確提取 videoId（正向驗證）
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      // Feature: youtube-player-screen-pip, Property 9: MessageBubble 狀態保護不變式
      '對正常文字訊息含 YouTube URL，guard clause 應允許提取 videoId（正向驗證）',
      (seed) {
        final videoId = _seedToVideoId(seed);
        final msg = _makeTextMessageWithYouTube(videoId);

        expect(
          _applyGuardClause(msg),
          equals(videoId),
          reason: '正常文字訊息含 YouTube URL 時，guard clause 應允許提取 videoId',
        );
      },
    );
  });
}

// ─── Widget Tests ─────────────────────────────────────────────────────────────

void _widgetTests() {
  group('YouTubePreviewCard Widget 測試', () {
    testWidgets('點擊縮圖時若有 PiP Session 先關閉再導航', (tester) async {
      final pipController = PipController();
      pipController.injectControllerForTest(
        _FakeYoutubePlayerController(videoId: 'pip_video_1'),
        'pip_video_1',
      );
      expect(pipController.state.isActive, isTrue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipControllerProvider.overrideWith((_) => pipController),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: YouTubePreviewCard(
                videoId: 'dQw4w9WgXcQ',
                isMe: false,
                maxWidth: 300,
              ),
            ),
          ),
        ),
      );

      // Tap without pumping to avoid rendering YouTubePlayerScreen
      // (which requires InAppWebViewPlatform in tests)
      await tester.tap(find.byType(GestureDetector).first);
      // Do NOT pump — we only need to verify PiP was closed before navigation

      // PiP session 應已被關閉（closePip 在 Navigator.push 之前呼叫）
      expect(pipController.state.isActive, isFalse);
    });

    testWidgets('點擊縮圖時若無 PiP Session 直接導航（不呼叫 closePip）', (tester) async {
      final pipController = PipController();
      expect(pipController.state.isActive, isFalse);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipControllerProvider.overrideWith((_) => pipController),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: YouTubePreviewCard(
                videoId: 'dQw4w9WgXcQ',
                isMe: false,
                maxWidth: 300,
              ),
            ),
          ),
        ),
      );

      // Tap without pumping to avoid rendering YouTubePlayerScreen
      await tester.tap(find.byType(GestureDetector).first);
      // Do NOT pump — we only need to verify PiP state was not changed

      // PiP session 仍為 inactive（未被意外觸發）
      expect(pipController.state.isActive, isFalse);
    });

    testWidgets('縮圖顯示邏輯：ClipRRect 圓角為 8', (tester) async {
      final pipController = PipController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipControllerProvider.overrideWith((_) => pipController),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: YouTubePreviewCard(
                videoId: 'dQw4w9WgXcQ',
                isMe: false,
                maxWidth: 300,
              ),
            ),
          ),
        ),
      );

      final clipRRect = tester.widget<ClipRRect>(find.byType(ClipRRect).first);
      expect(
        clipRRect.borderRadius,
        equals(BorderRadius.circular(8)),
        reason: '縮圖應使用圓角 8 的 ClipRRect',
      );
    });

    testWidgets('縮圖顯示邏輯：顯示播放按鈕疊加層（play_circle_filled 圖示）',
        (tester) async {
      final pipController = PipController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipControllerProvider.overrideWith((_) => pipController),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: YouTubePreviewCard(
                videoId: 'dQw4w9WgXcQ',
                isMe: false,
                maxWidth: 300,
              ),
            ),
          ),
        ),
      );

      expect(
        find.byIcon(Icons.play_circle_filled),
        findsOneWidget,
        reason: '縮圖應顯示播放按鈕疊加層',
      );
    });

    testWidgets('縮圖尺寸符合 16:9 比例', (tester) async {
      final pipController = PipController();
      const maxWidth = 320.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipControllerProvider.overrideWith((_) => pipController),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: YouTubePreviewCard(
                videoId: 'dQw4w9WgXcQ',
                isMe: false,
                maxWidth: maxWidth,
              ),
            ),
          ),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(ClipRRect),
              matching: find.byType(SizedBox),
            )
            .first,
      );

      expect(sizedBox.width, equals(maxWidth));
      expect(
        sizedBox.height,
        closeTo(maxWidth * 9 / 16, 0.01),
        reason: '縮圖高度應為寬度的 9/16（16:9 比例）',
      );
    });
  });
}

// ─── Main ─────────────────────────────────────────────────────────────────────

void main() {
  _property9Tests();
  _widgetTests();
}
