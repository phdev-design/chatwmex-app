import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/models/message.dart';
import 'package:app/core/media/cached_network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Property 1: Bug Condition** - Decryption Failure Messages Render as Text
/// **Validates: Requirements 1.1, 1.2, 1.3**
///
/// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
/// DO NOT attempt to fix the test or the code when it fails
/// NOTE: This test encodes the expected behavior - it will validate the fix when it passes after implementation
/// GOAL: Surface counterexamples that demonstrate the bug exists
void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  final params = ChatRoomParams(
    roomId: 'room-1',
    isRoom: true,
    currentUserId: 'me',
    token: 'token',
  );

  group('Bug Condition Exploration - Decryption Failure Messages', () {
    testWidgets(
      'WHEN msg.type == MessageType.image AND msg.content starts with 🔒 '
      'THEN should render as text bubble (not ImageWidget) and no network request',
      (tester) async {
        // Arrange: Create a message with decryption failure text
        final msg = Message(
          id: 'm1',
          content: '🔒 此訊息無法解密（金鑰已更新）',
          senderId: 'u1',
          type: MessageType.image, // Type is image but content is error text
          createdAt: DateTime.now(),
        );
        const state = ChatRoomState();

        // Act: Render the message bubble
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: msg,
              isMe: false,
              state: state,
              params: params,
              isRoom: true,
              currentUserId: 'me',
              title: 'room',
              onScrollToMessage: (_) async {},
            ),
          ),
        );
        // Use pump instead of pumpAndSettle to avoid waiting for network requests
        await tester.pump();

        // Assert: Should render as text, not as image widget
        // EXPECTED TO FAIL on unfixed code: Currently renders as CachedNetworkImageWidget
        expect(
          find.byType(CachedNetworkImageWidget),
          findsNothing,
          reason: 'Decryption failure message should NOT use CachedNetworkImageWidget',
        );

        // Assert: Should display the error text
        // EXPECTED TO FAIL on unfixed code: Text is not displayed, shows broken_image instead
        expect(
          find.text('🔒 此訊息無法解密（金鑰已更新）'),
          findsOneWidget,
          reason: 'Decryption failure message should be displayed as text',
        );

        // Assert: Should not show broken image icon
        // EXPECTED TO FAIL on unfixed code: Shows broken_image icon due to invalid URL
        expect(
          find.byIcon(Icons.broken_image),
          findsNothing,
          reason: 'Should not show broken image icon for decryption failure',
        );
      },
    );

    testWidgets(
      'WHEN msg.content = "🔒 解密失敗" '
      'THEN should render as text bubble',
      (tester) async {
        // Arrange: Another decryption failure message
        final msg = Message(
          id: 'm2',
          content: '🔒 解密失敗',
          senderId: 'u1',
          type: MessageType.image,
          createdAt: DateTime.now(),
        );
        const state = ChatRoomState();

        // Act
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: msg,
              isMe: true,
              state: state,
              params: params,
              isRoom: true,
              currentUserId: 'me',
              title: 'room',
              onScrollToMessage: (_) async {},
            ),
          ),
        );
        // Use pump instead of pumpAndSettle to avoid waiting for network requests
        await tester.pump();

        // Assert: Should not use image widget
        expect(
          find.byType(CachedNetworkImageWidget),
          findsNothing,
          reason: 'Should not render decryption failure as image',
        );

        // Assert: Should display the text
        expect(
          find.text('🔒 解密失敗'),
          findsOneWidget,
          reason: 'Should display decryption failure text',
        );
      },
    );

    testWidgets(
      'WHEN msg.content starts with 🔒 (various decryption failure messages) '
      'THEN should render as text bubble',
      (tester) async {
        // Test multiple variations of decryption failure messages
        final testCases = [
          '🔒 此訊息無法解密',
          '🔒 Message cannot be decrypted',
          '🔒 金鑰已更新',
        ];

        for (final content in testCases) {
          final msg = Message(
            id: 'msg-$content',
            content: content,
            senderId: 'u1',
            type: MessageType.image,
            createdAt: DateTime.now(),
          );
          const state = ChatRoomState();

          await tester.pumpWidget(
            wrap(
              MessageBubble(
                msg: msg,
                isMe: false,
                state: state,
                params: params,
                isRoom: true,
                currentUserId: 'me',
                title: 'room',
                onScrollToMessage: (_) async {},
              ),
            ),
          );
          // Use pump instead of pumpAndSettle to avoid waiting for network requests
          await tester.pump();

          // Should not use image widget
          expect(
            find.byType(CachedNetworkImageWidget),
            findsNothing,
            reason: 'Content "$content" should not render as image',
          );

          // Should display the text
          expect(
            find.text(content),
            findsOneWidget,
            reason: 'Content "$content" should be displayed as text',
          );
        }
      },
    );
  });
}
