# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Count Matches Rendered Items
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Test with concrete failing cases - messages with Base64 encrypted content (≥40 chars with +/= characters) that fail decryption
  - Test that when backend returns mixed valid/invalid messages (e.g., 10 total with 3 having invalid encrypted content), the state.messages.length includes all 10 but only 7 are renderable (resolveFullUrl returns non-empty for 7)
  - Test scenarios: (1) 10 messages with 3 invalid Base64 content, (2) 5 messages all invalid, (3) pagination with invalid messages in both batches
  - Run test on UNFIXED code in room_media_provider.dart
  - **EXPECTED OUTCOME**: Test FAILS showing count mismatch (e.g., state.messages.length=10 but countOfRenderedItems=7)
  - Document counterexamples found: messages where resolveFullUrl(message.content) returns empty string but message is still in state.messages
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Valid Messages Unchanged
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for valid messages (where resolveFullUrl returns non-empty strings)
  - Observe: Messages with plaintext URLs (http://, https://) are included in state and rendered
  - Observe: Messages with relative paths (/uploads/) are included in state and rendered
  - Observe: Messages with ObjectIDs (24-char hex) are included in state and rendered
  - Observe: Pagination with loadMore() merges messages correctly without duplicates
  - Write property-based tests capturing these observed behavior patterns:
    - For all messages where resolveFullUrl(content) returns non-empty string, message is in state.messages
    - For all valid message types (URL, path, ObjectID), count equals number of rendered items
    - For pagination scenarios, merged list has no duplicates and all messages have valid URLs
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 3. Fix for media count display mismatch

  - [x] 3.1 Add post-decryption filtering in room_media_provider.dart
    - Import resolveFullUrl from app/lib/features/chat/utils/chat_url_utils.dart
    - Create private method _filterValidMedia(List<Message> messages) that filters out messages where resolveFullUrl(message.content) returns empty string
    - Update loadInitial() to pass _decryptMediaContent result through _filterValidMedia before storing in state
    - Update loadMore() to pass _decryptMediaContent result through _filterValidMedia before merging with existing messages
    - _Bug_Condition: isBugCondition(message) where resolveFullUrl(message.content).isEmpty AND message is in RoomMediaState.messages_
    - _Expected_Behavior: For all messages where isBugCondition returns true, filter them out so state.messages.length equals countOfRenderedItems_
    - _Preservation: For all messages where resolveFullUrl returns non-empty string, continue to include in state and display unchanged (Requirements 3.1-3.5)_
    - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x] 3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Count Matches Rendered Items
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed - count now matches rendered items)
    - _Requirements: 2.1, 2.2, 2.3_

  - [x] 3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Valid Messages Unchanged
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions - valid messages still processed correctly)
    - Confirm all tests still pass after fix (pagination, plaintext handling, grouping all unchanged)

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
