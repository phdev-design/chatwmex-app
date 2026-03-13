# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Silent Key Generation on Missing Private Key
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists (silent key generation instead of throwing exception)
  - **Scoped PBT Approach**: Scope the property to concrete failing cases: userId with empty SecureStorage
  - Test that `CryptoService.initialize(userId: 'test_user')` silently generates new keypair when private key is missing (from Bug Condition in design)
  - The test assertions should match the Expected Behavior Properties from design: system should throw `PrivateKeyNotFoundException` instead of generating keys
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists: system generates keys silently instead of throwing exception)
  - Document counterexamples found:
    - iOS 模擬器重啟: 清空 SecureStorage，呼叫 `initialize(userId: 'user1')`，觀察是否靜默生成新金鑰
    - 更換裝置: 模擬新裝置環境（空的 SecureStorage），呼叫 `initialize(userId: 'user2')`，觀察是否靜默生成新金鑰
    - 重新安裝應用: 清空所有本地資料，呼叫 `initialize(userId: 'user3')`，觀察是否靜默生成新金鑰
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 2.1_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Normal Initialization with Existing Key
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs (when private key exists in SecureStorage)
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements:
    - 正常初始化: 當本地 SecureStorage 中存在有效的私鑰時，系統正常載入金鑰並完成初始化
    - 加密/解密流程: 用戶發送或接收加密訊息的 E2EE 流程保持不變
    - 備份方法: `encryptPrivateKeyForBackup` 和 `decryptPrivateKeyFromBackup` 方法邏輯保持不變
    - 多用戶隔離: 切換用戶時的金鑰隔離行為保持不變
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2_

- [x] 3. Fix for E2EE key recovery silent generation

  - [x] 3.1 Implement CryptoService changes
    - 在 `app/lib/core/crypto/crypto_service.dart` 檔案頂部新增 `PrivateKeyNotFoundException` 例外類別，包含 `userId` 屬性
    - 修改 `initialize` 方法簽名，新增 `bool forceGenerate = false` 參數
    - 當 `storedPrivateKeyBase64 == null` 且 `forceGenerate == false` 時，拋出 `PrivateKeyNotFoundException`
    - 當 `storedPrivateKeyBase64 == null` 且 `forceGenerate == true` 時，執行原有的生成新金鑰邏輯
    - 保留現有方法不變：`encryptPrivateKeyForBackup`、`decryptPrivateKeyFromBackup`、`restorePrivateKey`
    - _Bug_Condition: isBugCondition(input) where storedPrivateKeyBase64 == null AND NOT forceGenerateFlag_
    - _Expected_Behavior: System throws PrivateKeyNotFoundException instead of silently generating new keypair_
    - _Preservation: When private key exists in SecureStorage, system continues normal initialization_
    - _Requirements: 2.1, 3.1, 3.2_

  - [x] 3.2 Implement AuthViewModel changes
    - 在 `app/lib/features/auth/providers/auth_provider.dart` 的 `login()` 方法中，在 `crypto.initialize(userId: userId)` 外層包裹 try-catch 區塊
    - 捕捉 `PrivateKeyNotFoundException` 例外
    - 在 `AuthState` 中新增 `bool needsKeyRecovery` 和 `String? missingKeyUserId` 欄位
    - 當捕捉到 `PrivateKeyNotFoundException` 時，設定 `needsKeyRecovery = true` 和 `missingKeyUserId = userId`
    - 新增 `Future<void> recoverKeyFromBackup(String password)` 方法：呼叫後端 API 取得加密的私鑰，使用 `decryptPrivateKeyFromBackup` 解密，然後呼叫 `restorePrivateKey`
    - 新增 `Future<void> forceGenerateNewKey()` 方法：呼叫 `crypto.initialize(userId: userId, forceGenerate: true)`
    - _Bug_Condition: Exception thrown when private key is missing_
    - _Expected_Behavior: AuthViewModel intercepts exception and triggers UI flow_
    - _Preservation: Normal login flow with existing key remains unchanged_
    - _Requirements: 2.1, 3.1, 3.2_

  - [x] 3.3 Create KeyRecoveryDialog UI component
    - 建立新檔案 `app/lib/features/auth/widgets/key_recovery_dialog.dart`
    - 建立 `KeyRecoveryDialog` StatefulWidget
    - 顯示標題「偵測到金鑰遺失」
    - 顯示說明文字「您的加密金鑰在本地裝置上找不到。您可以使用備份密碼還原金鑰，或強制生成新金鑰（將無法解密歷史訊息）。」
    - 新增 TextField 輸入備份密碼（密碼欄位，帶眼睛圖示切換顯示/隱藏）
    - 新增 Button「從雲端還原金鑰」（主要按鈕，呼叫 `authViewModel.recoverKeyFromBackup(password)`）
    - 新增 TextButton「強制生成新金鑰」（次要按鈕，顯示確認對話框後呼叫 `authViewModel.forceGenerateNewKey()`）
    - 新增錯誤訊息顯示區域（當密碼錯誤時顯示紅色文字）
    - 使用 `ref.watch(authViewModelProvider)` 監聽狀態
    - 當 `state.isLoading` 為 true 時顯示 loading indicator
    - 當還原成功時自動關閉對話框並繼續登入流程
    - _Expected_Behavior: UI provides recovery and force generation options_
    - _Preservation: Existing auth UI flows remain unchanged_
    - _Requirements: 2.1_

  - [x] 3.4 Integrate KeyRecoveryDialog into LoginView
    - 在 `app/lib/features/auth/views/login_view.dart` 的 `build()` 方法中使用 `ref.listen` 監聽 `authViewModelProvider`
    - 當 `state.needsKeyRecovery == true` 時，使用 `showDialog()` 顯示 `KeyRecoveryDialog`
    - 設定 `barrierDismissible: false` 防止用戶點擊外部關閉對話框
    - _Expected_Behavior: Dialog appears when private key is missing_
    - _Preservation: Normal login flow without key issues remains unchanged_
    - _Requirements: 2.1_

  - [x] 3.5 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Throw Exception on Missing Private Key
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed: system now throws PrivateKeyNotFoundException instead of silently generating keys)
    - _Requirements: Expected Behavior Properties from design - Property 1_

  - [x] 3.6 Verify preservation tests still pass
    - **Property 2: Preservation** - Normal Initialization with Existing Key
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions in normal initialization, encryption/decryption, backup methods, multi-user isolation)

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
