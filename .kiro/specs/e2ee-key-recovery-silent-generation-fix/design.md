# E2EE Key Recovery Silent Generation Fix - Bugfix Design

## Overview

本 bugfix 修復 CryptoService 在偵測不到本地私鑰時自動靜默生成新金鑰的問題。修復後，當私鑰遺失時（例如 iOS 模擬器重啟、更換裝置、重新安裝應用），系統將拋出 `PrivateKeyNotFoundException` 例外，並在 UI 層攔截此例外，顯示金鑰還原對話框，讓用戶選擇「從雲端還原金鑰」或「強制生成新金鑰」。

修復策略包含三個核心變更：
1. CryptoService 新增 `PrivateKeyNotFoundException` 例外和 `forceGenerate` 參數
2. AuthViewModel 攔截例外並觸發 UI 流程
3. 新增 KeyRecoveryDialog UI 元件，整合現有的 `encryptPrivateKeyForBackup` 和 `decryptPrivateKeyFromBackup` 方法

## Glossary

- **Bug_Condition (C)**: 當 `CryptoService.initialize(userId)` 被呼叫且本地 SecureStorage 中找不到該用戶的私鑰時觸發
- **Property (P)**: 系統應拋出 `PrivateKeyNotFoundException` 例外，而非靜默生成新金鑰
- **Preservation**: 當本地私鑰存在時，系統應繼續正常載入金鑰並完成初始化，不受此修復影響
- **CryptoService**: 位於 `app/lib/core/crypto/crypto_service.dart` 的加密服務，負責管理 E2EE 金鑰對
- **AuthViewModel**: 位於 `app/lib/features/auth/providers/auth_provider.dart` 的登入狀態管理器，負責協調登入流程
- **SecureStorage**: Flutter Secure Storage，用於安全儲存私鑰的本地儲存機制
- **forceGenerate**: 新增的布林參數，當設為 `true` 時允許 CryptoService 在私鑰不存在時生成新金鑰

## Bug Details

### Bug Condition

當用戶登入時，`AuthViewModel.login()` 會呼叫 `crypto.initialize(userId: userId)`。若 SecureStorage 中找不到該用戶的私鑰（`storedPrivateKeyBase64 == null`），`initialize` 方法會自動生成新的金鑰對並寫入 Storage，不通知用戶也不提供還原選項。

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type InitializeRequest { userId: String }
  OUTPUT: boolean
  
  storageKey := "e2ee_private_key_" + input.userId
  storedPrivateKeyBase64 := SecureStorage.read(storageKey)
  
  RETURN storedPrivateKeyBase64 == null
         AND NOT forceGenerateFlag
         AND systemGeneratesNewKeyPairSilently
END FUNCTION
```

### Examples

- **iOS 模擬器重啟**: 用戶在 iOS 模擬器上登入應用，重啟模擬器後 Keychain 資料遺失，再次登入時系統靜默生成新金鑰，所有歷史訊息無法解密
- **更換裝置**: 用戶從 iPhone A 換到 iPhone B，在 iPhone B 上登入時系統靜默生成新金鑰，即使用戶擁有備份密碼也無法還原舊金鑰
- **重新安裝應用**: 用戶刪除應用後重新安裝，登入時系統靜默生成新金鑰，歷史訊息永久無法解密
- **Edge Case - 正常登入**: 用戶正常登入且本地私鑰存在，系統應正常載入金鑰，不顯示還原 UI（預期行為，不受此 bugfix 影響）

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- 當本地 SecureStorage 中存在有效的私鑰時，系統必須繼續正常載入金鑰並完成初始化
- 現有的 `encryptPrivateKeyForBackup` 和 `decryptPrivateKeyFromBackup` 方法邏輯必須保持不變
- 用戶發送或接收加密訊息的 E2EE 流程必須保持不變
- 應用在其他平台（Android、Web）的金鑰管理行為必須保持一致

**Scope:**
所有不涉及「私鑰遺失」情境的輸入應完全不受此修復影響。這包括：
- 正常登入流程（本地私鑰存在）
- 加密/解密訊息流程
- 金鑰備份流程（設定備份密碼）
- 登出流程

## Hypothesized Root Cause

基於 bugfix requirements 和程式碼分析，最可能的根本原因是：

1. **缺少例外機制**: `CryptoService.initialize()` 方法在偵測到 `storedPrivateKeyBase64 == null` 時，直接執行「生成新 keypair」邏輯，沒有拋出例外或提供選項讓上層決定如何處理

2. **缺少 forceGenerate 參數**: 目前 `initialize()` 方法沒有參數可以控制「是否允許自動生成新金鑰」，導致無法區分「首次初始化」和「金鑰遺失需要還原」兩種情境

3. **缺少 UI 攔截點**: `AuthViewModel.login()` 直接呼叫 `crypto.initialize(userId: userId)` 且沒有 try-catch 處理，無法攔截金鑰遺失的情況並顯示還原 UI

4. **缺少金鑰還原 UI**: 雖然 CryptoService 已實作 `decryptPrivateKeyFromBackup` 和 `restorePrivateKey` 方法，但沒有對應的 UI 元件讓用戶輸入備份密碼並觸發還原流程

## Correctness Properties

Property 1: Bug Condition - Throw Exception on Missing Private Key

_For any_ initialize request where the user's private key does not exist in SecureStorage and forceGenerate is false, the fixed CryptoService.initialize() function SHALL throw a PrivateKeyNotFoundException instead of silently generating a new keypair.

**Validates: Requirements 2.1**

Property 2: Preservation - Normal Initialization with Existing Key

_For any_ initialize request where the user's private key exists in SecureStorage, the fixed CryptoService.initialize() function SHALL produce exactly the same behavior as the original function, loading the existing keypair and completing initialization without throwing exceptions.

**Validates: Requirements 3.1, 3.2**

## Fix Implementation

### Changes Required

假設我們的根本原因分析正確，需要進行以下變更：

**File 1**: `app/lib/core/crypto/crypto_service.dart`

**Changes**:
1. **新增 PrivateKeyNotFoundException 例外類別**:
   - 在檔案頂部新增例外類別定義
   - 包含 `userId` 屬性以便上層識別是哪個用戶的金鑰遺失

2. **修改 initialize 方法簽名**:
   - 新增 `bool forceGenerate = false` 參數
   - 當 `storedPrivateKeyBase64 == null` 且 `forceGenerate == false` 時，拋出 `PrivateKeyNotFoundException`
   - 當 `storedPrivateKeyBase64 == null` 且 `forceGenerate == true` 時，執行原有的生成新金鑰邏輯

3. **保留現有方法**:
   - `encryptPrivateKeyForBackup` 保持不變
   - `decryptPrivateKeyFromBackup` 保持不變
   - `restorePrivateKey` 保持不變

**File 2**: `app/lib/features/auth/providers/auth_provider.dart`

**Function**: `login()`

**Specific Changes**:
1. **新增 try-catch 區塊**:
   - 在 `crypto.initialize(userId: userId)` 外層包裹 try-catch
   - 捕捉 `PrivateKeyNotFoundException` 例外

2. **新增狀態欄位**:
   - 在 `AuthState` 中新增 `bool needsKeyRecovery` 和 `String? missingKeyUserId` 欄位
   - 當捕捉到 `PrivateKeyNotFoundException` 時，設定 `needsKeyRecovery = true` 和 `missingKeyUserId = userId`

3. **新增金鑰還原方法**:
   - `Future<void> recoverKeyFromBackup(String password)`: 呼叫後端 API 取得加密的私鑰，使用 `decryptPrivateKeyFromBackup` 解密，然後呼叫 `restorePrivateKey`
   - `Future<void> forceGenerateNewKey()`: 呼叫 `crypto.initialize(userId: userId, forceGenerate: true)`

**File 3**: `app/lib/features/auth/widgets/key_recovery_dialog.dart` (新檔案)

**Specific Changes**:
1. **建立 KeyRecoveryDialog StatefulWidget**:
   - 顯示標題「偵測到金鑰遺失」
   - 顯示說明文字「您的加密金鑰在本地裝置上找不到。您可以使用備份密碼還原金鑰，或強制生成新金鑰（將無法解密歷史訊息）。」

2. **新增 UI 元件**:
   - TextField: 輸入備份密碼（密碼欄位，帶眼睛圖示切換顯示/隱藏）
   - Button: 「從雲端還原金鑰」（主要按鈕，呼叫 `authViewModel.recoverKeyFromBackup(password)`）
   - TextButton: 「強制生成新金鑰」（次要按鈕，顯示確認對話框後呼叫 `authViewModel.forceGenerateNewKey()`）
   - 錯誤訊息顯示區域（當密碼錯誤時顯示紅色文字）

3. **整合 AuthViewModel**:
   - 使用 `ref.watch(authViewModelProvider)` 監聽狀態
   - 當 `state.isLoading` 為 true 時顯示 loading indicator
   - 當還原成功時自動關閉對話框並繼續登入流程

**File 4**: `app/lib/features/auth/views/login_view.dart`

**Specific Changes**:
1. **監聽 needsKeyRecovery 狀態**:
   - 在 `build()` 方法中使用 `ref.listen` 監聽 `authViewModelProvider`
   - 當 `state.needsKeyRecovery == true` 時，顯示 `KeyRecoveryDialog`

2. **對話框顯示邏輯**:
   - 使用 `showDialog()` 顯示 `KeyRecoveryDialog`
   - 設定 `barrierDismissible: false` 防止用戶點擊外部關閉對話框

## Testing Strategy

### Validation Approach

測試策略採用兩階段方法：首先在未修復的程式碼上執行探索性測試，觀察靜默生成金鑰的錯誤行為；然後在修復後的程式碼上執行修復驗證測試和保留性測試，確保 bug 已修復且現有功能未受影響。

### Exploratory Bug Condition Checking

**Goal**: 在實作修復前，先在未修復的程式碼上執行測試，觀察靜默生成金鑰的錯誤行為，確認或反駁根本原因分析。如果反駁，需要重新假設根本原因。

**Test Plan**: 撰寫測試模擬「私鑰不存在」的情境，呼叫 `CryptoService.initialize(userId: 'test_user')`，並斷言系統會自動生成新金鑰而非拋出例外。在未修復的程式碼上執行此測試，預期會通過（證明 bug 存在）。

**Test Cases**:
1. **iOS 模擬器重啟測試**: 清空 SecureStorage，呼叫 `initialize(userId: 'user1')`，觀察是否靜默生成新金鑰（未修復程式碼上會通過）
2. **更換裝置測試**: 模擬新裝置環境（空的 SecureStorage），呼叫 `initialize(userId: 'user2')`，觀察是否靜默生成新金鑰（未修復程式碼上會通過）
3. **重新安裝應用測試**: 清空所有本地資料，呼叫 `initialize(userId: 'user3')`，觀察是否靜默生成新金鑰（未修復程式碼上會通過）
4. **Edge Case - 正常登入測試**: 預先寫入私鑰到 SecureStorage，呼叫 `initialize(userId: 'user4')`，觀察是否正常載入金鑰（未修復程式碼上會通過，且修復後也應通過）

**Expected Counterexamples**:
- 當 SecureStorage 中沒有私鑰時，`initialize()` 會自動生成新金鑰並返回公鑰，而非拋出例外
- 可能原因：缺少例外機制、缺少 forceGenerate 參數、缺少 UI 攔截點

### Fix Checking

**Goal**: 驗證對於所有符合 bug condition 的輸入（私鑰不存在且 forceGenerate 為 false），修復後的函數會產生預期行為（拋出 PrivateKeyNotFoundException）。

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := CryptoService_fixed.initialize(userId: input.userId, forceGenerate: false)
  ASSERT result throws PrivateKeyNotFoundException
  ASSERT exception.userId == input.userId
END FOR
```

### Preservation Checking

**Goal**: 驗證對於所有不符合 bug condition 的輸入（私鑰存在），修復後的函數會產生與原始函數相同的結果。

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT CryptoService_original.initialize(input) == CryptoService_fixed.initialize(input)
END FOR
```

**Testing Approach**: 建議使用 Property-Based Testing 進行保留性檢查，因為：
- 它會自動生成大量測試案例，涵蓋整個輸入域
- 它能捕捉手動單元測試可能遺漏的邊界情況
- 它提供強有力的保證，確保所有非 buggy 輸入的行為保持不變

**Test Plan**: 先在未修復的程式碼上觀察「私鑰存在」情境的行為，然後撰寫 property-based tests 捕捉該行為，確保修復後行為一致。

**Test Cases**:
1. **正常初始化保留測試**: 觀察未修復程式碼在私鑰存在時的行為，撰寫測試驗證修復後繼續正常載入金鑰
2. **加密/解密保留測試**: 觀察未修復程式碼的加密/解密流程，撰寫測試驗證修復後加密/解密功能不受影響
3. **備份方法保留測試**: 觀察未修復程式碼的 `encryptPrivateKeyForBackup` 和 `decryptPrivateKeyFromBackup` 行為，撰寫測試驗證修復後這些方法保持不變
4. **多用戶隔離保留測試**: 觀察未修復程式碼在切換用戶時的金鑰隔離行為，撰寫測試驗證修復後用戶間金鑰隔離保持不變

### Unit Tests

- 測試 `PrivateKeyNotFoundException` 在私鑰不存在且 `forceGenerate = false` 時被正確拋出
- 測試 `initialize(userId, forceGenerate: true)` 在私鑰不存在時能成功生成新金鑰
- 測試 `initialize(userId)` 在私鑰存在時能正常載入金鑰
- 測試 `AuthViewModel.recoverKeyFromBackup()` 能正確呼叫 API、解密金鑰並還原
- 測試 `AuthViewModel.forceGenerateNewKey()` 能正確呼叫 `initialize(forceGenerate: true)`
- 測試 `KeyRecoveryDialog` 在輸入錯誤密碼時顯示錯誤訊息
- 測試 `KeyRecoveryDialog` 在還原成功後自動關閉

### Property-Based Tests

- 生成隨機的 userId，驗證當私鑰不存在且 `forceGenerate = false` 時，`initialize()` 總是拋出 `PrivateKeyNotFoundException`
- 生成隨機的 userId 和私鑰，驗證當私鑰存在時，`initialize()` 總是成功載入金鑰且不拋出例外
- 生成隨機的備份密碼和私鑰，驗證 `encryptPrivateKeyForBackup` 和 `decryptPrivateKeyFromBackup` 的往返加密/解密總是成功
- 生成隨機的用戶切換序列，驗證金鑰隔離機制在修復後保持不變

### Integration Tests

- 測試完整的金鑰還原流程：清空 SecureStorage → 登入 → 顯示 KeyRecoveryDialog → 輸入備份密碼 → 還原成功 → 進入聊天列表
- 測試完整的強制生成流程：清空 SecureStorage → 登入 → 顯示 KeyRecoveryDialog → 點擊「強制生成新金鑰」→ 確認警告 → 生成成功 → 進入聊天列表
- 測試正常登入流程不受影響：保留私鑰 → 登入 → 直接進入聊天列表（不顯示 KeyRecoveryDialog）
- 測試錯誤密碼處理：清空 SecureStorage → 登入 → 顯示 KeyRecoveryDialog → 輸入錯誤密碼 → 顯示錯誤訊息 → 重試成功
