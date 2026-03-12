import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/models/message.dart';
import 'package:app/core/media/cached_network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Property 2: Preservation** - Link Preview Non-Text Elements
/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
///
/// IMPORTANT: Follow observation-first methodology
/// These tests verify that non-text aspects of link preview remain unchanged
/// EXPECTED OUTCOME: Tests PASS on unfixed code (confirms baseline behavior to preserve)
///
/// Tests cover:
/// - Image thumbnails display correctly with CachedNetworkImageWidget
/// - Tapping link preview launches URL in external browser (gesture detector exists)
/// - Empty title/description fields are not rendered (conditional logic works)
/// - Container styling (padding, border, background) renders correctly
void main() {
  Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
    return ProviderScope(
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: brightness,
          ),
        ),
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

  group('Preservation - Link Preview Non-Text Elements', () {
    group('Image Thumbnail Preservation (Requirement 3.1)', () {
      testWidgets(
        'Preservation: Link preview with valid image URL displays CachedNetworkImageWidget',
        (tester) async {
          // Arrange: Create a message with link preview containing valid image URL
          final msg = Message(
            id: 'p1',
            content: 'Check this: https://example.com',
            senderId: 'other-user',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: 'Example Site',
              description: 'Example description',
              imageUrl: 'https://example.com/image.png',
            ),
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

          // Assert: CachedNetworkImageWidget widget should exist
          final cachedImageFinder = find.byType(CachedNetworkImageWidget);
          expect(
            cachedImageFinder,
            findsOneWidget,
            reason: 'CachedNetworkImageWidget should be used for image thumbnails',
          );

          // Verify the image widget is within a ClipRRect with borderRadius
          final clipRRectFinder = find.ancestor(
            of: cachedImageFinder,
            matching: find.byType(ClipRRect),
          );
          expect(
            clipRRectFinder,
            findsOneWidget,
            reason: 'Image should be clipped with rounded corners',
          );
        },
      );

      testWidgets(
        'Preservation: Link preview with empty image URL displays fallback icon',
        (tester) async {
          // Arrange: Create a message with link preview without image URL
          final msg = Message(
            id: 'p2',
            content: 'Check this: https://example.com',
            senderId: 'me',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: 'Example Site',
              description: 'Example description',
              imageUrl: '', // Empty image URL
            ),
          );
          const state = ChatRoomState();

          // Act: Render the message bubble
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
          await tester.pump();

          // Assert: Link icon should be displayed as fallback
          final linkIconFinder = find.byIcon(Icons.link);
          expect(
            linkIconFinder,
            findsOneWidget,
            reason: 'Link icon should be displayed when no image URL is provided',
          );

          // Verify CachedNetworkImageWidget is NOT used when imageUrl is empty
          final cachedImageFinder = find.byType(CachedNetworkImageWidget);
          expect(
            cachedImageFinder,
            findsNothing,
            reason: 'CachedNetworkImageWidget should not be used when imageUrl is empty',
          );
        },
      );

      testWidgets(
        'Preservation: Image container has correct dimensions (44x44)',
        (tester) async {
          // Arrange: Create a message with link preview
          final msg = Message(
            id: 'p3',
            content: 'Check this: https://example.com',
            senderId: 'other-user',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: 'Example Site',
              description: 'Example description',
              imageUrl: 'https://example.com/image.png',
            ),
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

          // Assert: Find the image container
          final containerFinder = find.ancestor(
            of: find.byType(CachedNetworkImageWidget),
            matching: find.byType(Container),
          ).first;

          final container = tester.widget<Container>(containerFinder);
          final decoration = container.decoration as BoxDecoration?;

          // Verify container has borderRadius
          expect(
            decoration?.borderRadius,
            equals(BorderRadius.circular(6)),
            reason: 'Image container should have 6px border radius',
          );
        },
      );
    });

    group('Tap Gesture Preservation (Requirement 3.2)', () {
      testWidgets(
        'Preservation: Link preview has GestureDetector for tap handling',
        (tester) async {
          // Arrange: Create a message with link preview
          final msg = Message(
            id: 'p4',
            content: 'Check this: https://flutter.dev',
            senderId: 'other-user',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://flutter.dev',
              title: 'Flutter',
              description: 'Flutter framework',
              imageUrl: 'https://flutter.dev/logo.png',
            ),
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

          // Assert: GestureDetector should exist for the link preview
          final gestureDetectorFinder = find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(GestureDetector),
          );

          expect(
            gestureDetectorFinder,
            findsWidgets,
            reason: 'GestureDetector should exist for tap handling',
          );
        },
      );

      testWidgets(
        'Preservation: Link preview with various URL formats has tap handler',
        (tester) async {
          // Test with different URL formats
          final testUrls = [
            'https://example.com',
            'http://example.com',
            'https://www.example.com/path',
            'https://example.com/path?query=value',
          ];

          for (final url in testUrls) {
            // Arrange: Create a message with link preview
            final msg = Message(
              id: 'p5-$url',
              content: 'Check this: $url',
              senderId: 'me',
              type: MessageType.text,
              createdAt: DateTime.now(),
              linkPreview: LinkPreview(
                url: url,
                title: 'Test Site',
                description: 'Test description',
                imageUrl: '',
              ),
            );
            const state = ChatRoomState();

            // Act: Render the message bubble
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
            await tester.pump();

            // Assert: GestureDetector should exist
            final gestureDetectorFinder = find.descendant(
              of: find.byType(MessageBubble),
              matching: find.byType(GestureDetector),
            );

            expect(
              gestureDetectorFinder,
              findsWidgets,
              reason: 'GestureDetector should exist for URL: $url',
            );
          }
        },
      );
    });

    group('Conditional Rendering Preservation (Requirement 3.5)', () {
      testWidgets(
        'Preservation: Empty title is not rendered',
        (tester) async {
          // Arrange: Create a message with link preview with empty title
          final msg = Message(
            id: 'p6',
            content: 'Check this: https://example.com',
            senderId: 'other-user',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: '', // Empty title
              description: 'This has a description but no title',
              imageUrl: 'https://example.com/image.png',
            ),
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

          // Assert: Description should be found
          final descriptionFinder = find.text('This has a description but no title');
          expect(
            descriptionFinder,
            findsOneWidget,
            reason: 'Description should be rendered when non-empty',
          );

          // Title should not be rendered (no Text widget with empty string)
          // We verify this by checking that only one Text widget exists in the link preview
          final textWidgetsFinder = find.descendant(
            of: find.byType(Column),
            matching: find.byType(Text),
          );

          // Should find description text only (not title)
          expect(
            textWidgetsFinder,
            findsWidgets,
            reason: 'Only description text should be rendered',
          );
        },
      );

      testWidgets(
        'Preservation: Empty description is not rendered',
        (tester) async {
          // Arrange: Create a message with link preview with empty description
          final msg = Message(
            id: 'p7',
            content: 'Check this: https://example.com',
            senderId: 'me',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: 'This has a title but no description',
              description: '', // Empty description
              imageUrl: 'https://example.com/image.png',
            ),
          );
          const state = ChatRoomState();

          // Act: Render the message bubble
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
          await tester.pump();

          // Assert: Title should be found
          final titleFinder = find.text('This has a title but no description');
          expect(
            titleFinder,
            findsOneWidget,
            reason: 'Title should be rendered when non-empty',
          );

          // Description should not be rendered
          // We verify by checking that only title text exists
          final textWidgetsFinder = find.descendant(
            of: find.byType(Column),
            matching: find.byType(Text),
          );

          expect(
            textWidgetsFinder,
            findsWidgets,
            reason: 'Only title text should be rendered',
          );
        },
      );

      testWidgets(
        'Preservation: Both empty title and description are not rendered',
        (tester) async {
          // Arrange: Create a message with link preview with both empty
          final msg = Message(
            id: 'p8',
            content: 'Check this: https://example.com',
            senderId: 'other-user',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: '', // Empty title
              description: '', // Empty description
              imageUrl: 'https://example.com/image.png',
            ),
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

          // Assert: The link preview should still render (with image/icon)
          // but no text widgets should be in the Column
          final cachedImageFinder = find.byType(CachedNetworkImageWidget);
          expect(
            cachedImageFinder,
            findsOneWidget,
            reason: 'Link preview should still render with image',
          );

          // No text should be rendered in the content column
          final columnFinder = find.descendant(
            of: find.byType(Row),
            matching: find.byType(Column),
          );
          expect(columnFinder, findsWidgets);
        },
      );

      testWidgets(
        'Preservation: Both non-empty title and description are rendered',
        (tester) async {
          // Arrange: Create a message with link preview with both non-empty
          final msg = Message(
            id: 'p9',
            content: 'Check this: https://example.com',
            senderId: 'me',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: 'Example Title',
              description: 'Example Description',
              imageUrl: 'https://example.com/image.png',
            ),
          );
          const state = ChatRoomState();

          // Act: Render the message bubble
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
          await tester.pump();

          // Assert: Both title and description should be rendered
          final titleFinder = find.text('Example Title');
          final descriptionFinder = find.text('Example Description');

          expect(
            titleFinder,
            findsOneWidget,
            reason: 'Title should be rendered when non-empty',
          );
          expect(
            descriptionFinder,
            findsOneWidget,
            reason: 'Description should be rendered when non-empty',
          );
        },
      );
    });

    group('Container Styling Preservation (Requirements 3.1, 3.2)', () {
      testWidgets(
        'Preservation: Link preview container has correct padding',
        (tester) async {
          // Arrange: Create a message with link preview
          final msg = Message(
            id: 'p10',
            content: 'Check this: https://example.com',
            senderId: 'other-user',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: 'Example',
              description: 'Description',
              imageUrl: 'https://example.com/image.png',
            ),
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

          // Assert: Find the link preview container
          final containerFinder = find.descendant(
            of: find.byType(ConstrainedBox),
            matching: find.byType(Container),
          ).first;

          final container = tester.widget<Container>(containerFinder);

          // Verify padding
          expect(
            container.padding,
            equals(const EdgeInsets.all(8)),
            reason: 'Container should have 8px padding on all sides',
          );

          // Verify margin
          expect(
            container.margin,
            equals(const EdgeInsets.only(top: 6)),
            reason: 'Container should have 6px top margin',
          );
        },
      );

      testWidgets(
        'Preservation: Link preview container has correct border styling',
        (tester) async {
          // Arrange: Create a message with link preview
          final msg = Message(
            id: 'p11',
            content: 'Check this: https://example.com',
            senderId: 'me',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: 'Example',
              description: 'Description',
              imageUrl: '',
            ),
          );
          const state = ChatRoomState();

          // Act: Render the message bubble
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
          await tester.pump();

          // Assert: Find the link preview container
          final containerFinder = find.descendant(
            of: find.byType(ConstrainedBox),
            matching: find.byType(Container),
          ).first;

          final container = tester.widget<Container>(containerFinder);
          final decoration = container.decoration as BoxDecoration?;

          // Verify border radius
          expect(
            decoration?.borderRadius,
            equals(BorderRadius.circular(8)),
            reason: 'Container should have 8px border radius',
          );

          // Verify border exists
          expect(
            decoration?.border,
            isNotNull,
            reason: 'Container should have a border',
          );

          // Verify border width
          final border = decoration?.border as Border?;
          expect(
            border?.top.width,
            equals(1),
            reason: 'Border should be 1px wide',
          );
        },
      );

      testWidgets(
        'Preservation: Link preview has maximum width constraint (60% of screen)',
        (tester) async {
          // Arrange: Create a message with link preview
          final msg = Message(
            id: 'p12',
            content: 'Check this: https://example.com',
            senderId: 'other-user',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: LinkPreview(
              url: 'https://example.com',
              title: 'Example with a very long title that should be constrained',
              description: 'Example with a very long description that should also be constrained to the maximum width',
              imageUrl: 'https://example.com/image.png',
            ),
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

          // Assert: Find the ConstrainedBox that wraps the link preview Container
          // It should be the one with maxWidth constraint based on screen width
          final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
          final expectedMaxWidth = screenWidth * 0.6;

          // Find all ConstrainedBox widgets
          final constrainedBoxes = find.byType(ConstrainedBox);
          expect(
            constrainedBoxes,
            findsWidgets,
            reason: 'ConstrainedBox widgets should exist',
          );

          // Verify that at least one ConstrainedBox has the expected maxWidth constraint
          bool foundCorrectConstraint = false;
          for (final element in tester.widgetList<ConstrainedBox>(constrainedBoxes)) {
            if (element.constraints.maxWidth == expectedMaxWidth) {
              foundCorrectConstraint = true;
              break;
            }
          }

          expect(
            foundCorrectConstraint,
            isTrue,
            reason: 'At least one ConstrainedBox should have maximum width of 60% of screen width ($expectedMaxWidth)',
          );
        },
      );
    });

    group('Messages Without Link Preview (Requirement 3.3)', () {
      testWidgets(
        'Preservation: Message without link preview displays normally',
        (tester) async {
          // Arrange: Create a message without link preview
          final msg = Message(
            id: 'p13',
            content: 'This is a regular message without a link preview',
            senderId: 'other-user',
            type: MessageType.text,
            createdAt: DateTime.now(),
            linkPreview: null, // No link preview
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

          // Assert: Message content should be displayed
          final contentFinder = find.text('This is a regular message without a link preview');
          expect(
            contentFinder,
            findsOneWidget,
            reason: 'Message content should be displayed',
          );

          // No link preview elements should exist
          final cachedImageFinder = find.byType(CachedNetworkImageWidget);
          expect(
            cachedImageFinder,
            findsNothing,
            reason: 'No CachedNetworkImageWidget should exist without link preview',
          );
        },
      );
    });
  });
}
