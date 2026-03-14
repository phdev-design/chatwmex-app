# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - 解密失敗視覺提示與互動
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: For deterministic bugs, scope the property to the concrete failing case(s) to ensure reproducibility
  - Test that for any message where isDecryptionFailure(message) is true, the MessageBubble displays orange border, shows "🔒 無法解密 點擊重試 ↺" text, and calls retryDecryptMessage on tap
  - The test assertions should match the Expected Behavior Properties from design (Requirements 2.1, 2.2, 2.3)
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found:
    - Decryption failed messages lack orange border
    - Text does not include "點擊重試 ↺" hint
    - Tapping failed messages has no response
    - Retry status shows "等待對方上線" instead of "⏳ 解密中…"
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - 非解密失敗訊息行為
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs (messages where isDecryptionFailure returns false)
  - Observe: Successfully decrypted messages display normally
  - Observe: First-time decrypting messages show original decrypting status
  - Observe: Unencrypted messages display content normally
  - Observe: Long-press on non-failed messages shows action menu (reply, delete, emoji)
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  - Test that for all messages where NOT isDecryptionFailure(message), the display and interaction behavior remains unchanged
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [x] 3. Fix for 解密失敗 UI 改善

  - [x] 3.1 Implement visual and interaction improvements in message_bubble.dart
    - Modify decryption failure text from "🔒 解密失敗" to "🔒 無法解密 點擊重試 ↺" (around line 115)
    - Add orange border to MessageBubble Container when isDecryptionFailure is true: `border: Border.all(color: Colors.orange, width: 2)` (around line 680)
    - Add onTap handler to GestureDetector: when isDecryptionFailure is true and NOT isDecryptingRetry, call `ref.read(chatRoomProvider(widget.params).notifier).retryDecryptMessage(msg.id)` (around line 670)
    - Modify retry status text from "🔒 等待對方上線以重新解密..." to "⏳ 解密中…" while keeping CircularProgressIndicator animation (around line 85)
    - _Bug_Condition: isBugCondition(message) where (message.content.startsWith('🔒') OR message.status == MessageStatus.failed OR looksLikeCiphertext(message.content)) AND NOT hasOrangeBorder(message) AND NOT hasRetryHint(message) AND NOT hasClickHandler(message)_
    - _Expected_Behavior: For any message where isDecryptionFailure(message) is true, MessageBubble SHALL display orange border, show "🔒 無法解密 點擊重試 ↺" text, and call retryDecryptMessage on tap. For any message where isDecryptingRetry(message) is true, MessageBubble SHALL show "⏳ 解密中…" animation_
    - _Preservation: All non-decryption-failed messages (successful decryption, first-time decrypting, unencrypted) SHALL continue to display and interact exactly as before, preserving all existing functionality (normal display, long-press menu, reply, delete, etc.)_
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4_

  - [x] 3.2 Implement retryDecryptMessage method in chat_room_provider.dart
    - Add new method `Future<void> retryDecryptMessage(String messageId)` to ChatRoomNotifier class
    - Method implementation:
      1. Find the corresponding message by messageId
      2. Update message status to MessageStatus.decryptingRetry
      3. Call existing re_encrypt_request sending logic (reuse or extract existing code)
      4. Update local database and UI state
    - _Bug_Condition: Missing retryDecryptMessage method prevents retry functionality_
    - _Expected_Behavior: retryDecryptMessage SHALL update message status to decryptingRetry, send re_encrypt_request, and update UI state_
    - _Preservation: All existing ChatRoomNotifier methods and behaviors SHALL remain unchanged_
    - _Requirements: 2.3, 2.5_

  - [x] 3.3 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - 解密失敗視覺提示與互動
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - Verify orange border displays on decryption failed messages
    - Verify text shows "🔒 無法解密 點擊重試 ↺"
    - Verify tapping calls retryDecryptMessage
    - Verify retry status shows "⏳ 解密中…"
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 3.4 Verify preservation tests still pass
    - **Property 2: Preservation** - 非解密失敗訊息行為
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm successfully decrypted messages display normally
    - Confirm first-time decrypting messages show original status
    - Confirm unencrypted messages display content normally
    - Confirm long-press menu works on non-failed messages
    - Confirm all tests still pass after fix (no regressions)

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
