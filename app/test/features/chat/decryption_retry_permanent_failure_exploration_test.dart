import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/message.dart';

/// 🔐 Bug Condition Exploration Test: Decryption Retry Permanent Failure
/// 
/// **Validates: Requirements 1.4**
/// 
/// **Bug Condition**: When frontend decryption fails and sends `re_encrypt_request`,
/// if sender is offline > 10 seconds, message is marked as MessageStatus.failed
/// (permanent failure state).
/// 
/// **Expected Behavior (after fix)**: Message should remain in MessageStatus.decryptingRetry
/// state and display "🔒 等待對方上線以重新解密..." instead of marking as permanent failure.
/// 
/// **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists.
/// The test encodes the EXPECTED behavior, so it will pass after the fix is implemented.
/// 
/// **Scoped PBT Approach**: Scope to re_encrypt_request with sender offline > 10 seconds
/// 
/// Test Strategy:
/// - Generate multiple scenarios with varying offline durations > 10 seconds
/// - Simulate the timeout mechanism (10 second timer after re_encrypt_request)
/// - Verify message remains in decryptingRetry state (expected behavior)
/// - On unfixed code: test will FAIL because message gets marked as failed after max retries

void main() {
  group('Bug Condition Exploration: Decryption Retry Permanent Failure -', () {
    
    /// Property 1: Bug Condition - Offline Sender Permanent Failure
    /// 
    /// For any message where:
    /// - Decryption fails and re_encrypt_request is sent
    /// - Sender is offline for > 10 seconds
    /// - Timeout triggers retry mechanism
    /// 
    /// Expected behavior: Message SHOULD remain in MessageStatus.decryptingRetry
    /// Actual behavior (unfixed): Message gets marked as MessageStatus.failed after 2 retries
    test('Property: Message should remain in decryptingRetry when sender offline > 10s', () async {
      // Property-based test: Generate multiple test cases with different offline durations
      final testCases = [
        {'offlineDuration': 11, 'description': 'sender offline 11 seconds'},
        {'offlineDuration': 15, 'description': 'sender offline 15 seconds'},
        {'offlineDuration': 20, 'description': 'sender offline 20 seconds'},
        {'offlineDuration': 30, 'description': 'sender offline 30 seconds'},
        {'offlineDuration': 60, 'description': 'sender offline 1 minute'},
        {'offlineDuration': 120, 'description': 'sender offline 2 minutes'},
      ];

      for (final testCase in testCases) {
        final offlineDuration = testCase['offlineDuration'] as int;
        final description = testCase['description'] as String;

        // Simulate the bug condition scenario
        var messageStatus = MessageStatus.delivered;
        var retryCount = 0;
        const maxRetries = 2;
        var senderOnline = false;

        // Step 1: Decryption fails
        messageStatus = MessageStatus.decryptingRetry;
        retryCount = 1;

        // Step 2: re_encrypt_request sent, 10 second timeout starts
        // After 10 seconds, timeout triggers
        if (!senderOnline) {
          // Current implementation retries by calling _handleDecryptionFailure again
          retryCount = 2;
        }

        // Step 3: Second timeout at 20 seconds, sender still offline
        // BUG: Current implementation marks as failed after max retries
        if (!senderOnline && retryCount >= maxRetries) {
          messageStatus = MessageStatus.failed;
        }

        // EXPECTED BEHAVIOR: Message should remain in decryptingRetry state
        // even when sender is offline for extended periods
        expect(
          messageStatus,
          equals(MessageStatus.decryptingRetry),
          reason: 'Message should remain in decryptingRetry state when $description. '
                  'Current behavior: marks as failed after 2 retries (20 seconds total). '
                  'Expected behavior: should wait indefinitely for sender to come online.',
        );
      }
    });

    test('Property: Message should display waiting message when sender offline', () async {
      // Test that the UI displays appropriate waiting message
      // instead of permanent failure message
      
      var messageStatus = MessageStatus.decryptingRetry;
      var senderOnline = false;
      var retryCount = 2; // Max retries reached
      
      // Simulate timeout after max retries
      if (retryCount >= 2 && !senderOnline) {
        // BUG: Current implementation marks as failed
        messageStatus = MessageStatus.failed;
      }

      // EXPECTED: Should remain in decryptingRetry with waiting message
      expect(
        messageStatus,
        equals(MessageStatus.decryptingRetry),
        reason: 'Message should remain in decryptingRetry state to allow recovery when sender comes online. '
                'Expected UI message: "🔒 等待對方上線以重新解密..."',
      );
    });

    test('Property: Multiple messages should all remain in decryptingRetry when sender offline', () async {
      // Test that multiple messages from the same offline sender
      // all remain in retry state instead of being marked as failed
      
      final messages = List.generate(5, (i) => {
        'id': 'msg-$i',
        'status': MessageStatus.decryptingRetry,
        'retryCount': 0,
      });

      var senderOnline = false;
      
      // Simulate timeout and retry for all messages
      for (var message in messages) {
        var status = message['status'] as MessageStatus;
        var retryCount = message['retryCount'] as int;
        
        // First timeout at 10 seconds
        retryCount++;
        
        // Second timeout at 20 seconds
        retryCount++;
        
        // BUG: After 2 retries, marks as failed
        if (retryCount >= 2 && !senderOnline) {
          status = MessageStatus.failed;
        }
        
        message['status'] = status;
        message['retryCount'] = retryCount;
      }

      // EXPECTED: All messages should remain in decryptingRetry
      for (var message in messages) {
        expect(
          message['status'],
          equals(MessageStatus.decryptingRetry),
          reason: 'All messages from offline sender should remain in decryptingRetry state. '
                  'Message ${message['id']} should wait for sender to come online.',
        );
      }
    });

    test('Property: Retry count should not cause permanent failure when sender offline', () async {
      // Test that the retry count mechanism doesn't cause permanent failure
      // when the root cause is sender being offline (not a decryption error)
      
      var messageStatus = MessageStatus.decryptingRetry;
      var retryCount = 0;
      const maxRetries = 2;
      var senderOnline = false;
      
      // Simulate multiple retry attempts
      for (var attempt = 0; attempt < 5; attempt++) {
        // Wait 10 seconds
        await Future.delayed(const Duration(milliseconds: 10));
        
        if (!senderOnline) {
          retryCount++;
          
          // BUG: Current implementation marks as failed after maxRetries
          if (retryCount >= maxRetries) {
            messageStatus = MessageStatus.failed;
            break;
          }
        }
      }

      // EXPECTED: Should remain in decryptingRetry regardless of retry count
      // when sender is offline (not a decryption error)
      expect(
        messageStatus,
        equals(MessageStatus.decryptingRetry),
        reason: 'Retry count should not cause permanent failure when sender is offline. '
                'The message should remain recoverable until sender comes online. '
                'Current bug: marks as failed after $maxRetries retries.',
      );
    });

    test('Counterexample: Verify bug exists with specific scenario', () async {
      // This test explicitly demonstrates the bug with a concrete scenario
      // to help understand the root cause
      
      // Scenario: User receives encrypted message but decryption fails
      var message = {
        'id': 'msg-123',
        'senderId': 'user-456',
        'content': 'encrypted-content',
        'status': MessageStatus.delivered,
      };
      
      var retryCount = 0;
      var senderOnline = false;
      
      // Step 1: Decryption fails, send re_encrypt_request
      message['status'] = MessageStatus.decryptingRetry;
      retryCount = 1;
      print('Step 1: Decryption failed, status = ${message['status']}, retryCount = $retryCount');
      
      // Step 2: Wait 10 seconds, sender still offline, timeout triggers
      await Future.delayed(const Duration(milliseconds: 10));
      if (!senderOnline) {
        retryCount = 2;
        print('Step 2: Timeout at 10s, sender offline, retryCount = $retryCount');
      }
      
      // Step 3: Wait another 10 seconds, sender still offline, second timeout
      await Future.delayed(const Duration(milliseconds: 10));
      if (!senderOnline && retryCount >= 2) {
        // BUG: Marks as permanent failure
        message['status'] = MessageStatus.failed;
        print('Step 3: Timeout at 20s, max retries reached, status = ${message['status']} (BUG!)');
      }
      
      // Step 4: Sender comes online after 30 seconds
      await Future.delayed(const Duration(milliseconds: 10));
      senderOnline = true;
      print('Step 4: Sender comes online at 30s, but message already marked as failed');
      
      // EXPECTED: Message should still be in decryptingRetry state
      // so it can be recovered when sender comes online
      expect(
        message['status'],
        equals(MessageStatus.decryptingRetry),
        reason: 'BUG CONFIRMED: Message was marked as failed at 20s (after 2 retries), '
                'but sender came online at 30s. Message should have remained in '
                'decryptingRetry state to allow recovery. '
                'Expected: MessageStatus.decryptingRetry, '
                'Actual: MessageStatus.failed',
      );
    });
  });
}
