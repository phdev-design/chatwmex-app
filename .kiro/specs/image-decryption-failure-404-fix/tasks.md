# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Decryption Failure Messages Render as Text
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope the property to concrete failing cases: messages with `msg.type == MessageType.image` and `msg.content` starting with '🔒'
  - Test that when `msg.type == MessageType.image` AND `msg.content` starts with '🔒', the system attempts to load it as a URL (from Bug Condition in design)
  - The test assertions should verify that the widget should be a text bubble (not ImageWidget) and no network request should be made
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found (e.g., "system attempts to load 'http://127.0.0.1:8080/🔒 此訊息無法解密...' as URL, producing 404 error")
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Valid Image URLs Continue to Load
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs (valid image URLs, other message types, empty content)
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements:
    - Valid image URLs (e.g., 'https://example.com/image.jpg') load normally via CachedNetworkImageWidget
    - Other message types (text, voice, file) render according to existing logic
    - Empty content ('') displays existing error handling (broken_image icon)
    - Real image loading errors (network failures) display errorWidget
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [x] 3. Fix for image decryption failure 404 error

  - [x] 3.1 Implement the fix in message_bubble.dart
    - Add decryption failure detection: check if `msg.content` starts with '🔒' when `msg.type == MessageType.image`
    - Consider creating an extension method (e.g., `extension on Message { bool get isDecryptionFailure => type == MessageType.image && content?.startsWith('🔒') == true }`)
    - Add conditional branch: when decryption failure is detected, render as text bubble instead of image widget
    - Ensure text bubble styling matches MessageType.text (background color, padding, text color)
    - Preserve original image loading logic for non-decryption-failure cases
    - Use safe navigation operator `?.` to handle null content
    - Consider defining '🔒' as a constant to avoid hardcoding
    - _Bug_Condition: isBugCondition(msg) where msg.type == MessageType.image AND msg.content starts with '🔒' AND NOT isValidImageUrl(msg.content)_
    - _Expected_Behavior: Render as text bubble without invoking CachedNetworkImageWidget or making network requests (from design Property 1)_
    - _Preservation: Valid image URLs continue to load normally, other message types unchanged, existing error handling preserved (from design Property 2)_
    - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4_

  - [x] 3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Decryption Failure Messages Render as Text
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - Verify that decryption failure messages render as text bubbles
    - Verify no network requests are made for decryption failure messages
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

  - [x] 3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Valid Image URLs Continue to Load
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)
    - Verify valid image URLs still load normally
    - Verify other message types render correctly
    - Verify existing error handling is preserved

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
