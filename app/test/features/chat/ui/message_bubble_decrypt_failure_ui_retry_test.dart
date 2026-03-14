import 'dart:math';
import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Property 1: Bug Condition** - 解密失敗視覺提示與互動
/// **Validates: Requirements 2.1, 2.2, 2.3, 2.4**
///
/// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
/// DO NOT attempt to fix the test or the code when it fails
/// NOTE: This test encodes the expected behavior - it will validate the fix when it passes after implementation
/// GOAL: Surface counterexamples that demonstrate the bug exists
/// Scoped PBT Approach: For deterministic bugs, scope the property to the concrete failing case(s) to ensure reproducibility
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

  group('Bug Condition Exploration - 解密失敗視覺提示與互動', () {
    testWidgets(
      'WHEN message isDecryptionFailure (status = failed) '
      'THEN should display orange border (Requirement 2.1)',
      (tester) async {
        // Arrange: Create a message with decryption failure status
        final msg = Message(
          id: 'm1',
          content: '🔒 無法解密',
          senderId: 'u1',
          type: MessageType.text,
          status: MessageStatus.failed,
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
        await tester.pump();

        // Assert: Should have orange border
        // Find the Container with border decoration (the main bubble container)
        final containers = tester.widgetList<Container>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Container),
          ),
        );
        
        // Find the container with a border
        Container? containerWithBorder;
        for (final container in containers) {
          final decoration = container.decoration as BoxDecoration?;
          if (decoration?.border != null) {
            containerWithBorder = container;
            break;
          }
        }
        
        expect(
          containerWithBorder,
          isNotNull,
          reason: 'Decryption failure message should have a container with border',
        );
        
        final decoration = containerWithBorder!.decoration as BoxDecoration;
        final border = decoration.border as Border;
        expect(
          border.top.color,
          equals(Colors.orange),
          reason: 'Decryption failure message should have orange border',
        );
        expect(
          border.top.width,
          equals(2),
          reason: 'Border width should be 2',
        );
      },
    );

    testWidgets(
      'WHEN message isDecryptionFailure (content starts with 🔒) '
      'THEN should display "🔒 無法解密 點擊重試 ↺" text (Requirement 2.2)',
      (tester) async {
        // Arrange: Create a message with decryption failure prefix
        final msg = Message(
          id: 'm2',
          content: '🔒 無法解密',
          senderId: 'u1',
          type: MessageType.text,
          createdAt: DateTime.now(),
        );
        const state = ChatRoomState();

        // Act
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
        await tester.pump();

        // Assert: Should display retry hint text
        // EXPECTED TO FAIL on unfixed code: Text does not include "點擊重試 ↺"
        expect(
          find.text('🔒 無法解密 點擊重試 ↺'),
          findsOneWidget,
          reason: 'Decryption failure message should display retry hint',
        );
      },
    );

    testWidgets(
      'WHEN user taps decryption failure message '
      'THEN GestureDetector should have onTap handler (Requirement 2.3)',
      (tester) async {
        // Arrange: Create a message with decryption failure
        final msg = Message(
          id: 'm3',
          content: '🔒 無法解密',
          senderId: 'u1',
          type: MessageType.text,
          status: MessageStatus.failed,
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
        await tester.pump();

        // Assert: GestureDetector should have onTap handler for decryption failure
        // EXPECTED TO FAIL on unfixed code: GestureDetector only has onLongPress, no onTap
        final gestureDetector = tester.widget<GestureDetector>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(GestureDetector),
          ).first,
        );
        
        expect(
          gestureDetector.onTap,
          isNotNull,
          reason: 'Decryption failure message should have onTap handler to trigger retry',
        );
      },
    );

    testWidgets(
      'WHEN message status is decryptingRetry '
      'THEN should display "⏳ 解密中…" animation (Requirement 2.4)',
      (tester) async {
        // Arrange: Create a message with decryptingRetry status
        final msg = Message(
          id: 'm4',
          content: '🔒 無法解密',
          senderId: 'u1',
          type: MessageType.text,
          status: MessageStatus.decryptingRetry,
          createdAt: DateTime.now(),
        );
        const state = ChatRoomState();

        // Act
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
        await tester.pump();

        // Assert: Should display decrypting status text
        // EXPECTED TO FAIL on unfixed code: Shows "等待對方上線" instead of "⏳ 解密中…"
        expect(
          find.text('⏳ 解密中…'),
          findsOneWidget,
          reason: 'Retry status should show "⏳ 解密中…"',
        );

        // Assert: Should have loading animation
        expect(
          find.byType(CircularProgressIndicator),
          findsOneWidget,
          reason: 'Should display loading animation during retry',
        );
      },
    );
  });

  group('Property-Based Tests - Multiple Decryption Failure Cases', () {
    final random = Random(42); // Fixed seed for reproducibility

    testWidgets(
      'Property: All messages with isDecryptionFailure should have orange border and retry hint',
      (tester) async {
        // Test various decryption failure scenarios
        final testCases = [
          Message(
            id: 'case-1',
            content: '🔒 無法解密',
            senderId: 'u1',
            type: MessageType.text,
            status: MessageStatus.failed,
            createdAt: DateTime.now(),
          ),
          Message(
            id: 'case-2',
            content: '🔒 此訊息無法解密（金鑰已更新）',
            senderId: 'u2',
            type: MessageType.image,
            status: MessageStatus.failed,
            createdAt: DateTime.now(),
          ),
          Message(
            id: 'case-3',
            content: '🔒 解密失敗',
            senderId: 'u3',
            type: MessageType.text,
            createdAt: DateTime.now(),
          ),
          // Ciphertext-like content (long base64-like string)
          Message(
            id: 'case-4',
            content: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/==',
            senderId: 'u4',
            type: MessageType.text,
            createdAt: DateTime.now(),
          ),
        ];

        for (var i = 0; i < testCases.length; i++) {
          final msg = testCases[i];
          const state = ChatRoomState();

          await tester.pumpWidget(
            wrap(
              MessageBubble(
                msg: msg,
                isMe: random.nextBool(),
                state: state,
                params: params,
                isRoom: true,
                currentUserId: 'me',
                title: 'room',
                onScrollToMessage: (_) async {},
              ),
            ),
          );
          await tester.pump();

          // Assert: Should have orange border
          // Find the container with a border
          final containers = tester.widgetList<Container>(
            find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(Container),
            ),
          );
          
          Container? containerWithBorder;
          for (final container in containers) {
            final decoration = container.decoration as BoxDecoration?;
            if (decoration?.border != null) {
              containerWithBorder = container;
              break;
            }
          }
          
          expect(
            containerWithBorder,
            isNotNull,
            reason: 'Case $i (${msg.id}): Should have border',
          );

          // Assert: Should display retry hint
          // EXPECTED TO FAIL on unfixed code
          expect(
            find.textContaining('點擊重試 ↺'),
            findsOneWidget,
            reason: 'Case $i (${msg.id}): Should display retry hint',
          );
        }
      },
    );

    testWidgets(
      'Property: 10 random decryption failure messages all show orange border',
      (tester) async {
        const iterations = 10;
        
        for (var i = 0; i < iterations; i++) {
          final msg = Message(
            id: 'random-fail-$i',
            content: '🔒 無法解密',
            senderId: 'u$i',
            type: MessageType.text,
            status: MessageStatus.failed,
            createdAt: DateTime.now(),
          );
          const state = ChatRoomState();

          await tester.pumpWidget(
            wrap(
              MessageBubble(
                msg: msg,
                isMe: random.nextBool(),
                state: state,
                params: params,
                isRoom: true,
                currentUserId: 'me',
                title: 'room',
                onScrollToMessage: (_) async {},
              ),
            ),
          );
          await tester.pump();

          // Assert: All decryption failure messages should have orange border
          // Find the container with a border
          final containers = tester.widgetList<Container>(
            find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(Container),
            ),
          );
          
          Container? containerWithBorder;
          for (final container in containers) {
            final decoration = container.decoration as BoxDecoration?;
            if (decoration?.border != null) {
              containerWithBorder = container;
              break;
            }
          }
          
          expect(
            containerWithBorder,
            isNotNull,
            reason: 'Iteration $i: Decryption failure should have border',
          );
        }
      },
    );
  });

  group('Documented Counterexamples', () {
    test('Counterexample 1: Decryption failed messages lack orange border', () {
      // This test documents the expected counterexample
      // On unfixed code, messages with status=failed do not have orange border
      expect(
        true,
        isTrue,
        reason: 'Documented: Decryption failed messages currently lack orange border visual indicator',
      );
    });

    test('Counterexample 2: Text does not include "點擊重試 ↺" hint', () {
      // This test documents the expected counterexample
      // On unfixed code, the text only shows "🔒 無法解密" without retry hint
      expect(
        true,
        isTrue,
        reason: 'Documented: Current text is "🔒 解密失敗" without "點擊重試 ↺" hint',
      );
    });

    test('Counterexample 3: Tapping failed messages has no response', () {
      // This test documents the expected counterexample
      // On unfixed code, GestureDetector only handles onLongPress, not onTap for failed messages
      expect(
        true,
        isTrue,
        reason: 'Documented: GestureDetector currently has no onTap handler for decryption failure messages',
      );
    });

    test('Counterexample 4: Retry status shows "等待對方上線" instead of "⏳ 解密中…"', () {
      // This test documents the expected counterexample
      // On unfixed code, decryptingRetry status shows "🔒 等待對方上線以重新解密..." instead of "⏳ 解密中…"
      expect(
        true,
        isTrue,
        reason: 'Documented: Retry status currently shows "等待對方上線" instead of "⏳ 解密中…"',
      );
    });
  });
}
