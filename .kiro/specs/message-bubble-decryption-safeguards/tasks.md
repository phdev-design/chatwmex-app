# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Decryption Failure Detection for All Message Types
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope the property to concrete failing cases: text/voice/file messages with decryption failures
  - Test that for any message where `content.startsWith('🔒')` OR `status == MessageStatus.failed` (and type is NOT image), the widget displays lock icon with error text and does NOT evaluate `msg.linkPreview`
  - Test cases to include:
    - Text message with `content == '🔒 encrypted_data'` → should display lock icon (will fail on unfixed code)
    - Voice message with `content.startsWith('🔒')` → should display lock icon (will fail on unfixed code)
    - File message with `status == MessageStatus.failed` → should display lock icon (will fail on unfixed code)
    - Image message with `content.startsWith('🔒')` → should display lock icon (should pass on unfixed code - baseline)
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS for text/voice/file messages (this is correct - it proves the bug exists)
  - Document counterexamples found: which message types fail to display lock icon, which cause Regex errors from linkPreview evaluation
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 2.5_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Successfully Decrypted Message Behavior
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for successfully decrypted messages (where `content` does NOT start with '🔒' AND `status` is NOT `MessageStatus.failed`)
  - Write property-based tests capturing observed behavior patterns:
    - Successfully decrypted image messages render with tap-to-view functionality
    - Successfully decrypted voice messages render AudioMessageBubble widget
    - Successfully decrypted file messages render with tap-to-open functionality
    - Successfully decrypted text messages with valid URLs display link previews
    - Messages with `status == MessageStatus.decryptingRetry` display loading spinner with "🔒 等待對方上線以重新解密..." message
    - Unsent messages (`isUnsent == true`) display "此訊息已收回" regardless of decryption status
    - Successfully decrypted messages display reactions, reply content, timestamp, and status icons
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 3. Fix for decryption failure detection across all message types

  - [x] 3.1 Implement the fix in message_bubble.dart
    - Broaden `isDecryptionFailure` check (line 73-75): change from `msg.type == MessageType.image && msg.content.startsWith(decryptionFailurePrefix)` to `msg.content.startsWith(decryptionFailurePrefix) || msg.status == MessageStatus.failed`
    - Add dedicated decryption failure branch after line 97: insert `else if (isDecryptionFailure)` branch that displays lock icon with error text
    - Prevent link preview evaluation on encrypted content (line 286): change `hasPreview` calculation to include `!isDecryptionFailure && !isDecryptingRetry` checks
    - Ensure conditional logic order: `isDecryptingRetry` → `isDecryptionFailure` → normal message type processing
    - Add safety comments explaining the checks apply to all message types
    - _Bug_Condition: isBugCondition(input) where (input.content.startsWith('🔒') OR input.status == MessageStatus.failed) AND input.type != MessageType.image_
    - _Expected_Behavior: Display lock icon with error text, set hasPreview = false, do NOT evaluate msg.linkPreview, do NOT resolve image URLs_
    - _Preservation: Successfully decrypted messages (all types), decryptingRetry status messages, unsent messages, and all message interactions must remain unchanged_
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

  - [x] 3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Decryption Failure Detection for All Message Types
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES for all message types (confirms bug is fixed)
    - Verify that text/voice/file messages with decryption failures now display lock icon
    - Verify that no Regex errors occur from linkPreview evaluation
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Successfully Decrypted Message Behavior
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix: image rendering, voice playback, file attachments, link previews, decryptingRetry spinner, unsent messages, reactions, replies
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
