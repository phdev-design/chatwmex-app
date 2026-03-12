# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Re-encryption Response Field Name Mismatch
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the backend rejects re-encryption responses due to field name mismatch
  - **Scoped PBT Approach**: Scope the property to re_encrypt_response messages with the field name `content` instead of `re_encrypted_content`
  - Test that when the frontend sends a `re_encrypt_response` WebSocket message with field name `content`, the backend rejects it with "Missing required fields in re_encrypt_response"
  - Test that messages remain encrypted and cannot be displayed when re-encryption responses are rejected
  - The test assertions should verify: (1) backend logs show rejection error, (2) messages remain encrypted, (3) payload contains `content` field instead of `re_encrypted_content`
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found: specific messages that fail re-encryption, backend error logs, payload structure showing wrong field name
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Other WebSocket Messages Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-re_encrypt_response WebSocket messages (regular chat messages, control messages, etc.)
  - Write property-based tests capturing observed behavior: for all WebSocket messages where type != 're_encrypt_response', the payload structure and field names remain unchanged
  - Property-based testing generates many test cases across different message types for stronger guarantees
  - Test cases should cover: (1) regular chat messages with existing field names, (2) other E2EE control messages, (3) already decrypted messages display correctly, (4) other payload fields (message_id, room_id, receiver_id) in re_encrypt_response remain unchanged
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [-] 3. Fix field name mismatch in re-encryption response

  - [x] 3.1 Implement the fix in chat_room_provider.dart
    - Open file `app/lib/features/chat/providers/chat_room_provider.dart`
    - Navigate to the `_handleReEncryptRequest` method (around line 961)
    - Change the field name from `'content': reEncryptedContent` to `'re_encrypted_content': reEncryptedContent`
    - Verify that all other fields (message_id, receiver_id, room_id) remain unchanged
    - Verify that no other WebSocket message types are affected by this change
    - _Bug_Condition: isBugCondition(input) where input.messageType == 're_encrypt_response' AND input.payload.hasField('content') AND NOT input.payload.hasField('re_encrypted_content')_
    - _Expected_Behavior: After fix, payload SHALL contain 're_encrypted_content' field (not 'content'), backend SHALL successfully validate and accept the response, messages SHALL be decrypted and displayed correctly_
    - _Preservation: Other WebSocket message types (not re_encrypt_response) SHALL continue to use existing field names; backend E2EE decryption logic SHALL remain unchanged; already decrypted messages SHALL continue to display correctly; other payload fields SHALL remain unchanged_
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 3.1, 3.2, 3.3, 3.4_

  - [x] 3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Re-encryption Response Field Name Correctness
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - Verify: (1) backend accepts re-encryption responses without "Missing required fields" error, (2) messages are successfully decrypted, (3) payload contains `re_encrypted_content` field, (4) images and content display correctly
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Other WebSocket Messages Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix: (1) regular chat messages work unchanged, (2) other E2EE messages work unchanged, (3) already decrypted messages display correctly, (4) other payload fields remain unchanged
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [x] 4. Checkpoint - Ensure all tests pass
  - Run all tests (bug condition test + preservation tests)
  - Verify no backend errors in logs related to "Missing required fields in re_encrypt_response"
  - Verify messages decrypt and display correctly in the UI
  - Verify images show correctly (not broken/missing)
  - If any issues arise, document them and ask the user for guidance
