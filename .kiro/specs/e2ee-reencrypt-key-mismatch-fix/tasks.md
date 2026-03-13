# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Re-Encrypted Content Reading
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope the property to payloads with `'re_encrypted_content'` present but `'content'` absent or null
  - Test that `_handleReEncryptResponse` successfully reads re-encrypted content when payload contains `'re_encrypted_content'` key
  - Test assertions should verify: content is read correctly, decryption proceeds, message status updates to `delivered`
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS with "Invalid re_encrypt_response: missing content" log and early return (this is correct - it proves the bug exists)
  - Document counterexamples found: `payload['content']` returns null when `'re_encrypted_content'` is present, causing validation failure
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 2.1, 2.2_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Validation and Error Handling
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs (validation failures, legacy `'content'` key, decryption errors)
  - Write property-based tests capturing observed behavior patterns:
    - Missing `message_id` → early return with error log
    - Wrong `receiver_id` → security warning and early return
    - Message not in `decryptingRetry` → skip processing with status log
    - Decryption failure → message remains in `decryptingRetry` status
    - Legacy `'content'` key only → successful processing (backward compatibility)
    - Both keys present → verify priority behavior
    - Empty content string → validation catches empty strings
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 2.3, 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 3. Fix for E2EE re-encrypt key mismatch

  - [x] 3.1 Implement the fix in _handleReEncryptResponse
    - Update line 921 in `app/lib/features/chat/providers/chat_room_provider.dart`
    - Change: `final content = payload['content'] as String?;`
    - To: `final content = (payload['re_encrypted_content'] ?? payload['content']) as String?;`
    - This reads from `'re_encrypted_content'` first, falling back to `'content'` for backward compatibility
    - _Bug_Condition: isBugCondition(payload) where payload['re_encrypted_content'] IS NOT NULL AND payload['content'] IS NULL_
    - _Expected_Behavior: For any re_encrypt_response payload where 're_encrypted_content' is present, the function SHALL successfully read the re-encrypted content, proceed with decryption, and update message status to delivered_
    - _Preservation: All validation logic (message_id, receiver_id, message status), decryption flows, LocalDB updates, UI updates, and error handling must remain unchanged. Backward compatibility with 'content' key must be maintained._
    - _Requirements: 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x] 3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Re-Encrypted Content Reading
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed - content is read from 're_encrypted_content', decryption proceeds, status updates to delivered)
    - _Requirements: 2.1, 2.2_

  - [x] 3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Validation and Error Handling
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions - all validation logic, backward compatibility, and error handling preserved)
    - Confirm all tests still pass after fix (no regressions)
    - _Requirements: 2.3, 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
