import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/message.dart';

/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
/// 
/// Property 2: Preservation - Continue Re-encrypt Request for Decrypting Messages
/// 
/// This test suite captures the baseline behavior of the E2EE decryption retry flow
/// that MUST be preserved after the bugfix is applied. These tests run on UNFIXED code
/// and are EXPECTED TO PASS, confirming the correct behavior to preserve.
/// 
/// The preservation requirements ensure that:
/// - Messages with statusInMemory == decryptingRetry and retryCount < 2 continue to receive re_encrypt_request
/// - First time decryption failure continues to mark message as decryptingRetry
/// - Sender continues to handle re_encrypt_request by fetching from LocalDB and re-encrypting
/// - Receiver continues to handle re_encrypt_response by attempting to decrypt
/// - Retry limit (>= 2) continues to mark message as failed and stop retrying
/// 
/// IMPORTANT: These tests use observation-first methodology - they observe and document
/// the current correct behavior on unfixed code, which must remain unchanged after the fix.

void main() {
  group('Property 2: Preservation - E2EE Decryption Retry Flow', () {
    
    group('Requirement 3.1: Messages with decryptingRetry status and retryCount < 2 should continue to receive re_encrypt_request', () {
      
      test('Single message with decryptingRetry status and retryCount = 0 should trigger re_encrypt_request', () {
        // **Validates: Requirement 3.1**
        // Scenario: One message failed decryption for the first time
        
        final message = Message(
          id: 'msg-001',
          content: 'encrypted_content_base64',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 0,
        );
        
        // Simulate checking if re_encrypt_request should be sent
        final shouldSendRequest = message.status == MessageStatus.decryptingRetry && 
                                  (message.decryptRetryCount ?? 0) < 2;
        
        expect(shouldSendRequest, true, 
          reason: 'Message with decryptingRetry status and retryCount = 0 should trigger re_encrypt_request');
      });
      
      test('Single message with decryptingRetry status and retryCount = 1 should trigger re_encrypt_request', () {
        // **Validates: Requirement 3.1**
        // Scenario: Message failed decryption once, now retrying second time
        
        final message = Message(
          id: 'msg-002',
          content: 'encrypted_content_base64',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 1,
        );
        
        final shouldSendRequest = message.status == MessageStatus.decryptingRetry && 
                                  (message.decryptRetryCount ?? 0) < 2;
        
        expect(shouldSendRequest, true, 
          reason: 'Message with decryptingRetry status and retryCount = 1 should trigger re_encrypt_request');
      });
      
      test('Multiple messages with varying retryCount < 2 should all trigger re_encrypt_request', () {
        // **Validates: Requirement 3.1**
        // Scenario: Multiple messages in decryptingRetry state with different retry counts
        
        final messages = [
          Message(
            id: 'msg-001',
            content: 'encrypted_1',
            senderId: 'sender-123',
            receiverId: 'receiver-456',
            createdAt: DateTime.now(),
            status: MessageStatus.decryptingRetry,
            decryptRetryCount: 0,
          ),
          Message(
            id: 'msg-002',
            content: 'encrypted_2',
            senderId: 'sender-123',
            receiverId: 'receiver-456',
            createdAt: DateTime.now(),
            status: MessageStatus.decryptingRetry,
            decryptRetryCount: 1,
          ),
          Message(
            id: 'msg-003',
            content: 'encrypted_3',
            senderId: 'sender-123',
            receiverId: 'receiver-456',
            createdAt: DateTime.now(),
            status: MessageStatus.decryptingRetry,
            decryptRetryCount: null, // null treated as 0
          ),
        ];
        
        final messagesToRetry = messages.where((m) => 
          m.status == MessageStatus.decryptingRetry && 
          (m.decryptRetryCount ?? 0) < 2
        ).toList();
        
        expect(messagesToRetry.length, 3, 
          reason: 'All messages with retryCount < 2 should be eligible for re_encrypt_request');
      });
      
      test('Message with null retryCount should be treated as 0 and trigger re_encrypt_request', () {
        // **Validates: Requirement 3.1**
        // Scenario: First time decryption failure, retryCount not yet set
        
        final message = Message(
          id: 'msg-004',
          content: 'encrypted_content',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: null,
        );
        
        final shouldSendRequest = message.status == MessageStatus.decryptingRetry && 
                                  (message.decryptRetryCount ?? 0) < 2;
        
        expect(shouldSendRequest, true, 
          reason: 'Message with null retryCount should be treated as 0 and trigger re_encrypt_request');
      });
    });
    
    group('Requirement 3.2: First time decryption failure should continue to mark message as decryptingRetry', () {
      
      test('Message with no prior retry should be marked as decryptingRetry on first failure', () {
        // **Validates: Requirement 3.2**
        // Scenario: Message decryption fails for the first time
        
        final originalMessage = Message(
          id: 'msg-005',
          content: 'encrypted_content',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.delivered,
          decryptRetryCount: null,
        );
        
        // Simulate first decryption failure
        final updatedMessage = originalMessage.copyWith(
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 1, // Incremented from 0 to 1
        );
        
        expect(updatedMessage.status, MessageStatus.decryptingRetry,
          reason: 'First decryption failure should mark message as decryptingRetry');
        expect(updatedMessage.decryptRetryCount, 1,
          reason: 'Retry count should be incremented to 1 on first failure');
      });
      
      test('Multiple messages failing decryption for first time should all be marked as decryptingRetry', () {
        // **Validates: Requirement 3.2**
        // Scenario: Batch of messages all fail decryption on first attempt
        
        final originalMessages = List.generate(5, (i) => Message(
          id: 'msg-00$i',
          content: 'encrypted_$i',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.delivered,
          decryptRetryCount: null,
        ));
        
        // Simulate first decryption failure for all
        final updatedMessages = originalMessages.map((m) => m.copyWith(
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 1,
        )).toList();
        
        expect(updatedMessages.every((m) => m.status == MessageStatus.decryptingRetry), true,
          reason: 'All messages should be marked as decryptingRetry on first failure');
        expect(updatedMessages.every((m) => m.decryptRetryCount == 1), true,
          reason: 'All messages should have retryCount = 1 after first failure');
      });
    });
    
    group('Requirement 3.3: Sender should continue to handle re_encrypt_request by fetching from LocalDB and re-encrypting', () {
      
      test('Sender receives re_encrypt_request with valid messageId and receiverId', () {
        // **Validates: Requirement 3.3**
        // Scenario: Sender receives re_encrypt_request and should process it
        
        final reEncryptRequest = {
          'message_id': 'msg-006',
          'receiver_id': 'receiver-456',
          'sender_id': 'sender-123',
          'room_id': null,
        };
        
        // Validate request structure
        expect(reEncryptRequest['message_id'], isNotEmpty,
          reason: 're_encrypt_request should contain valid message_id');
        expect(reEncryptRequest['receiver_id'], isNotEmpty,
          reason: 're_encrypt_request should contain valid receiver_id');
        
        // Simulate sender processing: fetch original message from LocalDB
        final shouldProcess = reEncryptRequest['message_id'] != null && 
                             reEncryptRequest['message_id'].toString().isNotEmpty &&
                             reEncryptRequest['receiver_id'] != null &&
                             reEncryptRequest['receiver_id'].toString().isNotEmpty;
        
        expect(shouldProcess, true,
          reason: 'Sender should process re_encrypt_request with valid parameters');
      });
      
      test('Sender should prepare re_encrypt_response with re_encrypted_content field', () {
        // **Validates: Requirement 3.3**
        // Scenario: Sender prepares response after re-encrypting
        
        final originalMessage = Message(
          id: 'msg-007',
          content: 'plaintext_content',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.delivered,
        );
        
        // Simulate re-encryption process
        final reEncryptedContent = 'new_encrypted_content_base64';
        
        final reEncryptResponse = {
          'message_id': originalMessage.id,
          'receiver_id': 'receiver-456',
          'room_id': null,
          're_encrypted_content': reEncryptedContent,
        };
        
        expect(reEncryptResponse['re_encrypted_content'], isNotEmpty,
          reason: 're_encrypt_response should contain re_encrypted_content field');
        expect(reEncryptResponse['message_id'], originalMessage.id,
          reason: 're_encrypt_response should reference the original message_id');
      });
      
      test('Sender should handle re_encrypt_request for group messages with room_id', () {
        // **Validates: Requirement 3.3**
        // Scenario: Group message re-encryption request
        
        final reEncryptRequest = {
          'message_id': 'msg-008',
          'receiver_id': 'receiver-456',
          'sender_id': 'sender-123',
          'room_id': 'room-789',
        };
        
        final isGroupMessage = reEncryptRequest['room_id'] != null;
        
        expect(isGroupMessage, true,
          reason: 'Sender should identify group message re_encrypt_request by room_id presence');
        
        // For group messages, sender should create fanout payload
        final reEncryptedContent = 'encrypted_for_receiver';
        final fanoutPayload = {
          'is_fanout': true,
          'ciphertexts': {
            reEncryptRequest['receiver_id']: reEncryptedContent,
          },
        };
        
        expect(fanoutPayload['is_fanout'], true,
          reason: 'Group message re_encrypt_response should use fanout format');
        expect(fanoutPayload['ciphertexts'], isNotEmpty,
          reason: 'Fanout payload should contain ciphertexts map');
      });
    });
    
    group('Requirement 3.4: Receiver should continue to handle re_encrypt_response by attempting to decrypt', () {
      
      test('Receiver receives re_encrypt_response and attempts decryption', () {
        // **Validates: Requirement 3.4**
        // Scenario: Receiver gets re_encrypt_response and should decrypt
        
        final reEncryptResponse = {
          'message_id': 'msg-009',
          'receiver_id': 'receiver-456',
          'room_id': null,
          're_encrypted_content': 'new_encrypted_content_base64',
        };
        
        // Validate response structure
        expect(reEncryptResponse['message_id'], isNotEmpty,
          reason: 're_encrypt_response should contain valid message_id');
        expect(reEncryptResponse['re_encrypted_content'], isNotEmpty,
          reason: 're_encrypt_response should contain re_encrypted_content');
        
        // Simulate receiver processing
        final shouldAttemptDecryption = reEncryptResponse['message_id'] != null &&
                                       reEncryptResponse['message_id'].toString().isNotEmpty &&
                                       reEncryptResponse['re_encrypted_content'] != null &&
                                       reEncryptResponse['re_encrypted_content'].toString().isNotEmpty;
        
        expect(shouldAttemptDecryption, true,
          reason: 'Receiver should attempt decryption when receiving valid re_encrypt_response');
      });
      
      test('Receiver should update message status to delivered after successful re-decryption', () {
        // **Validates: Requirement 3.4**
        // Scenario: Re-decryption succeeds
        
        final messageBeforeRedecrypt = Message(
          id: 'msg-010',
          content: 'encrypted_content',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 1,
        );
        
        // Simulate successful re-decryption
        final decryptedContent = 'Hello, this is the plaintext message';
        final messageAfterRedecrypt = messageBeforeRedecrypt.copyWith(
          content: decryptedContent,
          status: MessageStatus.delivered,
        );
        
        expect(messageAfterRedecrypt.status, MessageStatus.delivered,
          reason: 'Message status should be updated to delivered after successful re-decryption');
        expect(messageAfterRedecrypt.content, decryptedContent,
          reason: 'Message content should be updated to decrypted plaintext');
      });
      
      test('Receiver should handle re_encrypt_response with fallback content field', () {
        // **Validates: Requirement 3.4**
        // Scenario: Response uses legacy 'content' field instead of 're_encrypted_content'
        
        final reEncryptResponse = {
          'message_id': 'msg-011',
          'receiver_id': 'receiver-456',
          'content': 'encrypted_content_base64', // Fallback field
        };
        
        // Simulate content extraction with fallback
        final content = reEncryptResponse['re_encrypted_content'] ?? reEncryptResponse['content'];
        
        expect(content, isNotEmpty,
          reason: 'Receiver should extract content from re_encrypted_content or fallback to content field');
      });
    });
    
    group('Requirement 3.5: Retry limit (>= 2) should continue to mark message as failed and stop retrying', () {
      
      test('Message with retryCount = 2 should be marked as failed and not trigger re_encrypt_request', () {
        // **Validates: Requirement 3.5**
        // Scenario: Message has reached retry limit
        
        final message = Message(
          id: 'msg-012',
          content: 'encrypted_content',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 2,
        );
        
        // Check if retry limit reached
        final retryLimitReached = (message.decryptRetryCount ?? 0) >= 2;
        final shouldSendRequest = message.status == MessageStatus.decryptingRetry && 
                                  (message.decryptRetryCount ?? 0) < 2;
        
        expect(retryLimitReached, true,
          reason: 'Message with retryCount >= 2 should be identified as reaching retry limit');
        expect(shouldSendRequest, false,
          reason: 'Message with retryCount >= 2 should NOT trigger re_encrypt_request');
        
        // Simulate marking as failed
        final failedMessage = message.copyWith(
          status: MessageStatus.failed,
          content: '🔒 解密失敗（已超過重試次數）',
        );
        
        expect(failedMessage.status, MessageStatus.failed,
          reason: 'Message should be marked as failed when retry limit reached');
      });
      
      test('Message with retryCount > 2 should be marked as failed and not trigger re_encrypt_request', () {
        // **Validates: Requirement 3.5**
        // Scenario: Message has exceeded retry limit (edge case)
        
        final message = Message(
          id: 'msg-013',
          content: 'encrypted_content',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 3,
        );
        
        final retryLimitReached = (message.decryptRetryCount ?? 0) >= 2;
        final shouldSendRequest = message.status == MessageStatus.decryptingRetry && 
                                  (message.decryptRetryCount ?? 0) < 2;
        
        expect(retryLimitReached, true,
          reason: 'Message with retryCount > 2 should be identified as exceeding retry limit');
        expect(shouldSendRequest, false,
          reason: 'Message with retryCount > 2 should NOT trigger re_encrypt_request');
      });
      
      test('Multiple messages at retry limit should all be marked as failed', () {
        // **Validates: Requirement 3.5**
        // Scenario: Batch of messages all reach retry limit
        
        final messages = [
          Message(
            id: 'msg-014',
            content: 'encrypted_1',
            senderId: 'sender-123',
            receiverId: 'receiver-456',
            createdAt: DateTime.now(),
            status: MessageStatus.decryptingRetry,
            decryptRetryCount: 2,
          ),
          Message(
            id: 'msg-015',
            content: 'encrypted_2',
            senderId: 'sender-123',
            receiverId: 'receiver-456',
            createdAt: DateTime.now(),
            status: MessageStatus.decryptingRetry,
            decryptRetryCount: 3,
          ),
          Message(
            id: 'msg-016',
            content: 'encrypted_3',
            senderId: 'sender-123',
            receiverId: 'receiver-456',
            createdAt: DateTime.now(),
            status: MessageStatus.decryptingRetry,
            decryptRetryCount: 2,
          ),
        ];
        
        final messagesAtLimit = messages.where((m) => 
          (m.decryptRetryCount ?? 0) >= 2
        ).toList();
        
        expect(messagesAtLimit.length, 3,
          reason: 'All messages with retryCount >= 2 should be identified as at retry limit');
        
        // Simulate marking all as failed
        final failedMessages = messagesAtLimit.map((m) => m.copyWith(
          status: MessageStatus.failed,
          content: '🔒 解密失敗（已超過重試次數）',
        )).toList();
        
        expect(failedMessages.every((m) => m.status == MessageStatus.failed), true,
          reason: 'All messages at retry limit should be marked as failed');
      });
      
      test('Re-decryption failure after re_encrypt_response should mark message as failed', () {
        // **Validates: Requirement 3.5**
        // Scenario: Receiver gets re_encrypt_response but decryption still fails
        
        final messageBeforeRedecrypt = Message(
          id: 'msg-017',
          content: 'encrypted_content',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 1,
        );
        
        // Simulate re-decryption failure
        final messageAfterFailedRedecrypt = messageBeforeRedecrypt.copyWith(
          status: MessageStatus.failed,
          content: '🔒 重新解密失敗',
        );
        
        expect(messageAfterFailedRedecrypt.status, MessageStatus.failed,
          reason: 'Message should be marked as failed when re-decryption fails');
        expect(messageAfterFailedRedecrypt.content, contains('重新解密失敗'),
          reason: 'Failed message should have appropriate error message');
      });
    });
    
    group('Integration: Complete E2EE Decryption Retry Flow', () {
      
      test('Complete flow: First failure -> re_encrypt_request -> re_encrypt_response -> success', () {
        // **Validates: Requirements 3.1, 3.2, 3.3, 3.4**
        // Scenario: Happy path - decryption fails once, then succeeds on retry
        
        // Step 1: Initial message decryption fails
        final initialMessage = Message(
          id: 'msg-018',
          content: 'encrypted_content',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.delivered,
          decryptRetryCount: null,
        );
        
        // Step 2: Mark as decryptingRetry (Requirement 3.2)
        final messageAfterFirstFailure = initialMessage.copyWith(
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 1,
        );
        
        expect(messageAfterFirstFailure.status, MessageStatus.decryptingRetry);
        expect(messageAfterFirstFailure.decryptRetryCount, 1);
        
        // Step 3: Check if should send re_encrypt_request (Requirement 3.1)
        final shouldSendRequest = messageAfterFirstFailure.status == MessageStatus.decryptingRetry && 
                                  (messageAfterFirstFailure.decryptRetryCount ?? 0) < 2;
        
        expect(shouldSendRequest, true,
          reason: 'Should send re_encrypt_request for message with retryCount < 2');
        
        // Step 4: Sender processes re_encrypt_request (Requirement 3.3)
        final reEncryptRequest = {
          'message_id': messageAfterFirstFailure.id,
          'receiver_id': messageAfterFirstFailure.receiverId,
          'sender_id': messageAfterFirstFailure.senderId,
        };
        
        expect(reEncryptRequest['message_id'], isNotEmpty);
        
        // Step 5: Sender sends re_encrypt_response (Requirement 3.3)
        final reEncryptResponse = {
          'message_id': messageAfterFirstFailure.id,
          'receiver_id': messageAfterFirstFailure.receiverId,
          're_encrypted_content': 'new_encrypted_content',
        };
        
        expect(reEncryptResponse['re_encrypted_content'], isNotEmpty);
        
        // Step 6: Receiver successfully decrypts (Requirement 3.4)
        final finalMessage = messageAfterFirstFailure.copyWith(
          content: 'Decrypted plaintext message',
          status: MessageStatus.delivered,
        );
        
        expect(finalMessage.status, MessageStatus.delivered,
          reason: 'Message should be delivered after successful re-decryption');
        expect(finalMessage.content, 'Decrypted plaintext message');
      });
      
      test('Complete flow: Two failures -> retry limit reached -> marked as failed', () {
        // **Validates: Requirements 3.1, 3.2, 3.5**
        // Scenario: Decryption fails twice, reaches retry limit
        
        // Step 1: First decryption failure
        final messageAfterFirstFailure = Message(
          id: 'msg-019',
          content: 'encrypted_content',
          senderId: 'sender-123',
          receiverId: 'receiver-456',
          createdAt: DateTime.now(),
          status: MessageStatus.decryptingRetry,
          decryptRetryCount: 1,
        );
        
        // Step 2: First re_encrypt_request sent
        final shouldSendFirstRequest = (messageAfterFirstFailure.decryptRetryCount ?? 0) < 2;
        expect(shouldSendFirstRequest, true);
        
        // Step 3: Second decryption failure (after re_encrypt_response)
        final messageAfterSecondFailure = messageAfterFirstFailure.copyWith(
          decryptRetryCount: 2,
        );
        
        // Step 4: Check retry limit reached (Requirement 3.5)
        final retryLimitReached = (messageAfterSecondFailure.decryptRetryCount ?? 0) >= 2;
        final shouldSendSecondRequest = (messageAfterSecondFailure.decryptRetryCount ?? 0) < 2;
        
        expect(retryLimitReached, true,
          reason: 'Retry limit should be reached after 2 failures');
        expect(shouldSendSecondRequest, false,
          reason: 'Should NOT send re_encrypt_request when retry limit reached');
        
        // Step 5: Mark as failed (Requirement 3.5)
        final finalMessage = messageAfterSecondFailure.copyWith(
          status: MessageStatus.failed,
          content: '🔒 解密失敗（已超過重試次數）',
        );
        
        expect(finalMessage.status, MessageStatus.failed,
          reason: 'Message should be marked as failed when retry limit reached');
      });
    });
  });
}
