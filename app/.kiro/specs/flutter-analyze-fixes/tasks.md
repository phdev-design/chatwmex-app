# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Flutter Analyze 錯誤存在驗證
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bugs exist
  - **Scoped PBT Approach**: Scope the property to concrete failing cases identified by flutter analyze
  - Test that `flutter analyze` reports "Undefined name '_'" errors at lines 103, 225, 378, 617
  - Test that `flutter analyze` reports "use_build_context_synchronously" warnings in notification_service.dart, qr_scanner_page.dart, contact_info_page.dart
  - Test that `flutter analyze` reports "unnecessary_import" warnings for foundation.dart imports
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bugs exist)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - 業務邏輯和功能不變
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for all application features
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Test backup functionality (backup_manager.dart)
  - Test encryption/decryption functionality (crypto_service.dart)
  - Test chat room message handling (chat_room_provider.dart)
  - Test contact info page display and interaction (contact_info_page.dart)
  - Test notification navigation (notification_service.dart)
  - Test QR scanner authorization flow (qr_scanner_page.dart)
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 3. Fix Flutter Analyze 錯誤

  - [x] 3.1 階段 1：修復編譯錯誤（Undefined name '_'）
    - Fix lib/core/backup/backup_manager.dart line 103: 修正正則表達式字串，確保字串正確閉合
    - Fix lib/core/crypto/crypto_service.dart line 225: 調整 catch 區塊註解位置，將註解移到區塊內部
    - Fix lib/features/chat/ui/contact_info_page.dart line 378: 檢查並修復語法錯誤
    - Fix lib/features/chat/providers/chat_room_provider.dart line 617: 檢查並修復語法錯誤
    - _Bug_Condition: isBugCondition(input) where input.errorType == "Undefined name '_'" AND input.line IN [103, 225, 378, 617]_
    - _Expected_Behavior: flutter analyze 不報告任何 "Undefined name '_'" 錯誤_
    - _Preservation: 所有業務邏輯、UI 顯示、使用者互動必須完全不變_
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 2.3, 2.4, 3.1, 3.4, 3.5_

  - [x] 3.2 階段 2：修復 BuildContext 非同步使用警告
    - Fix lib/core/notification/notification_service.dart: 調整 mounted 檢查位置，確保在每次使用 context 前都有檢查
    - Fix lib/features/auth/ui/qr_scanner_page.dart: 確認 mounted 檢查正確，確保每個 await 後都有對應檢查
    - Fix lib/features/chat/ui/contact_info_page.dart: 修正 mounted 檢查，使用 context.mounted 而非 mounted
    - _Bug_Condition: isBugCondition(input) where input.errorType == "use_build_context_synchronously"_
    - _Expected_Behavior: flutter analyze 不報告任何 "use_build_context_synchronously" 警告_
    - _Preservation: 所有導航、UI 互動、通知處理功能必須完全不變_
    - _Requirements: 1.5, 1.6, 2.5, 2.6, 3.2, 3.4, 3.5_

  - [x] 3.3 階段 3：移除無用的 import
    - Remove unnecessary foundation.dart imports from files that already import material.dart
    - Check lib/core/notification/notification_service.dart
    - Check lib/features/chat/ui/backup_conversations_page.dart
    - Check other files reported by flutter analyze
    - Preserve foundation.dart import if file uses specific features not available in material.dart
    - _Bug_Condition: isBugCondition(input) where input.errorType == "unnecessary_import" AND input.importPath == 'package:flutter/foundation.dart'_
    - _Expected_Behavior: flutter analyze 不報告任何 "unnecessary_import" 警告_
    - _Preservation: 所有功能必須完全不變，確保沒有因移除 import 導致的編譯錯誤_
    - _Requirements: 1.7, 2.7, 3.3_

  - [x] 3.4 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Flutter Analyze 無錯誤
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bugs are fixed)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [x] 3.5 Verify preservation tests still pass
    - **Property 2: Preservation** - 業務邏輯和功能不變
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 4. Checkpoint - Ensure all tests pass
  - Run `flutter analyze` and verify no errors or warnings
  - Run all existing unit tests and verify they pass
  - Manually test key features: backup, encryption, chat rooms, notifications, QR scanner
  - Ensure all tests pass, ask the user if questions arise
