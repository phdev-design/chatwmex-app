# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Skip Re-encrypt Request for Already Decrypted Messages
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope the property to concrete failing cases: messages with statusInDB=decryptingRetry but statusInMemory=read/delivered/sent
  - Test that system skips sending re_encrypt_request for messages where isBugCondition(input) is true (from Bug Condition in design)
  - Test assertions should verify: NOT re_encrypt_request_sent_for_already_decrypted_messages(result) AND log_contains_skip_reason(result)
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found:
    - System sends re_encrypt_request for messages already in read/delivered status
    - Log shows "Message is not in decryptingRetry status: MessageStatus.read" errors
    - Same messages get re_encrypt_request sent twice (duplicate initialization)
    - LocalDB status remains 'decryptingRetry' after successful decryption
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Continue Re-encrypt Request for Decrypting Messages
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs (messages where statusInMemory == decryptingRetry AND retryCount < 2)
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements:
    - First time decryption failure: system marks message as decryptingRetry and sends re_encrypt_request
    - Sender receives re_encrypt_request: system fetches original message from LocalDB and re-encrypts
    - Receiver receives re_encrypt_response: system attempts to decrypt and updates message status
    - Retry limit reached (>= 2): system marks message as MessageStatus.failed and stops retrying
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 3. Fix for E2EE duplicate re-encrypt request bug

  - [x] 3.1 Add initialization guard flag in ChatRoomProvider
    - Add `bool _isAutoResendInitialized = false;` field to ChatRoomViewModel class
    - This flag prevents duplicate initialization in the same session
    - _Bug_Condition: isBugCondition(input) where input.event IN ['hot_restart', 'ws_reconnected'] AND duplicate initialization occurs_
    - _Expected_Behavior: Initialization logic executes at most once per session (Property 4)_
    - _Preservation: Normal decryption retry flow for messages with statusInMemory == decryptingRetry_
    - _Requirements: 2.2_

  - [x] 3.2 Implement _initializeAutoResend() method in ChatRoomProvider
    - Check `_isAutoResendInitialized` flag, return early if already initialized
    - Query LocalDB for all messages with status = 'decryptingRetry' using new helper method
    - For each message, check current status in `state.messages`
    - If memory status is read/delivered/sent/failed, skip and log reason
    - If memory status is decryptingRetry AND retryCount < 2, send re_encrypt_request
    - Set `_isAutoResendInitialized = true` after completion
    - _Bug_Condition: isBugCondition(input) where messages have statusInDB=decryptingRetry but statusInMemory IN [read, delivered, sent]_
    - _Expected_Behavior: Skip sending re_encrypt_request and log skip reason (Property 1)_
    - _Preservation: Continue sending re_encrypt_request for messages with statusInMemory == decryptingRetry (Property 2)_
    - _Requirements: 2.1, 2.4, 3.1_

  - [x] 3.3 Add _getDecryptingRetryMessages() helper method in ChatRoomProvider
    - Call LocalDbService().getDecryptingRetryMessages()
    - Return Future<List<Message>>
    - _Requirements: 2.1_

  - [x] 3.4 Implement getDecryptingRetryMessages() in LocalDbService
    - Query all messages with status = 'decryptingRetry'
    - Order by created_at ASC (process older messages first)
    - Return Future<List<Message>>
    - _Requirements: 2.1_

  - [x] 3.5 Call _initializeAutoResend() in build() method
    - Add after `Future.microtask(() => loadHistory());`
    - Use `Future.microtask(() => _initializeAutoResend());` for delayed execution
    - _Requirements: 2.1, 2.2_

  - [x] 3.6 Reset flag in ws_disconnected event handler
    - Set `_isAutoResendInitialized = false;` in ws_disconnected event handler
    - **CRITICAL**: Must reset flag on disconnect, otherwise subsequent reconnections will not trigger auto-resend
    - This ensures every reconnection can properly execute auto-resend logic
    - _Bug_Condition: Without reset, second and subsequent reconnections will skip auto-resend_
    - _Expected_Behavior: Flag resets on disconnect, allowing auto-resend on every reconnection_
    - _Requirements: 2.2_

  - [x] 3.7 Call _initializeAutoResend() in ws_reconnected event handler
    - Add after `resendPendingMessages();`
    - Ensures auto-retry of incomplete decryption messages after reconnection
    - _Requirements: 2.1, 2.2_

  - [x] 3.8 Update LocalDB status in _tryDecryptMessage() method
    - After successful decryption (before `return m.copyWith(content: decrypted);`)
    - Call `LocalDbService().updateMessageStatus(m.clientMsgId ?? m.id, MessageStatus.delivered);`
    - **CRITICAL**: Use `clientMsgId ?? m.id` because during loadHistory, message.id may be clientMsgId not server id
    - Ensures database state syncs with memory state
    - _Bug_Condition: isBugCondition(input) where message.statusInDB remains 'decryptingRetry' after successful decryption_
    - _Expected_Behavior: LocalDB status updates to match in-memory status (Property 3)_
    - _Preservation: Normal message status update flow_
    - _Requirements: 2.3_

  - [x] 3.9 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Skip Re-encrypt Request for Already Decrypted Messages
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - Verify system skips sending re_encrypt_request for messages with statusInMemory IN [read, delivered, sent]
    - Verify log contains skip reasons
    - Verify no duplicate initialization occurs
    - Verify LocalDB status syncs after successful decryption
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 3.10 Verify preservation tests still pass
    - **Property 2: Preservation** - Continue Re-encrypt Request for Decrypting Messages
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all preservation behaviors still work:
      - First time decryption failure handling
      - Re-encrypt request/response flow
      - Retry limit enforcement
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 4. Checkpoint - Ensure all tests pass
  - Verify bug condition test passes (messages with statusInMemory=read/delivered/sent are skipped)
  - Verify preservation tests pass (messages with statusInMemory=decryptingRetry continue normal flow)
  - Verify no duplicate re_encrypt_request sends occur
  - Verify LocalDB status syncs correctly after decryption
  - Ask user if questions arise
