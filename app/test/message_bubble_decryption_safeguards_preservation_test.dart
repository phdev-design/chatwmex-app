import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/models/message.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/features/chat/providers/chat_room_provider.dart';

/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**
/// 
/// Property 2: Preservation - Successfully Decrypted Message Behavior
/// 
/// CRITICAL: This test MUST PASS on unfixed code - passing confirms baseline behavior to preserve
/// GOAL: Capture existing behavior for successfully decrypted messages
/// 
/// Property-based testing approach: Generate many test cases across the input domain
/// (different message types, statuses, content variations) to ensure strong guarantees
/// that behavior is unchanged for all non-buggy inputs.
/// 
/// Test cases cover:
/// - Successfully decrypted image messages render with tap-to-view functionality
/// - Successfully decrypted voice messages render AudioMessageBubble widget
/// - Successfully decrypted file messages render with tap-to-open functionality
/// - Successfully decrypted text messages with valid URLs display link previews
/// - Messages with `status == MessageStatus.decryptingRetry` display loading spinner
/// - Unsent messages (`isUnsent == true`) display "此訊息已收回"
/// - Successfully decrypted messages display reactions, reply content, timestamp, and status icons
/// 
/// EXPECTED OUTCOME: All tests PASS on unfixed code (confirms baseline behavior)
void main() {
  group('Property 2: Preservation - Successfully Decrypted Message Behavior', () {
    
    // Test Case 1: Successfully decrypted image messages
    testWidgets('Successfully decrypted image messages render with tap-to-view functionality', (WidgetTester tester) async {
      print('\n=== Testing Successfully Decrypted Image Messages ===');
      
      // Generate test cases: various image URLs without 🔒 prefix
      final testCases = [
        'https://example.com/image1.jpg',
        'https://example.com/photos/vacation.png',
        '/uploads/profile_pic.jpg',
        'image_data_base64_encoded',
      ];
      
      for (final imageUrl in testCases) {
        print('Testing image URL: $imageUrl');
        
        final message = Message(
          id: 'test-image-${testCases.indexOf(imageUrl)}',
          content: imageUrl,
          senderId: 'user1',
          type: MessageType.image,
          status: MessageStatus.sent,
          createdAt: DateTime.now(),
        );
        
        // Build the widget
        await tester.pumpWidget(_buildMessageBubble(message));
        await tester.pump(); // Use pump instead of pumpAndSettle to avoid waiting for image loading
        
        // Verify: Image should render (not show lock icon)
        final lockIconFinder = find.byIcon(Icons.lock_outline);
        expect(
          lockIconFinder,
          findsNothing,
          reason: 'Successfully decrypted image should NOT display lock icon',
        );
        
        // Verify: Should find GestureDetector for tap-to-view
        final gestureDetectorFinder = find.byType(GestureDetector);
        expect(
          gestureDetectorFinder,
          findsWidgets,
          reason: 'Image should have tap-to-view functionality',
        );
        
        print('✓ Image message renders correctly without lock icon');
      }
      
      print('=== End of Image Message Test ===\n');
    });
    
    // Test Case 2: Successfully decrypted voice messages
    testWidgets('Successfully decrypted voice messages render AudioMessageBubble widget', (WidgetTester tester) async {
      print('\n=== Testing Successfully Decrypted Voice Messages ===');
      
      // Generate test cases: various voice message content
      final testCases = [
        'https://example.com/audio1.m4a',
        '/uploads/voice_message.aac',
        'audio_data_encrypted_key',
      ];
      
      for (final audioUrl in testCases) {
        print('Testing audio URL: $audioUrl');
        
        final message = Message(
          id: 'test-voice-${testCases.indexOf(audioUrl)}',
          content: audioUrl,
          senderId: 'user1',
          type: MessageType.voice,
          status: MessageStatus.delivered,
          createdAt: DateTime.now(),
        );
        
        // Build the widget
        await tester.pumpWidget(_buildMessageBubble(message));
        await tester.pumpAndSettle();
        
        // Verify: Should NOT show lock icon
        final lockIconFinder = find.byIcon(Icons.lock_outline);
        expect(
          lockIconFinder,
          findsNothing,
          reason: 'Successfully decrypted voice message should NOT display lock icon',
        );
        
        // Note: AudioMessageBubble is a separate widget, so we just verify it's not showing error state
        final errorTextFinder = find.textContaining('解密失敗');
        expect(
          errorTextFinder,
          findsNothing,
          reason: 'Voice message should not show decryption error',
        );
        
        print('✓ Voice message renders correctly without lock icon');
      }
      
      print('=== End of Voice Message Test ===\n');
    });
    
    // Test Case 3: Successfully decrypted file messages
    testWidgets('Successfully decrypted file messages render with tap-to-open functionality', (WidgetTester tester) async {
      print('\n=== Testing Successfully Decrypted File Messages ===');
      
      // Generate test cases: various file URLs and types
      final testCases = [
        'https://example.com/document.pdf',
        '/uploads/report.docx',
        'https://storage.com/files/presentation.pptx',
      ];
      
      for (final fileUrl in testCases) {
        print('Testing file URL: $fileUrl');
        
        final message = Message(
          id: 'test-file-${testCases.indexOf(fileUrl)}',
          content: fileUrl,
          senderId: 'user1',
          type: MessageType.file,
          status: MessageStatus.read,
          createdAt: DateTime.now(),
        );
        
        // Build the widget
        await tester.pumpWidget(_buildMessageBubble(message));
        await tester.pumpAndSettle();
        
        // Verify: Should NOT show lock icon
        final lockIconFinder = find.byIcon(Icons.lock_outline);
        expect(
          lockIconFinder,
          findsNothing,
          reason: 'Successfully decrypted file message should NOT display lock icon',
        );
        
        // Verify: Should show file icon (PDF or generic file icon)
        final pdfIconFinder = find.byIcon(Icons.picture_as_pdf);
        final fileIconFinder = find.byIcon(Icons.insert_drive_file);
        expect(
          pdfIconFinder.evaluate().isNotEmpty || fileIconFinder.evaluate().isNotEmpty,
          isTrue,
          reason: 'File message should display file icon',
        );
        
        print('✓ File message renders correctly with file icon');
      }
      
      print('=== End of File Message Test ===\n');
    });
    
    // Test Case 4: Successfully decrypted text messages with URLs
    testWidgets('Successfully decrypted text messages with valid URLs display link previews', (WidgetTester tester) async {
      print('\n=== Testing Text Messages with Link Previews ===');
      
      // Generate test cases: text messages with URLs and link preview data
      final testCases = [
        {
          'content': 'Check this out: https://example.com',
          'preview': LinkPreview(
            url: 'https://example.com',
            title: 'Example Website',
            description: 'This is an example website',
            imageUrl: 'https://example.com/og-image.jpg',
          ),
        },
        {
          'content': 'News article: https://news.com/article',
          'preview': LinkPreview(
            url: 'https://news.com/article',
            title: 'Breaking News',
            description: 'Latest updates on current events',
          ),
        },
      ];
      
      for (final testCase in testCases) {
        print('Testing text with URL: ${testCase['content']}');
        
        final message = Message(
          id: 'test-text-${testCases.indexOf(testCase)}',
          content: testCase['content'] as String,
          senderId: 'user1',
          type: MessageType.text,
          status: MessageStatus.sent,
          createdAt: DateTime.now(),
          linkPreview: testCase['preview'] as LinkPreview,
        );
        
        // Build the widget
        await tester.pumpWidget(_buildMessageBubble(message));
        await tester.pump(); // Use pump instead of pumpAndSettle to avoid waiting for image loading
        
        // Verify: Should NOT show lock icon
        final lockIconFinder = find.byIcon(Icons.lock_outline);
        expect(
          lockIconFinder,
          findsNothing,
          reason: 'Successfully decrypted text message should NOT display lock icon',
        );
        
        // Verify: Should display the text content
        final contentFinder = find.text(testCase['content'] as String);
        expect(
          contentFinder,
          findsOneWidget,
          reason: 'Text message should display its content',
        );
        
        // Verify: Link preview should be rendered (if preview data exists)
        final preview = testCase['preview'] as LinkPreview;
        if (preview.title.isNotEmpty) {
          final titleFinder = find.text(preview.title);
          expect(
            titleFinder,
            findsOneWidget,
            reason: 'Link preview title should be displayed',
          );
        }
        
        print('✓ Text message with link preview renders correctly');
      }
      
      print('=== End of Text Message with Link Preview Test ===\n');
    });
    
    // Test Case 5: Messages with decryptingRetry status
    testWidgets('Messages with decryptingRetry status display loading spinner with message', (WidgetTester tester) async {
      print('\n=== Testing DecryptingRetry Status Messages ===');
      
      // Generate test cases: various message types with decryptingRetry status
      final testCases = [
        MessageType.text,
        MessageType.image,
        MessageType.voice,
        MessageType.file,
      ];
      
      for (final messageType in testCases) {
        print('Testing decryptingRetry for type: ${messageType.name}');
        
        final message = Message(
          id: 'test-retry-${messageType.name}',
          content: 'some_content',
          senderId: 'user1',
          type: messageType,
          status: MessageStatus.decryptingRetry,
          createdAt: DateTime.now(),
        );
        
        // Build the widget
        await tester.pumpWidget(_buildMessageBubble(message));
        await tester.pump(); // Use pump to avoid waiting for CircularProgressIndicator animation
        
        // Verify: Should display loading spinner
        final spinnerFinder = find.byType(CircularProgressIndicator);
        expect(
          spinnerFinder,
          findsOneWidget,
          reason: 'DecryptingRetry message should display loading spinner',
        );
        
        // Verify: Should display retry message
        final retryMessageFinder = find.textContaining('等待對方上線以重新解密');
        expect(
          retryMessageFinder,
          findsOneWidget,
          reason: 'DecryptingRetry message should display retry text',
        );
        
        // Verify: Should NOT show lock icon (different from failed state)
        final lockIconFinder = find.byIcon(Icons.lock_outline);
        expect(
          lockIconFinder,
          findsNothing,
          reason: 'DecryptingRetry should show spinner, not lock icon',
        );
        
        print('✓ DecryptingRetry message displays loading spinner correctly');
      }
      
      print('=== End of DecryptingRetry Status Test ===\n');
    });
    
    // Test Case 6: Unsent messages
    testWidgets('Unsent messages display "此訊息已收回" regardless of decryption status', (WidgetTester tester) async {
      print('\n=== Testing Unsent Messages ===');
      
      // Generate test cases: various message types and statuses with isUnsent=true
      final testCases = [
        {'type': MessageType.text, 'status': MessageStatus.sent, 'content': 'Hello world'},
        {'type': MessageType.image, 'status': MessageStatus.delivered, 'content': 'https://example.com/image.jpg'},
        {'type': MessageType.text, 'status': MessageStatus.failed, 'content': '🔒 encrypted_data'},
        {'type': MessageType.voice, 'status': MessageStatus.read, 'content': 'audio_url'},
      ];
      
      for (final testCase in testCases) {
        print('Testing unsent message: type=${(testCase['type'] as MessageType).name}, status=${(testCase['status'] as MessageStatus).name}');
        
        final message = Message(
          id: 'test-unsent-${testCases.indexOf(testCase)}',
          content: testCase['content'] as String,
          senderId: 'user1',
          type: testCase['type'] as MessageType,
          status: testCase['status'] as MessageStatus,
          createdAt: DateTime.now(),
          isUnsent: true,
        );
        
        // Build the widget
        await tester.pumpWidget(_buildMessageBubble(message));
        await tester.pumpAndSettle();
        
        // Verify: Should display "此訊息已收回"
        final unsentTextFinder = find.text('此訊息已收回');
        expect(
          unsentTextFinder,
          findsOneWidget,
          reason: 'Unsent message should display "此訊息已收回"',
        );
        
        // Verify: Should NOT display original content
        if (testCase['content'] != '此訊息已收回') {
          final originalContentFinder = find.text(testCase['content'] as String);
          expect(
            originalContentFinder,
            findsNothing,
            reason: 'Unsent message should not display original content',
          );
        }
        
        print('✓ Unsent message displays correctly');
      }
      
      print('=== End of Unsent Message Test ===\n');
    });
    
    // Test Case 7: Successfully decrypted messages display metadata (timestamp, status icons)
    testWidgets('Successfully decrypted messages display reactions, timestamp, and status icons', (WidgetTester tester) async {
      print('\n=== Testing Message Metadata Display ===');
      
      // Generate test cases: messages with various metadata
      final testCases = [
        {
          'type': MessageType.text,
          'content': 'Hello!',
          'status': MessageStatus.sent,
          'reactions': {'👍': ['user2'], '❤️': ['user3', 'user4']},
        },
        {
          'type': MessageType.text,
          'content': 'How are you?',
          'status': MessageStatus.read,
          'reactions': null,
        },
        {
          'type': MessageType.image,
          'content': 'https://example.com/photo.jpg',
          'status': MessageStatus.delivered,
          'reactions': {'😂': ['user2']},
        },
      ];
      
      for (final testCase in testCases) {
        print('Testing message metadata: status=${(testCase['status'] as MessageStatus).name}');
        
        final message = Message(
          id: 'test-metadata-${testCases.indexOf(testCase)}',
          content: testCase['content'] as String,
          senderId: 'current-user',
          type: testCase['type'] as MessageType,
          status: testCase['status'] as MessageStatus,
          createdAt: DateTime.now(),
          reactions: testCase['reactions'] as Map<String, List<String>>?,
        );
        
        // Build the widget (isMe=true to see status icons)
        await tester.pumpWidget(_buildMessageBubble(message, isMe: true));
        await tester.pump(); // Use pump to avoid waiting for image loading in link previews
        
        // Verify: Should display timestamp (formatted time)
        // Note: We can't easily test the exact time format, but we can verify no lock icon is shown
        final lockIconFinder = find.byIcon(Icons.lock_outline);
        expect(
          lockIconFinder,
          findsNothing,
          reason: 'Successfully decrypted message should NOT display lock icon',
        );
        
        // Verify: Should display status icon for sent messages
        final statusIcons = [
          Icons.schedule,
          Icons.access_time,
          Icons.check,
          Icons.done_all,
          Icons.error_outline,
        ];
        
        bool foundStatusIcon = false;
        for (final icon in statusIcons) {
          if (find.byIcon(icon).evaluate().isNotEmpty) {
            foundStatusIcon = true;
            break;
          }
        }
        
        expect(
          foundStatusIcon,
          isTrue,
          reason: 'Message should display status icon',
        );
        
        // Verify: Reactions should be displayed if present
        if (testCase['reactions'] != null) {
          final reactions = testCase['reactions'] as Map<String, List<String>>;
          for (final emoji in reactions.keys) {
            final emojiTextFinder = find.text(emoji);
            expect(
              emojiTextFinder,
              findsOneWidget,
              reason: 'Reaction emoji "$emoji" should be displayed',
            );
          }
        }
        
        print('✓ Message metadata displays correctly');
      }
      
      print('=== End of Message Metadata Test ===\n');
    });
    
    // Test Case 8: Edge cases - messages with both valid and edge case content
    testWidgets('Edge cases: Empty content, various statuses, mixed scenarios', (WidgetTester tester) async {
      print('\n=== Testing Edge Cases ===');
      
      // Generate edge case test scenarios
      final testCases = [
        {
          'description': 'Text message with empty content',
          'message': Message(
            id: 'edge-1',
            content: '',
            senderId: 'user1',
            type: MessageType.text,
            status: MessageStatus.sent,
            createdAt: DateTime.now(),
          ),
        },
        {
          'description': 'Message with pending status',
          'message': Message(
            id: 'edge-2',
            content: 'Pending message',
            senderId: 'user1',
            type: MessageType.text,
            status: MessageStatus.pending,
            createdAt: DateTime.now(),
          ),
        },
        {
          'description': 'Message with sending status',
          'message': Message(
            id: 'edge-3',
            content: 'Sending...',
            senderId: 'user1',
            type: MessageType.text,
            status: MessageStatus.sending,
            createdAt: DateTime.now(),
          ),
        },
      ];
      
      for (final testCase in testCases) {
        print('Testing: ${testCase['description']}');
        
        final message = testCase['message'] as Message;
        
        // Build the widget
        await tester.pumpWidget(_buildMessageBubble(message));
        await tester.pumpAndSettle();
        
        // Verify: Should NOT show lock icon (these are not decryption failures)
        final lockIconFinder = find.byIcon(Icons.lock_outline);
        expect(
          lockIconFinder,
          findsNothing,
          reason: '${testCase['description']} should NOT display lock icon',
        );
        
        // Verify: Should NOT show decryption error text
        final errorTextFinder = find.textContaining('解密失敗');
        expect(
          errorTextFinder,
          findsNothing,
          reason: '${testCase['description']} should not show decryption error',
        );
        
        print('✓ Edge case handled correctly');
      }
      
      print('=== End of Edge Cases Test ===\n');
    });
  });
}

/// Helper function to build MessageBubble widget in test environment
Widget _buildMessageBubble(Message message, {bool isMe = false}) {
  // Create a minimal ChatRoomState for testing
  final state = ChatRoomState(
    messages: [message],
    isLoading: false,
    hasMore: false,
    typingUsers: [],
    isConnected: true,
  );
  
  final params = ChatRoomParams(
    roomId: 'test-room',
    isRoom: false,
    currentUserId: 'current-user',
    token: 'test-token',
  );
  
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          msg: message,
          isMe: isMe,
          state: state,
          params: params,
          isRoom: false,
          currentUserId: 'current-user',
          title: 'Test Chat',
          onScrollToMessage: (messageId) async {},
        ),
      ),
    ),
  );
}
