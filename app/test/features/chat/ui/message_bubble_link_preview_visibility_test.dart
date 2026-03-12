import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Property 1: Bug Condition** - Link Preview Text Visibility
/// **Validates: Requirements 2.1, 2.2, 2.3**
///
/// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
/// DO NOT attempt to fix the test or the code when it fails
/// NOTE: This test encodes the expected behavior - it will validate the fix when it passes after implementation
/// GOAL: Surface counterexamples that demonstrate the bug exists
///
/// Scoped PBT Approach: Test link previews with non-empty title and/or description
/// in different theme/sender contexts (dark/light mode × incoming/outgoing messages)
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

  group('Bug Condition Exploration - Link Preview Text Visibility', () {
    testWidgets(
      'Bug Condition: Dark mode incoming message - title and description should use appropriate colors (not colorScheme.onSurface/onSurfaceVariant)',
      (tester) async {
        // Arrange: Create a message with link preview in dark mode, incoming message
        final msg = Message(
          id: 'm1',
          content: 'Check this out: https://flutter.dev',
          senderId: 'other-user',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://flutter.dev',
            title: 'Flutter Documentation',
            description: 'Official Flutter documentation and tutorials',
            imageUrl: 'https://flutter.dev/images/flutter-logo.png',
          ),
        );
        const state = ChatRoomState();

        // Act: Render the message bubble in dark mode
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: msg,
              isMe: false, // Incoming message
              state: state,
              params: params,
              isRoom: true,
              currentUserId: 'me',
              title: 'room',
              onScrollToMessage: (_) async {},
            ),
            brightness: Brightness.dark,
          ),
        );
        await tester.pump();

        // Assert: Find the title and description Text widgets
        final titleFinder = find.text('Flutter Documentation');
        final descriptionFinder = find.text('Official Flutter documentation and tutorials');

        expect(titleFinder, findsOneWidget, reason: 'Title text widget should exist');
        expect(descriptionFinder, findsOneWidget, reason: 'Description text widget should exist');

        // Get the Text widgets
        final titleWidget = tester.widget<Text>(titleFinder);
        final descriptionWidget = tester.widget<Text>(descriptionFinder);

        // Get the color scheme for comparison
        final colorScheme = Theme.of(tester.element(titleFinder)).colorScheme;

        // CRITICAL ASSERTION: Title should NOT use colorScheme.onSurface
        // Expected behavior: Title should use textColor (tokens.bubbleText for incoming messages)
        expect(
          titleWidget.style?.color,
          isNot(equals(colorScheme.onSurface)),
          reason: 'Title should use textColor (tokens.bubbleText), not colorScheme.onSurface for proper contrast',
        );

        // CRITICAL ASSERTION: Description should NOT use colorScheme.onSurfaceVariant
        // Expected behavior: Description should use subtleTextColor (tokens.subtleText for incoming messages)
        expect(
          descriptionWidget.style?.color,
          isNot(equals(colorScheme.onSurfaceVariant)),
          reason: 'Description should use subtleTextColor (tokens.subtleText), not colorScheme.onSurfaceVariant for proper contrast',
        );
      },
    );

    testWidgets(
      'Bug Condition: Dark mode outgoing message - title and description should use appropriate colors',
      (tester) async {
        // Arrange: Create a message with link preview in dark mode, outgoing message
        final msg = Message(
          id: 'm2',
          content: 'Check this out: https://github.com',
          senderId: 'me',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://github.com',
            title: 'GitHub Repository',
            description: 'Open source project repository',
            imageUrl: 'https://github.com/logo.png',
          ),
        );
        const state = ChatRoomState();

        // Act: Render the message bubble in dark mode
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: msg,
              isMe: true, // Outgoing message
              state: state,
              params: params,
              isRoom: true,
              currentUserId: 'me',
              title: 'room',
              onScrollToMessage: (_) async {},
            ),
            brightness: Brightness.dark,
          ),
        );
        await tester.pump();

        // Assert: Find the title and description Text widgets
        final titleFinder = find.text('GitHub Repository');
        final descriptionFinder = find.text('Open source project repository');

        expect(titleFinder, findsOneWidget, reason: 'Title text widget should exist');
        expect(descriptionFinder, findsOneWidget, reason: 'Description text widget should exist');

        // Get the Text widgets
        final titleWidget = tester.widget<Text>(titleFinder);
        final descriptionWidget = tester.widget<Text>(descriptionFinder);

        // Get the color scheme for comparison
        final colorScheme = Theme.of(tester.element(titleFinder)).colorScheme;

        // CRITICAL ASSERTION: Title should NOT use colorScheme.onSurface
        // Expected behavior: Title should use textColor (tokens.bubbleOutgoingText for outgoing messages)
        expect(
          titleWidget.style?.color,
          isNot(equals(colorScheme.onSurface)),
          reason: 'Title should use textColor (tokens.bubbleOutgoingText), not colorScheme.onSurface',
        );

        // CRITICAL ASSERTION: Description should NOT use colorScheme.onSurfaceVariant
        // Expected behavior: Description should use subtleTextColor (tokens.bubbleOutgoingSubtleText for outgoing messages)
        expect(
          descriptionWidget.style?.color,
          isNot(equals(colorScheme.onSurfaceVariant)),
          reason: 'Description should use subtleTextColor (tokens.bubbleOutgoingSubtleText), not colorScheme.onSurfaceVariant',
        );
      },
    );

    testWidgets(
      'Bug Condition: Light mode incoming message - title and description should use appropriate colors',
      (tester) async {
        // Arrange: Create a message with link preview in light mode, incoming message
        final msg = Message(
          id: 'm3',
          content: 'Check this out: https://dart.dev',
          senderId: 'other-user',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://dart.dev',
            title: 'Dart Programming Language',
            description: 'Official Dart language documentation',
            imageUrl: 'https://dart.dev/logo.png',
          ),
        );
        const state = ChatRoomState();

        // Act: Render the message bubble in light mode
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: msg,
              isMe: false, // Incoming message
              state: state,
              params: params,
              isRoom: true,
              currentUserId: 'me',
              title: 'room',
              onScrollToMessage: (_) async {},
            ),
            brightness: Brightness.light,
          ),
        );
        await tester.pump();

        // Assert: Find the title and description Text widgets
        final titleFinder = find.text('Dart Programming Language');
        final descriptionFinder = find.text('Official Dart language documentation');

        expect(titleFinder, findsOneWidget, reason: 'Title text widget should exist');
        expect(descriptionFinder, findsOneWidget, reason: 'Description text widget should exist');

        // Get the Text widgets
        final titleWidget = tester.widget<Text>(titleFinder);
        final descriptionWidget = tester.widget<Text>(descriptionFinder);

        // Get the color scheme for comparison
        final colorScheme = Theme.of(tester.element(titleFinder)).colorScheme;

        // CRITICAL ASSERTION: Title should NOT use colorScheme.onSurface
        expect(
          titleWidget.style?.color,
          isNot(equals(colorScheme.onSurface)),
          reason: 'Title should use textColor (tokens.bubbleText), not colorScheme.onSurface',
        );

        // CRITICAL ASSERTION: Description should NOT use colorScheme.onSurfaceVariant
        expect(
          descriptionWidget.style?.color,
          isNot(equals(colorScheme.onSurfaceVariant)),
          reason: 'Description should use subtleTextColor (tokens.subtleText), not colorScheme.onSurfaceVariant',
        );
      },
    );

    testWidgets(
      'Bug Condition: Light mode outgoing message - title and description should use appropriate colors',
      (tester) async {
        // Arrange: Create a message with link preview in light mode, outgoing message
        final msg = Message(
          id: 'm4',
          content: 'Check this out: https://pub.dev',
          senderId: 'me',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://pub.dev',
            title: 'Pub.dev Package Repository',
            description: 'Dart and Flutter package repository',
            imageUrl: 'https://pub.dev/logo.png',
          ),
        );
        const state = ChatRoomState();

        // Act: Render the message bubble in light mode
        await tester.pumpWidget(
          wrap(
            MessageBubble(
              msg: msg,
              isMe: true, // Outgoing message
              state: state,
              params: params,
              isRoom: true,
              currentUserId: 'me',
              title: 'room',
              onScrollToMessage: (_) async {},
            ),
            brightness: Brightness.light,
          ),
        );
        await tester.pump();

        // Assert: Find the title and description Text widgets
        final titleFinder = find.text('Pub.dev Package Repository');
        final descriptionFinder = find.text('Dart and Flutter package repository');

        expect(titleFinder, findsOneWidget, reason: 'Title text widget should exist');
        expect(descriptionFinder, findsOneWidget, reason: 'Description text widget should exist');

        // Get the Text widgets
        final titleWidget = tester.widget<Text>(titleFinder);
        final descriptionWidget = tester.widget<Text>(descriptionFinder);

        // Get the color scheme for comparison
        final colorScheme = Theme.of(tester.element(titleFinder)).colorScheme;

        // CRITICAL ASSERTION: Title should NOT use colorScheme.onSurface
        expect(
          titleWidget.style?.color,
          isNot(equals(colorScheme.onSurface)),
          reason: 'Title should use textColor (tokens.bubbleOutgoingText), not colorScheme.onSurface',
        );

        // CRITICAL ASSERTION: Description should NOT use colorScheme.onSurfaceVariant
        expect(
          descriptionWidget.style?.color,
          isNot(equals(colorScheme.onSurfaceVariant)),
          reason: 'Description should use subtleTextColor (tokens.bubbleOutgoingSubtleText), not colorScheme.onSurfaceVariant',
        );
      },
    );

    testWidgets(
      'Bug Condition: Link preview with only title (no description) should use appropriate color',
      (tester) async {
        // Arrange: Create a message with link preview that has only title
        final msg = Message(
          id: 'm5',
          content: 'Check this out: https://example.com',
          senderId: 'other-user',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example.com',
            title: 'Example Website',
            description: '', // Empty description
            imageUrl: 'https://example.com/logo.png',
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
            brightness: Brightness.dark,
          ),
        );
        await tester.pump();

        // Assert: Find the title Text widget
        final titleFinder = find.text('Example Website');
        expect(titleFinder, findsOneWidget, reason: 'Title text widget should exist');

        // Get the Text widget
        final titleWidget = tester.widget<Text>(titleFinder);

        // Get the color scheme for comparison
        final colorScheme = Theme.of(tester.element(titleFinder)).colorScheme;

        // CRITICAL ASSERTION: Title should NOT use colorScheme.onSurface
        expect(
          titleWidget.style?.color,
          isNot(equals(colorScheme.onSurface)),
          reason: 'Title should use textColor, not colorScheme.onSurface',
        );
      },
    );

    testWidgets(
      'Bug Condition: Link preview with only description (no title) should use appropriate color',
      (tester) async {
        // Arrange: Create a message with link preview that has only description
        final msg = Message(
          id: 'm6',
          content: 'Check this out: https://example.org',
          senderId: 'me',
          type: MessageType.text,
          createdAt: DateTime.now(),
          linkPreview: LinkPreview(
            url: 'https://example.org',
            title: '', // Empty title
            description: 'This is an interesting website with useful content',
            imageUrl: 'https://example.org/logo.png',
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
            brightness: Brightness.light,
          ),
        );
        await tester.pump();

        // Assert: Find the description Text widget
        final descriptionFinder = find.text('This is an interesting website with useful content');
        expect(descriptionFinder, findsOneWidget, reason: 'Description text widget should exist');

        // Get the Text widget
        final descriptionWidget = tester.widget<Text>(descriptionFinder);

        // Get the color scheme for comparison
        final colorScheme = Theme.of(tester.element(descriptionFinder)).colorScheme;

        // CRITICAL ASSERTION: Description should NOT use colorScheme.onSurfaceVariant
        expect(
          descriptionWidget.style?.color,
          isNot(equals(colorScheme.onSurfaceVariant)),
          reason: 'Description should use subtleTextColor, not colorScheme.onSurfaceVariant',
        );
      },
    );
  });
}
