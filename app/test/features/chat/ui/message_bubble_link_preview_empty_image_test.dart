import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/models/message.dart';
import 'package:app/core/media/cached_network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Task 3.2: Handle empty imageUrl in Link Preview rendering**
/// **Validates: Requirements 1.3, 2.3**
///
/// Tests verify that Link Preview correctly handles:
/// - null imageUrl → shows fallback icon
/// - empty string imageUrl → shows fallback icon
/// - encrypted/invalid imageUrl → shows fallback icon (resolveFullUrl returns empty)
/// - valid imageUrl → displays image correctly (preservation)
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

  group('Task 3.2 - Handle empty imageUrl in Link Preview', () {
    testWidgets(
      'Bug Fix: Link preview with null imageUrl shows fallback icon',
      (tester) async {
        // Arrange: Create a message with link preview with null imageUrl
        final msg = Message(
          id: 'test-null-image',
          content: 'Check this: https://example.com',
          senderId: 'other-user',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example.com',
            title: 'Example Site',
            description: 'Example description',
            imageUrl: null, // null imageUrl
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

        // Assert: Fallback icon should be displayed
        final linkIconFinder = find.byIcon(Icons.link);
        expect(
          linkIconFinder,
          findsOneWidget,
          reason: 'Fallback icon should be displayed when imageUrl is null',
        );

        // CachedNetworkImageWidget should NOT be used
        final cachedImageFinder = find.byType(CachedNetworkImageWidget);
        expect(
          cachedImageFinder,
          findsNothing,
          reason: 'CachedNetworkImageWidget should not be used when imageUrl is null',
        );
      },
    );

    testWidgets(
      'Bug Fix: Link preview with empty string imageUrl shows fallback icon',
      (tester) async {
        // Arrange: Create a message with link preview with empty imageUrl
        final msg = Message(
          id: 'test-empty-image',
          content: 'Check this: https://example.com',
          senderId: 'me',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example.com',
            title: 'Example Site',
            description: 'Example description',
            imageUrl: '', // empty imageUrl
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

        // Assert: Fallback icon should be displayed
        final linkIconFinder = find.byIcon(Icons.link);
        expect(
          linkIconFinder,
          findsOneWidget,
          reason: 'Fallback icon should be displayed when imageUrl is empty',
        );

        // CachedNetworkImageWidget should NOT be used
        final cachedImageFinder = find.byType(CachedNetworkImageWidget);
        expect(
          cachedImageFinder,
          findsNothing,
          reason: 'CachedNetworkImageWidget should not be used when imageUrl is empty',
        );
      },
    );

    testWidgets(
      'Bug Fix: Link preview with encrypted imageUrl (long Base64) shows fallback icon',
      (tester) async {
        // Arrange: Create a message with link preview with encrypted imageUrl
        // This simulates the bug condition where imageUrl contains encrypted content
        final msg = Message(
          id: 'test-encrypted-image',
          content: 'Check this: https://example.com',
          senderId: 'other-user',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example.com',
            title: 'Example Site',
            description: 'Example description',
            imageUrl: 'U2FsdGVkX1+abc123def456ghi789jkl012mno345pqr678stu901vwx234yz==', // encrypted Base64 string
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

        // Assert: Fallback icon should be displayed
        // resolveFullUrl will detect the long Base64 string and return empty string
        final linkIconFinder = find.byIcon(Icons.link);
        expect(
          linkIconFinder,
          findsOneWidget,
          reason: 'Fallback icon should be displayed when imageUrl is encrypted Base64',
        );

        // CachedNetworkImageWidget should NOT be used
        final cachedImageFinder = find.byType(CachedNetworkImageWidget);
        expect(
          cachedImageFinder,
          findsNothing,
          reason: 'CachedNetworkImageWidget should not be used when imageUrl is encrypted',
        );
      },
    );

    testWidgets(
      'Preservation: Link preview with valid imageUrl displays image correctly',
      (tester) async {
        // Arrange: Create a message with link preview with valid imageUrl
        final msg = Message(
          id: 'test-valid-image',
          content: 'Check this: https://example.com',
          senderId: 'me',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example.com',
            title: 'Example Site',
            description: 'Example description',
            imageUrl: 'https://example.com/image.png', // valid imageUrl
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

        // Assert: CachedNetworkImageWidget should be used
        final cachedImageFinder = find.byType(CachedNetworkImageWidget);
        expect(
          cachedImageFinder,
          findsOneWidget,
          reason: 'CachedNetworkImageWidget should be used when imageUrl is valid',
        );

        // Fallback icon should NOT be displayed
        final linkIconFinder = find.byIcon(Icons.link);
        expect(
          linkIconFinder,
          findsNothing,
          reason: 'Fallback icon should not be displayed when imageUrl is valid',
        );
      },
    );

    testWidgets(
      'Preservation: Link preview with relative path imageUrl displays image correctly',
      (tester) async {
        // Arrange: Create a message with link preview with relative path imageUrl
        final msg = Message(
          id: 'test-relative-image',
          content: 'Check this: https://example.com',
          senderId: 'other-user',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example.com',
            title: 'Example Site',
            description: 'Example description',
            imageUrl: '/uploads/images/abc123.jpg', // relative path
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

        // Assert: CachedNetworkImageWidget should be used
        final cachedImageFinder = find.byType(CachedNetworkImageWidget);
        expect(
          cachedImageFinder,
          findsOneWidget,
          reason: 'CachedNetworkImageWidget should be used when imageUrl is a relative path',
        );

        // Fallback icon should NOT be displayed
        final linkIconFinder = find.byIcon(Icons.link);
        expect(
          linkIconFinder,
          findsNothing,
          reason: 'Fallback icon should not be displayed when imageUrl is a relative path',
        );
      },
    );

    testWidgets(
      'Preservation: Link preview with MongoDB ObjectID imageUrl displays image correctly',
      (tester) async {
        // Arrange: Create a message with link preview with MongoDB ObjectID imageUrl
        final msg = Message(
          id: 'test-objectid-image',
          content: 'Check this: https://example.com',
          senderId: 'me',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example.com',
            title: 'Example Site',
            description: 'Example description',
            imageUrl: '507f1f77bcf86cd799439011', // MongoDB ObjectID (24 hex chars)
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

        // Assert: CachedNetworkImageWidget should be used
        final cachedImageFinder = find.byType(CachedNetworkImageWidget);
        expect(
          cachedImageFinder,
          findsOneWidget,
          reason: 'CachedNetworkImageWidget should be used when imageUrl is a MongoDB ObjectID',
        );

        // Fallback icon should NOT be displayed
        final linkIconFinder = find.byIcon(Icons.link);
        expect(
          linkIconFinder,
          findsNothing,
          reason: 'Fallback icon should not be displayed when imageUrl is a MongoDB ObjectID',
        );
      },
    );

    testWidgets(
      'Bug Fix: Multiple link previews with mixed imageUrl states render correctly',
      (tester) async {
        // This test verifies that the fix handles multiple scenarios correctly
        // We'll test by rendering multiple messages in sequence

        const state = ChatRoomState();

        // Test 1: null imageUrl
        final msg1 = Message(
          id: 'multi-1',
          content: 'Link 1',
          senderId: 'other-user',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example1.com',
            title: 'Site 1',
            description: 'Description 1',
            imageUrl: null,
          ),
        );

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: msg1,
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

        expect(find.byIcon(Icons.link), findsOneWidget);
        expect(find.byType(CachedNetworkImageWidget), findsNothing);

        // Test 2: valid imageUrl
        final msg2 = Message(
          id: 'multi-2',
          content: 'Link 2',
          senderId: 'me',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example2.com',
            title: 'Site 2',
            description: 'Description 2',
            imageUrl: 'https://example2.com/image.png',
          ),
        );

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: msg2,
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

        expect(find.byType(CachedNetworkImageWidget), findsOneWidget);
        expect(find.byIcon(Icons.link), findsNothing);

        // Test 3: empty imageUrl
        final msg3 = Message(
          id: 'multi-3',
          content: 'Link 3',
          senderId: 'other-user',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example3.com',
            title: 'Site 3',
            description: 'Description 3',
            imageUrl: '',
          ),
        );

        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: msg3,
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

        expect(find.byIcon(Icons.link), findsOneWidget);
        expect(find.byType(CachedNetworkImageWidget), findsNothing);
      },
    );
  });
}
