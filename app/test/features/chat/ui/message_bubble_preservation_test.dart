import 'dart:math';
import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/models/message.dart';
import 'package:app/core/media/cached_network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Property 2: Preservation** - Valid Image URLs Continue to Load
/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4**
///
/// CRITICAL: These tests MUST PASS on unfixed code - they capture baseline behavior
/// These tests ensure the fix doesn't break existing functionality
/// GOAL: Verify all non-buggy inputs continue to work as before
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

  group('Preservation Property Tests - Valid Image URLs Continue to Load', () {
    testWidgets(
      'Property: Valid image URLs (https://example.com/image.jpg) load normally via CachedNetworkImageWidget',
      (tester) async {
        // Arrange: Create a message with a valid image URL
        final msg = Message(
          id: 'm1',
          content: 'https://example.com/image.jpg',
          senderId: 'u1',
          type: MessageType.image,
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

        // Assert: Should use CachedNetworkImageWidget for valid URLs
        expect(
          find.byType(CachedNetworkImageWidget),
          findsOneWidget,
          reason: 'Valid image URLs should continue to use CachedNetworkImageWidget',
        );

        // Assert: Should NOT display the URL as text
        expect(
          find.text('https://example.com/image.jpg'),
          findsNothing,
          reason: 'Valid image URLs should be rendered as images, not text',
        );
      },
    );

    testWidgets(
      'Property: Multiple valid image URL formats load normally',
      (tester) async {
        // Test various valid image URL formats
        final validUrls = [
          'https://example.com/photo.png',
          'https://cdn.example.com/images/pic.jpeg',
          'http://localhost:8080/image.gif',
          'https://example.com/path/to/image.webp',
        ];

        for (final url in validUrls) {
          final msg = Message(
            id: 'msg-$url',
            content: url,
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
          await tester.pump();

          // Should use CachedNetworkImageWidget
          expect(
            find.byType(CachedNetworkImageWidget),
            findsOneWidget,
            reason: 'URL "$url" should render as image',
          );

          // Should not display as text
          expect(
            find.text(url),
            findsNothing,
            reason: 'URL "$url" should not be displayed as text',
          );
        }
      },
    );

    testWidgets(
      'Property: Empty content displays existing error handling (broken_image icon)',
      (tester) async {
        // Arrange: Create a message with empty content
        final msg = Message(
          id: 'm2',
          content: '',
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

        // Assert: Should still use CachedNetworkImageWidget (which will show error)
        expect(
          find.byType(CachedNetworkImageWidget),
          findsOneWidget,
          reason: 'Empty content should continue to use CachedNetworkImageWidget',
        );

        // Note: The broken_image icon is shown by CachedNetworkImageWidget's errorWidget
        // We verify the widget is present, which maintains existing behavior
      },
    );

    testWidgets(
      'Property: Other message types (text, voice, file) render according to existing logic',
      (tester) async {
        // Test MessageType.text
        final textMsg = Message(
          id: 'text-1',
          content: 'Hello, this is a text message',
          senderId: 'u1',
          type: MessageType.text,
          createdAt: DateTime.now(),
        );
        const state = ChatRoomState();

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: textMsg,
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

        // Assert: Text message should display as text
        expect(
          find.text('Hello, this is a text message'),
          findsOneWidget,
          reason: 'Text messages should continue to display as text',
        );

        // Assert: Should NOT use CachedNetworkImageWidget
        expect(
          find.byType(CachedNetworkImageWidget),
          findsNothing,
          reason: 'Text messages should not use image widget',
        );
      },
    );

    testWidgets(
      'Property: File messages render with file icon and name',
      (tester) async {
        final fileMsg = Message(
          id: 'file-1',
          content: 'https://example.com/document.pdf',
          senderId: 'u1',
          type: MessageType.file,
          createdAt: DateTime.now(),
        );
        const state = ChatRoomState();

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: fileMsg,
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

        // Assert: File message should show file icon
        expect(
          find.byIcon(Icons.picture_as_pdf),
          findsOneWidget,
          reason: 'PDF files should continue to show PDF icon',
        );

        // Assert: Should display filename
        expect(
          find.text('document.pdf'),
          findsOneWidget,
          reason: 'File messages should continue to display filename',
        );

        // Assert: Should NOT use CachedNetworkImageWidget
        expect(
          find.byType(CachedNetworkImageWidget),
          findsNothing,
          reason: 'File messages should not use image widget',
        );
      },
    );

    testWidgets(
      'Property: Text messages with URLs do not render as images',
      (tester) async {
        // This tests that text messages containing URLs are not affected
        final textMsg = Message(
          id: 'text-url-1',
          content: 'Check out this image: https://example.com/image.jpg',
          senderId: 'u1',
          type: MessageType.text, // Type is text, not image
          createdAt: DateTime.now(),
        );
        const state = ChatRoomState();

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: textMsg,
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

        // Assert: Should display as text
        expect(
          find.text('Check out this image: https://example.com/image.jpg'),
          findsOneWidget,
          reason: 'Text messages with URLs should remain as text',
        );

        // Assert: Should NOT use CachedNetworkImageWidget
        expect(
          find.byType(CachedNetworkImageWidget),
          findsNothing,
          reason: 'Text messages should not use image widget',
        );
      },
    );
  });

  group('Property-Based Tests - Randomized Input Generation', () {
    final random = Random(42); // Fixed seed for reproducibility

    String generateRandomImageUrl() {
      final domains = ['example.com', 'cdn.example.com', 'images.test.com'];
      final paths = ['photo', 'image', 'pic', 'img'];
      final extensions = ['jpg', 'png', 'gif', 'webp', 'jpeg'];
      
      final domain = domains[random.nextInt(domains.length)];
      final path = paths[random.nextInt(paths.length)];
      final ext = extensions[random.nextInt(extensions.length)];
      final id = random.nextInt(10000);
      
      return 'https://$domain/$path$id.$ext';
    }

    String generateRandomText() {
      final words = ['Hello', 'World', 'Test', 'Message', 'Flutter', 'Dart'];
      final length = 3 + random.nextInt(5);
      final selectedWords = List.generate(
        length,
        (_) => words[random.nextInt(words.length)],
      );
      return selectedWords.join(' ');
    }

    testWidgets(
      'Property: 20 random valid image URLs all load via CachedNetworkImageWidget',
      (tester) async {
        const iterations = 20;
        
        for (var i = 0; i < iterations; i++) {
          final url = generateRandomImageUrl();
          final msg = Message(
            id: 'random-img-$i',
            content: url,
            senderId: 'u1',
            type: MessageType.image,
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

          // Assert: All valid URLs should use CachedNetworkImageWidget
          expect(
            find.byType(CachedNetworkImageWidget),
            findsOneWidget,
            reason: 'Random URL "$url" (iteration $i) should render as image',
          );

          // Assert: Should not display as text
          expect(
            find.text(url),
            findsNothing,
            reason: 'Random URL "$url" (iteration $i) should not be text',
          );
        }
      },
    );

    testWidgets(
      'Property: 20 random text messages all display as text (not images)',
      (tester) async {
        const iterations = 20;
        
        for (var i = 0; i < iterations; i++) {
          final text = generateRandomText();
          final msg = Message(
            id: 'random-text-$i',
            content: text,
            senderId: 'u1',
            type: MessageType.text,
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

          // Assert: Text messages should display as text
          expect(
            find.text(text),
            findsOneWidget,
            reason: 'Random text "$text" (iteration $i) should display as text',
          );

          // Assert: Should NOT use CachedNetworkImageWidget
          expect(
            find.byType(CachedNetworkImageWidget),
            findsNothing,
            reason: 'Random text "$text" (iteration $i) should not use image widget',
          );
        }
      },
    );

    testWidgets(
      'Property: Messages NOT starting with 🔒 are unaffected by the fix',
      (tester) async {
        // Generate various messages that don't start with 🔒
        final testCases = [
          ('https://example.com/image.jpg', MessageType.image, true), // Should use image widget
          ('Regular text message', MessageType.text, false), // Should not use image widget
          ('🎉 Celebration message', MessageType.text, false), // Different emoji
          ('Lock 🔒 in middle', MessageType.text, false), // 🔒 not at start
          ('https://example.com/file.pdf', MessageType.file, false), // File type
        ];

        for (var i = 0; i < testCases.length; i++) {
          final (content, type, shouldHaveImageWidget) = testCases[i];
          final msg = Message(
            id: 'non-lock-$i',
            content: content,
            senderId: 'u1',
            type: type,
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
          await tester.pump();

          // Assert: Image widget presence matches expected behavior
          if (shouldHaveImageWidget) {
            expect(
              find.byType(CachedNetworkImageWidget),
              findsOneWidget,
              reason: 'Content "$content" should use image widget',
            );
          } else {
            expect(
              find.byType(CachedNetworkImageWidget),
              findsNothing,
              reason: 'Content "$content" should not use image widget',
            );
          }
        }
      },
    );
  });

  group('Edge Cases - Preservation of Existing Behavior', () {
    testWidgets(
      'Edge case: Image message with only whitespace content',
      (tester) async {
        final msg = Message(
          id: 'whitespace',
          content: '   ',
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
        await tester.pump();

        // Should still use CachedNetworkImageWidget (existing behavior)
        expect(
          find.byType(CachedNetworkImageWidget),
          findsOneWidget,
          reason: 'Whitespace content should maintain existing behavior',
        );
      },
    );

    testWidgets(
      'Edge case: Image message with URL containing special characters',
      (tester) async {
        final msg = Message(
          id: 'special-chars',
          content: 'https://example.com/image?id=123&size=large',
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
        await tester.pump();

        // Should use CachedNetworkImageWidget for URLs with query params
        expect(
          find.byType(CachedNetworkImageWidget),
          findsOneWidget,
          reason: 'URLs with query parameters should continue to work',
        );
      },
    );

    testWidgets(
      'Edge case: Text message starting with emoji (not 🔒)',
      (tester) async {
        final msg = Message(
          id: 'other-emoji',
          content: '😀 Happy message!',
          senderId: 'u1',
          type: MessageType.text,
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
        await tester.pump();

        // Should display as text
        expect(
          find.text('😀 Happy message!'),
          findsOneWidget,
          reason: 'Text messages with other emojis should remain as text',
        );

        // Should not use image widget
        expect(
          find.byType(CachedNetworkImageWidget),
          findsNothing,
          reason: 'Text messages should not use image widget',
        );
      },
    );
  });
}
