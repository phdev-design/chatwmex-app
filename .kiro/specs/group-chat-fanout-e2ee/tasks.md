# Implementation Plan: Group Chat Fan-out E2EE

## Overview

This plan implements Client-Side Fan-out End-to-End Encryption for group chats in the Flutter messaging system. The implementation extends the existing X25519 + AES-GCM encryption to support group chats by encrypting each message individually for every member. The approach ensures zero-knowledge server architecture, backward compatibility with plaintext messages, and maintains the existing one-to-one E2EE functionality.

## Tasks

- [x] 1. Implement core fan-out encryption and decryption methods
  - [x] 1.1 Implement _encryptGroupMessage method in ChatRoomProvider
    - Create method that takes plaintext and member IDs
    - Fetch public keys for all members using PublicKeyCacheService
    - Encrypt message for each member with valid public key
    - Build fan-out payload with is_fanout flag and ciphertexts map
    - Return JSON-encoded payload string
    - Handle partial encryption success (at least one member succeeds)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 4.4, 10.4_
  
  - [ ]* 1.2 Write property test for fan-out encryption completeness
    - **Property 1: Fan-out Encryption Completeness**
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.4**
  
  - [ ]* 1.3 Write property test for fan-out payload structure validity
    - **Property 2: Fan-out Payload Structure Validity**
    - **Validates: Requirements 1.5, 1.6, 15.1, 15.2, 15.3**
  
  - [ ]* 1.4 Write property test for fan-out serialization round-trip
    - **Property 3: Fan-out Serialization Round-trip**
    - **Validates: Requirements 1.7**
  
  - [x] 1.5 Implement _decryptGroupMessage method in ChatRoomProvider
    - Create method that takes message content and sender ID
    - Parse content as JSON and check for is_fanout flag
    - Extract ciphertexts map and retrieve current user's ciphertext
    - Fetch sender's public key from PublicKeyCacheService
    - Decrypt using CryptoService.decryptMessage
    - Return plaintext on success, error messages on failure
    - Handle backward compatibility (non-fanout messages return as-is)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 7.1, 7.2, 11.1, 11.2, 11.3, 11.4_
  
  - [ ]* 1.6 Write property test for fan-out decryption extraction
    - **Property 4: Fan-out Decryption Extraction**
    - **Validates: Requirements 2.1, 2.2, 2.3, 2.4**
  
  - [ ]* 1.7 Write property test for successful decryption returns plaintext
    - **Property 5: Successful Decryption Returns Plaintext**
    - **Validates: Requirements 2.5**
  
  - [ ]* 1.8 Write unit tests for _encryptGroupMessage
    - Test encryption with all members having valid keys
    - Test encryption with some members missing keys
    - Test encryption with no members having keys (should throw)
    - Test encryption with empty member list
    - Test encryption with single member
    - Test encryption with 50 members (max size)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 4.4, 10.2, 10.3_
  
  - [ ]* 1.9 Write unit tests for _decryptGroupMessage
    - Test decryption with valid fan-out payload
    - Test decryption with plaintext message (backward compatibility)
    - Test decryption with missing user ciphertext
    - Test decryption with invalid JSON
    - Test decryption with corrupted ciphertext
    - Test decryption with unavailable sender key
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 7.1, 7.2, 11.1, 11.2, 11.3, 11.4_

- [x] 2. Modify _tryDecryptMessage to handle group and private messages
  - [x] 2.1 Update _tryDecryptMessage method in ChatRoomProvider
    - Check E2EE toggle state for the room
    - Branch on arg.isRoom flag to determine message type
    - For group messages: call _decryptGroupMessage
    - For private messages: use existing one-to-one decryption logic
    - Return message with decrypted content or error message
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 3.4, 3.5, 18.3, 18.4, 18.5_
  
  - [ ]* 2.2 Write property test for E2EE toggle controls decryption
    - **Property 7: E2EE Toggle Controls Decryption Attempts**
    - **Validates: Requirements 3.4, 3.5**
  
  - [ ]* 2.3 Write property test for private message encryption separation
    - **Property 22: Private Message Encryption Separation**
    - **Validates: Requirements 18.1, 18.3, 18.4**
  
  - [ ]* 2.4 Write unit tests for _tryDecryptMessage
    - Test group message decryption with E2EE enabled
    - Test group message display with E2EE disabled
    - Test private message decryption (should use one-to-one logic)
    - Test mixed message history rendering
    - _Requirements: 3.4, 3.5, 7.4, 18.3, 18.4_

- [x] 3. Checkpoint - Ensure core encryption/decryption tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Integrate fan-out encryption into sendMessage method
  - [x] 4.1 Modify sendMessage method in ChatRoomProvider
    - Check E2EE toggle state and isRoom flag
    - For group messages with E2EE enabled: fetch member list and call _encryptGroupMessage
    - For group messages with E2EE disabled: send plaintext
    - For private messages: use existing one-to-one encryption
    - Set payloadContent to encrypted or plaintext based on conditions
    - Handle encryption errors and display appropriate error messages
    - Preserve link preview metadata alongside encrypted content
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 3.1, 3.2, 3.3, 9.1, 9.2, 9.5, 10.1, 10.2, 10.3, 10.4, 13.1, 13.2, 18.1, 18.2_
  
  - [ ]* 4.2 Write property test for E2EE toggle controls encryption strategy
    - **Property 6: E2EE Toggle Controls Encryption Strategy**
    - **Validates: Requirements 3.1, 3.2, 3.3**
  
  - [ ]* 4.3 Write property test for member list snapshot consistency
    - **Property 15: Member List Snapshot Consistency**
    - **Validates: Requirements 9.1, 9.2, 9.5**
  
  - [ ]* 4.4 Write property test for zero-knowledge content transmission
    - **Property 17: Zero-Knowledge Content Transmission**
    - **Validates: Requirements 12.3**
  
  - [ ]* 4.5 Write property test for fan-out payload plaintext exclusion
    - **Property 18: Fan-out Payload Plaintext Exclusion**
    - **Validates: Requirements 12.4**
  
  - [ ]* 4.6 Write property test for link preview preservation
    - **Property 19: Link Preview Preservation**
    - **Validates: Requirements 13.1, 13.2, 13.5**
  
  - [ ]* 4.7 Write unit tests for sendMessage with fan-out
    - Test sending group message with E2EE enabled
    - Test sending group message with E2EE disabled
    - Test sending private message (should not use fan-out)
    - Test sending message with link preview and E2EE
    - Test error handling for member list fetch failure
    - Test error handling for complete public key unavailability
    - Test error handling for complete encryption failure
    - _Requirements: 3.1, 3.2, 3.3, 10.1, 10.2, 10.3, 13.1, 13.2, 18.1, 18.2_

- [x] 5. Integrate fan-out encryption into resendPendingMessages method
  - [x] 5.1 Modify resendPendingMessages method in ChatRoomProvider
    - Identify pending group messages for the room
    - Check E2EE toggle state for each message
    - For group messages with E2EE enabled: fetch current member list and call _encryptGroupMessage
    - For group messages with E2EE disabled: resend plaintext
    - Preserve link preview metadata through encryption and resend
    - Use current member list at resend time (not original member list)
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 9.1, 9.2, 9.5_
  
  - [ ]* 5.2 Write property test for pending message encryption consistency
    - **Property 10: Pending Message Encryption Consistency**
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5**
  
  - [ ]* 5.3 Write unit tests for resendPendingMessages
    - Test resending pending group message with E2EE enabled
    - Test resending pending group message with E2EE disabled
    - Test preserving link preview during resend
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [x] 6. Integrate fan-out encryption into retrySend method
  - [x] 6.1 Modify retrySend method in ChatRoomProvider
    - Check E2EE toggle state and isRoom flag
    - For group messages with E2EE enabled: fetch current member list and call _encryptGroupMessage
    - For group messages with E2EE disabled: retry with plaintext
    - Preserve link preview metadata through encryption and retry
    - Use current member list at retry time (not original member list)
    - Handle encryption errors and update message status appropriately
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 9.1, 9.2, 9.5_
  
  - [ ]* 6.2 Write property test for retry message encryption consistency
    - **Property 11: Retry Message Encryption Consistency**
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5**
  
  - [ ]* 6.3 Write unit tests for retrySend
    - Test retrying failed group message with E2EE enabled
    - Test retrying failed group message with E2EE disabled
    - Test preserving link preview during retry
    - Test error handling for encryption failure during retry
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [x] 7. Checkpoint - Ensure integration tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Enhance PublicKeyCacheService with batch fetching
  - [x] 8.1 Add getPublicKeys batch method to PublicKeyCacheService
    - Create method that takes list of user IDs
    - Fetch all keys in parallel using Future.wait
    - Return map of user IDs to public keys (null for unavailable)
    - Leverage existing getPublicKey method for caching and deduplication
    - _Requirements: 4.1, 4.2, 4.3_
  
  - [ ]* 8.2 Write property test for public key cache deduplication
    - **Property 8: Public Key Cache Deduplication**
    - **Validates: Requirements 4.2**
  
  - [ ]* 8.3 Write property test for graceful key unavailability handling
    - **Property 9: Graceful Key Unavailability Handling**
    - **Validates: Requirements 4.3, 4.4, 10.4**
  
  - [ ]* 8.4 Write unit tests for getPublicKeys
    - Test fetching keys for multiple users
    - Test caching behavior (no redundant API calls)
    - Test handling of unavailable keys
    - _Requirements: 4.1, 4.2, 4.3_

- [x] 9. Implement encryption performance optimizations
  - [x] 9.1 Add parallel encryption to _encryptGroupMessage
    - Batch encryption operations in groups of 10
    - Use Future.wait for concurrent encryption
    - Ensure UI thread is not blocked (already async)
    - Display message in "sending" status during encryption
    - _Requirements: 8.1, 8.2, 8.3_
  
  - [ ]* 9.2 Write property test for encryption status feedback
    - **Property 14: Encryption Status Feedback**
    - **Validates: Requirements 8.3**
  
  - [ ]* 9.3 Write performance tests for encryption
    - Test encryption time for 10, 25, 50 member groups
    - Verify completion within 2000ms for 50 members
    - Verify UI remains responsive during encryption
    - _Requirements: 8.1, 8.2_

- [x] 10. Add comprehensive error handling and logging
  - [x] 10.1 Enhance error handling in _encryptGroupMessage
    - Add specific error messages for member list fetch failure
    - Add specific error messages for complete key unavailability
    - Add specific error messages for complete encryption failure
    - Log encryption errors without exposing sensitive data
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
  
  - [x] 10.2 Enhance error handling in _decryptGroupMessage
    - Handle JSON parse failures gracefully (treat as plaintext)
    - Display appropriate message for missing user ciphertext
    - Display appropriate message for decryption failures
    - Display appropriate message for unavailable sender key
    - Log decryption errors without exposing sensitive data
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_
  
  - [ ]* 10.3 Write unit tests for error handling
    - Test all encryption error scenarios
    - Test all decryption error scenarios
    - Verify error messages are user-friendly
    - Verify no sensitive data in logs
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 11.1, 11.2, 11.3, 11.4, 11.5_

- [x] 11. Implement backward compatibility and edge case handling
  - [x] 11.1 Add backward compatibility checks in _decryptGroupMessage
    - Handle plaintext messages in E2EE-enabled rooms
    - Handle messages without is_fanout flag
    - Handle messages with is_fanout set to false
    - Display all messages without decryption errors
    - _Requirements: 7.1, 7.2, 7.3_
  
  - [ ]* 11.2 Write property test for backward compatibility with plaintext
    - **Property 12: Backward Compatibility with Plaintext**
    - **Validates: Requirements 7.1, 7.2, 7.3**
  
  - [ ]* 11.3 Write property test for mixed message history rendering
    - **Property 13: Mixed Message History Rendering**
    - **Validates: Requirements 7.4**
  
  - [ ]* 11.4 Write unit tests for edge cases
    - Test empty member list
    - Test single member group
    - Test maximum size group (50 members)
    - Test message with special characters
    - Test very long message content
    - Test concurrent encryption operations
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 8.1_

- [x] 12. Implement member list timing and consistency properties
  - [x] 12.1 Add member list snapshot logic to _encryptGroupMessage
    - Capture member list once at start of encryption
    - Use captured list for all encryption operations
    - Do not refetch member list during encryption
    - _Requirements: 9.1, 9.2, 9.5_
  
  - [ ]* 12.2 Write property test for member list timing independence
    - **Property 16: Member List Timing Independence**
    - **Validates: Requirements 9.3, 9.4**
  
  - [ ]* 12.3 Write unit tests for member list consistency
    - Test member joining during encryption (should not be included)
    - Test member leaving during encryption (should still be included)
    - _Requirements: 9.3, 9.4_

- [x] 13. Implement link preview handling with encryption
  - [x] 13.1 Ensure link preview preservation in sendMessage
    - Verify link preview metadata is preserved separately from encrypted content
    - Verify link preview is included in payload alongside fan-out payload
    - Verify link preview is not encrypted
    - _Requirements: 13.1, 13.2, 13.5_
  
  - [x] 13.2 Ensure link preview display after decryption
    - Verify link preview displays correctly after successful decryption
    - _Requirements: 13.3_
  
  - [ ]* 13.3 Write property test for link preview display after decryption
    - **Property 20: Link Preview Display After Decryption**
    - **Validates: Requirements 13.3**
  
  - [ ]* 13.4 Write unit tests for link preview handling
    - Test sending message with link preview and E2EE enabled
    - Test receiving message with link preview and decryption
    - Test resending message with link preview
    - Test retrying message with link preview
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_

- [x] 14. Implement unique ciphertext per recipient validation
  - [x] 14.1 Add validation for unique ciphertexts in _encryptGroupMessage
    - Ensure separate encryption operation for each member ID
    - Ensure distinct ciphertext map entries for each member
    - Handle case where two members have same public key (still encrypt separately)
    - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.5_
  
  - [ ]* 14.2 Write property test for unique ciphertext per recipient
    - **Property 21: Unique Ciphertext Per Recipient**
    - **Validates: Requirements 16.1, 16.4, 16.5**
  
  - [ ]* 14.3 Write unit tests for unique ciphertext validation
    - Test that each member gets distinct ciphertext
    - Test that ciphertext map has one entry per member ID
    - Test handling of members with same public key
    - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.5_

- [x] 15. Implement transparent user experience requirements
  - [x] 15.1 Verify encryption/decryption happens without user interaction
    - Ensure no user prompts during encryption/decryption
    - Ensure no cryptographic details displayed in UI
    - Ensure encrypted messages display identically to plaintext (except errors)
    - _Requirements: 17.1, 17.2, 17.3, 17.4, 17.5_
  
  - [ ]* 15.2 Write integration tests for transparent UX
    - Test that encryption is invisible to user
    - Test that decryption is invisible to user
    - Test that messages display normally
    - _Requirements: 17.1, 17.2, 17.3, 17.4, 17.5_

- [x] 16. Final checkpoint - Run all tests and verify requirements
  - Ensure all tests pass, ask the user if questions arise.

- [x] 17. Integration and end-to-end validation
  - [ ]* 17.1 Write end-to-end integration tests
    - Test complete encryption flow from User A to User B
    - Test mixed message history (plaintext + encrypted)
    - Test member list changes during encryption
    - Test public key cache behavior across multiple messages
    - _Requirements: All requirements_
  
  - [x] 17.2 Write performance validation tests
    - Measure and validate encryption performance for various group sizes
    - Measure and validate decryption performance
    - Monitor memory usage during encryption
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties (22 properties total)
- Unit tests validate specific examples and edge cases
- The implementation reuses existing CryptoService primitives (X25519 + AES-GCM)
- All encryption/decryption operations are asynchronous to avoid blocking UI
- Backward compatibility with plaintext messages is maintained throughout
- Private message encryption remains unchanged (one-to-one E2EE)
