# Implementation Plan

## Bug Fix 1: WebSocket Read Limit Exceeded

- [x] 1.1 Write bug condition exploration test
  - **Property 1: Bug Condition** - Large Payload WebSocket Disconnection
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope the property to payloads > 8KB (e.g., 10KB, 50KB, 100KB)
  - Test that WebSocket connection crashes when receiving group message with Fan-out E2EE payload > 8KB
  - The test assertions should verify connection remains alive after receiving large payload
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1_

- [x] 1.2 Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Small Payload Normal Transmission
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for payloads < 1MB
  - Write property-based tests capturing that WebSocket continues to transmit messages normally for payloads < 1MB
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1_

- [ ] 1.3 Fix WebSocket read limit
  - [x] 1.3.1 Implement the fix
    - Update `maxMessageSize` in `backend/internal/delivery/websocket/client.go` to `1048576` (1MB)
    - Ensure WebSocket can handle Fan-out E2EE payloads up to 1MB
    - _Bug_Condition: payload size > 8KB_
    - _Expected_Behavior: WebSocket accepts messages up to 1MB without disconnection_
    - _Preservation: Messages < 1MB continue to transmit normally_
    - _Requirements: 1.1, 2.1, 3.1_

  - [x] 1.3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Large Payload Accepted
    - **IMPORTANT**: Re-run the SAME test from task 1.1 - do NOT write a new test
    - The test from task 1.1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1.1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - _Requirements: 2.1_

  - [x] 1.3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Small Payload Still Works
    - **IMPORTANT**: Re-run the SAME tests from task 1.2 - do NOT write new tests
    - Run preservation property tests from step 1.2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

- [x] 1.4 Checkpoint - Ensure all tests pass for Bug Fix 1

## Bug Fix 2: Message Type Overwrite Issue

- [x] 2.1 Write bug condition exploration test
  - **Property 1: Bug Condition** - Link Preview Type Overwrite Crash
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope to messages with Link Preview metadata
  - Test that backend overwrites msg.Type to "link" when Link Preview detected, causing Flutter StateError in Message.fromJson()
  - The test assertions should verify msg.Type remains unchanged
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.2_

- [x] 2.2 Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Non-Link-Preview Message Type Handling
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for messages without Link Preview
  - Write property-based tests capturing that backend continues to process message types normally
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.2_

- [ ] 2.3 Fix message type overwrite
  - [x] 2.3.1 Implement the fix
    - Remove forced msg.Type = "link" assignment in `backend/internal/usecase/message_usecase.go`
    - Preserve original msg.Type when Link Preview is detected
    - _Bug_Condition: message contains Link Preview metadata_
    - _Expected_Behavior: msg.Type remains unchanged_
    - _Preservation: Messages without Link Preview continue to process normally_
    - _Requirements: 1.2, 2.2, 3.2_

  - [x] 2.3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Type Preserved With Link Preview
    - **IMPORTANT**: Re-run the SAME test from task 2.1 - do NOT write a new test
    - The test from task 2.1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 2.1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - _Requirements: 2.2_

  - [x] 2.3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Non-Link Messages Still Work
    - **IMPORTANT**: Re-run the SAME tests from task 2.2 - do NOT write new tests
    - Run preservation property tests from step 2.2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

- [x] 2.4 Checkpoint - Ensure all tests pass for Bug Fix 2

## Bug Fix 3: Flutter Compilation Errors (Orphaned Underscores)

- [x] 3.1 Write bug condition exploration test
  - **Property 1: Bug Condition** - Orphaned Underscore Compilation Failure
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope to files with orphaned underscore: backup_manager.dart:103, crypto_service.dart:225, chat_room_provider.dart:617, contact_info_page.dart:376-378
  - Test that Flutter compilation fails with "Undefined name '_'" error
  - The test assertions should verify compilation succeeds
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.3_

- [x] 3.2 Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Valid Code Compilation Success
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for files without syntax errors
  - Write property-based tests capturing that compilation continues to succeed for valid code
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.3_

- [ ] 3.3 Fix orphaned underscores
  - [x] 3.3.1 Implement the fix
    - Remove or replace orphaned `_` in backup_manager.dart line 103
    - Remove or replace orphaned `_` in crypto_service.dart line 225
    - Remove or replace orphaned `_` in chat_room_provider.dart line 617
    - Remove or replace orphaned `_` in contact_info_page.dart lines 376-378
    - _Bug_Condition: orphaned underscore `_` symbol exists_
    - _Expected_Behavior: all orphaned underscores removed or replaced with valid variable names_
    - _Preservation: valid code continues to compile successfully_
    - _Requirements: 1.3, 2.3, 3.3_

  - [x] 3.3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Compilation Succeeds
    - **IMPORTANT**: Re-run the SAME test from task 3.1 - do NOT write a new test
    - The test from task 3.1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 3.1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - _Requirements: 2.3_

  - [x] 3.3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Valid Code Still Compiles
    - **IMPORTANT**: Re-run the SAME tests from task 3.2 - do NOT write new tests
    - Run preservation property tests from step 3.2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

- [x] 3.4 Checkpoint - Ensure all tests pass for Bug Fix 3

## Bug Fix 4: Decryption Retry Permanent Failure

- [x] 4.1 Write bug condition exploration test
  - **Property 1: Bug Condition** - Offline Sender Permanent Failure
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope to re_encrypt_request with sender offline > 10 seconds
  - Test that message is marked as MessageStatus.failed when sender offline > 10 seconds after re_encrypt_request
  - The test assertions should verify message remains in MessageStatus.decryptingRetry state
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.4_

- [x] 4.2 Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Successful Decryption Status
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for successful decryption cases
  - Write property-based tests capturing that messages continue to display as MessageStatus.sent or correct status when decryption succeeds
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.4_

- [ ] 4.3 Fix decryption retry status
  - [x] 4.3.1 Implement the fix
    - Update message status logic to keep MessageStatus.decryptingRetry when sender offline/timeout
    - Display "🔒 等待對方上線以重新解密..." instead of marking as permanent failure
    - Remove 10-second timeout logic that marks message as failed
    - _Bug_Condition: re_encrypt_request sent AND sender offline > 10 seconds_
    - _Expected_Behavior: message remains in MessageStatus.decryptingRetry state_
    - _Preservation: successful decryption continues to show correct status_
    - _Requirements: 1.4, 2.4, 3.4_

  - [x] 4.3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Retry State Maintained
    - **IMPORTANT**: Re-run the SAME test from task 4.1 - do NOT write a new test
    - The test from task 4.1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 4.1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - _Requirements: 2.4_

  - [x] 4.3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Successful Decryption Still Works
    - **IMPORTANT**: Re-run the SAME tests from task 4.2 - do NOT write new tests
    - Run preservation property tests from step 4.2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

- [x] 4.4 Checkpoint - Ensure all tests pass for Bug Fix 4

## Bug Fix 5: BuildContext Usage After Async

- [x] 5.1 Write bug condition exploration test
  - **Property 1: Bug Condition** - Unmounted Context Access Crash
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope to BuildContext usage after await in contact_info_page.dart, notification_service.dart, qr_scanner_page.dart
  - Test that accessing BuildContext after await causes crash when widget is unmounted
  - The test assertions should verify context.mounted check prevents crash
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.5_

- [x] 5.2 Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Synchronous Context Usage
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for synchronous BuildContext usage
  - Write property-based tests capturing that synchronous context usage continues to work normally
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.5_

- [ ] 5.3 Fix BuildContext usage after async
  - [x] 5.3.1 Implement the fix
    - Add `if (!context.mounted) return;` check in contact_info_page.dart before context usage after await
    - Add `if (!context.mounted) return;` check in notification_service.dart before context usage after await
    - Add `if (!context.mounted) return;` check in qr_scanner_page.dart before context usage after await
    - _Bug_Condition: BuildContext used after await AND widget unmounted_
    - _Expected_Behavior: context.mounted check prevents crash_
    - _Preservation: synchronous context usage continues to work normally_
    - _Requirements: 1.5, 2.5, 3.5_

  - [x] 5.3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Mounted Check Prevents Crash
    - **IMPORTANT**: Re-run the SAME test from task 5.1 - do NOT write a new test
    - The test from task 5.1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 5.1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - _Requirements: 2.5_

  - [x] 5.3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Sync Context Still Works
    - **IMPORTANT**: Re-run the SAME tests from task 5.2 - do NOT write new tests
    - Run preservation property tests from step 5.2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

- [x] 5.4 Checkpoint - Ensure all tests pass for Bug Fix 5

## Bug Fix 6: Deprecated API Warnings

- [x] 6.1 Write bug condition exploration test
  - **Property 1: Bug Condition** - Deprecated API Warnings
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope to Color.withOpacity() usage and unnecessary foundation.dart imports
  - Test that compilation produces deprecation warnings for Color.withOpacity() and unnecessary imports
  - The test assertions should verify no deprecation warnings are produced
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.6_

- [x] 6.2 Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Modern API Compilation
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for modern API usage
  - Write property-based tests capturing that modern API code continues to compile without warnings
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.6_

- [ ] 6.3 Fix deprecated API usage
  - [x] 6.3.1 Implement the fix
    - Replace Color.withOpacity() with .withValues(alpha: ...) throughout codebase
    - Remove unnecessary `import 'package:flutter/foundation.dart'` statements
    - _Bug_Condition: Color.withOpacity() used OR unnecessary foundation.dart import exists_
    - _Expected_Behavior: .withValues(alpha: ...) used AND no unnecessary imports_
    - _Preservation: modern API code continues to compile without warnings_
    - _Requirements: 1.6, 2.6, 3.6_

  - [x] 6.3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - No Deprecation Warnings
    - **IMPORTANT**: Re-run the SAME test from task 6.1 - do NOT write a new test
    - The test from task 6.1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 6.1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - _Requirements: 2.6_

  - [x] 6.3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Modern API Still Works
    - **IMPORTANT**: Re-run the SAME tests from task 6.2 - do NOT write new tests
    - Run preservation property tests from step 6.2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

- [x] 6.4 Checkpoint - Ensure all tests pass for Bug Fix 6

## Final Checkpoint

- [x] 7. Final verification - Ensure all 6 bug fixes are complete and all tests pass
  - Verify all exploration tests now pass (bugs are fixed)
  - Verify all preservation tests still pass (no regressions)
  - Ask user if any questions arise
