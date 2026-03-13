import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/models/message.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/features/chat/providers/chat_room_provider.dart';

/// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 2.5**
/// 
/// Bug Condition Exploration Test for Message Bubble Decryption Safeguards
/// 
/// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
/// DO NOT attempt to fix the test or the code when it fails
/// NOTE: This test encodes the expected behavior - it will validate the fix when it passes after implementation
/// GOAL: Surface counterexamples that demonstrate the bug exists
/// 
/// Scoped PBT Approach: Scope the property to concrete failing cases: text/voice/file messages with decryption failures
/// Test that for any message where `content.startsWith('🔒')` OR `status == MessageStatus.failed` (and type is NOT image),
/// the widget displays lock icon with error text and does NOT evaluate `msg.linkPreview`
/// 
/// Test cases to include:
/// - Text message with `content == '🔒 encrypted_data'` → should display lock icon (will fail on unfixed code)
/// - Voice message with `content.startsWith('🔒')` → should display lock icon (will fail on unfixed code)
/// - File message with `status == MessageStatus.failed` → should display lock icon (will fail on unfixed code)
/// - Image message with `content.startsWith('🔒')` → should display lock icon (should pass on unfixed code - baseline)
/// 
/// EXPECTED OUTCOME: Test FAILS for text/voice/file messages (this is correct - it proves the bug exists)
void main() {
  group('Bug Condition: Decryption Failure Detection for All Message Types', () {
    testWidgets('Property 1: Bug Condition - Text message with 🔒 prefix should display lock icon', (WidgetTester tester) async {
      print('\n=== Testing Text Message Decryption Failure ===');
      
      // Create a text message with decryption failure (🔒 prefix)
      final message = Message(
        id: 'test-text-1',
        content: '🔒 encrypted_data_abc123',
        senderId: 'user1',
        type: MessageType.text,
        status: MessageStatus.failed,
        createdAt: DateTime.now(),
      );
      
      print('Test message: type=${message.type.name}, content="${message.content}", status=${message.status.name}');
      
      // Build the widget
      await tester.pumpWidget(_buildMessageBubble(message));
      await tester.pumpAndSettle();
      
      // Verify the widget displays lock icon with error text
      // On UNFIXED code, this will FAIL because text messages are not detected as decryption failures
      final lockIconFinder = find.byIcon(Icons.lock_outline);
      final errorTextFinder = find.textContaining('解密失敗');
      
      print('Looking for lock icon and error text...');
      
      if (lockIconFinder.evaluate().isEmpty) {
        print('✗ COUNTEREXAMPLE: Lock icon NOT found for text message with 🔒 prefix');
        print('  This confirms the bug: text messages with decryption failures are not detected');
      } else {
        print('✓ Lock icon found');
      }
      
      if (errorTextFinder.evaluate().isEmpty) {
        print('✗ COUNTEREXAMPLE: Error text NOT found for text message with 🔒 prefix');
      } else {
        print('✓ Error text found');
      }
      
      // CRITICAL: This assertion will FAIL on unfixed code (expected behavior)
      expect(
        lockIconFinder,
        findsOneWidget,
        reason: 'Text message with 🔒 prefix should display lock icon. '
                'Failure confirms bug: only image messages are detected as decryption failures.',
      );
      
      expect(
        errorTextFinder,
        findsOneWidget,
        reason: 'Text message with decryption failure should display error text.',
      );
      
      print('=== End of Text Message Test ===\n');
    });
    
    testWidgets('Property 1: Bug Condition - Voice message with 🔒 prefix should display lock icon', (WidgetTester tester) async {
      print('\n=== Testing Voice Message Decryption Failure ===');
      
      // Create a voice message with decryption failure (🔒 prefix)
      final message = Message(
        id: 'test-voice-1',
        content: '🔒 encrypted_audio_xyz789',
        senderId: 'user1',
        type: MessageType.voice,
        status: MessageStatus.failed,
        createdAt: DateTime.now(),
      );
      
      print('Test message: type=${message.type.name}, content="${message.content}", status=${message.status.name}');
      
      // Build the widget
      await tester.pumpWidget(_buildMessageBubble(message));
      await tester.pumpAndSettle();
      
      // Verify the widget displays lock icon with error text
      final lockIconFinder = find.byIcon(Icons.lock_outline);
      final errorTextFinder = find.textContaining('解密失敗');
      
      print('Looking for lock icon and error text...');
      
      if (lockIconFinder.evaluate().isEmpty) {
        print('✗ COUNTEREXAMPLE: Lock icon NOT found for voice message with 🔒 prefix');
        print('  This confirms the bug: voice messages with decryption failures are not detected');
      } else {
        print('✓ Lock icon found');
      }
      
      if (errorTextFinder.evaluate().isEmpty) {
        print('✗ COUNTEREXAMPLE: Error text NOT found for voice message with 🔒 prefix');
      } else {
        print('✓ Error text found');
      }
      
      // CRITICAL: This assertion will FAIL on unfixed code (expected behavior)
      expect(
        lockIconFinder,
        findsOneWidget,
        reason: 'Voice message with 🔒 prefix should display lock icon. '
                'Failure confirms bug: only image messages are detected as decryption failures.',
      );
      
      expect(
        errorTextFinder,
        findsOneWidget,
        reason: 'Voice message with decryption failure should display error text.',
      );
      
      print('=== End of Voice Message Test ===\n');
    });
    
    testWidgets('Property 1: Bug Condition - File message with failed status should display lock icon', (WidgetTester tester) async {
      print('\n=== Testing File Message Decryption Failure ===');
      
      // Create a file message with failed status
      final message = Message(
        id: 'test-file-1',
        content: '🔒 encrypted_file_data',
        senderId: 'user1',
        type: MessageType.file,
        status: MessageStatus.failed,
        createdAt: DateTime.now(),
      );
      
      print('Test message: type=${message.type.name}, content="${message.content}", status=${message.status.name}');
      
      // Build the widget
      await tester.pumpWidget(_buildMessageBubble(message));
      await tester.pumpAndSettle();
      
      // Verify the widget displays lock icon with error text
      final lockIconFinder = find.byIcon(Icons.lock_outline);
      final errorTextFinder = find.textContaining('解密失敗');
      
      print('Looking for lock icon and error text...');
      
      if (lockIconFinder.evaluate().isEmpty) {
        print('✗ COUNTEREXAMPLE: Lock icon NOT found for file message with failed status');
        print('  This confirms the bug: file messages with decryption failures are not detected');
      } else {
        print('✓ Lock icon found');
      }
      
      if (errorTextFinder.evaluate().isEmpty) {
        print('✗ COUNTEREXAMPLE: Error text NOT found for file message with failed status');
      } else {
        print('✓ Error text found');
      }
      
      // CRITICAL: This assertion will FAIL on unfixed code (expected behavior)
      expect(
        lockIconFinder,
        findsOneWidget,
        reason: 'File message with failed status should display lock icon. '
                'Failure confirms bug: only image messages are detected as decryption failures.',
      );
      
      expect(
        errorTextFinder,
        findsOneWidget,
        reason: 'File message with decryption failure should display error text.',
      );
      
      print('=== End of File Message Test ===\n');
    });
    
    testWidgets('Baseline: Image message with 🔒 prefix should display lock icon (already working)', (WidgetTester tester) async {
      print('\n=== Testing Image Message Decryption Failure (Baseline) ===');
      
      // Create an image message with decryption failure (🔒 prefix)
      // This should PASS on unfixed code because images are already handled
      final message = Message(
        id: 'test-image-1',
        content: '🔒 encrypted_image_data',
        senderId: 'user1',
        type: MessageType.image,
        status: MessageStatus.failed,
        createdAt: DateTime.now(),
      );
      
      print('Test message: type=${message.type.name}, content="${message.content}", status=${message.status.name}');
      
      // Build the widget
      await tester.pumpWidget(_buildMessageBubble(message));
      await tester.pumpAndSettle();
      
      // Verify the widget displays lock icon with error text
      final lockIconFinder = find.byIcon(Icons.lock_outline);
      final errorTextFinder = find.textContaining('解密失敗');
      
      print('Looking for lock icon and error text...');
      
      if (lockIconFinder.evaluate().isEmpty) {
        print('✗ UNEXPECTED: Lock icon NOT found for image message (this should work on unfixed code)');
      } else {
        print('✓ Lock icon found (as expected - baseline behavior)');
      }
      
      if (errorTextFinder.evaluate().isEmpty) {
        print('✗ UNEXPECTED: Error text NOT found for image message');
      } else {
        print('✓ Error text found (as expected - baseline behavior)');
      }
      
      // This should PASS on unfixed code (baseline behavior)
      expect(
        lockIconFinder,
        findsOneWidget,
        reason: 'Image message with 🔒 prefix should display lock icon (baseline behavior).',
      );
      
      expect(
        errorTextFinder,
        findsOneWidget,
        reason: 'Image message with decryption failure should display error text (baseline behavior).',
      );
      
      print('=== End of Image Message Test (Baseline) ===\n');
    });
  });
}

/// Helper function to build MessageBubble widget in test environment
Widget _buildMessageBubble(Message message) {
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
          isMe: false,
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
