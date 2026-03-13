# E2EE WebSocket Stability Fixes 設計文件

## Overview

本設計文件針對聊天應用程式中的 6 個關鍵穩定性問題提供修復方案。這些問題涵蓋：

1. WebSocket 訊息大小限制導致群組訊息連線中斷
2. Link Preview 類型強制覆寫導致前端解析崩潰
3. Flutter 編譯錯誤（孤立底線符號）
4. E2EE 解密失敗後的不良狀態管理
5. Flutter 非同步操作後的 BuildContext 使用風險
6. Flutter 廢棄 API 警告

修復策略採用最小化變更原則，確保現有功能不受影響，同時提升系統穩定性和使用者體驗。

## Glossary

- **Bug_Condition (C)**: 觸發錯誤的條件集合
- **Property (P)**: 修復後應具備的正確行為
- **Preservation**: 必須保持不變的現有行為
- **Fan-out E2EE**: 群組訊息加密機制，為每個成員單獨產生密文
- **maxMessageSize**: WebSocket 連線允許的最大訊息大小（位元組）
- **MessageStatus**: 訊息狀態列舉（sent, failed, decryptingRetry 等）
- **BuildContext**: Flutter widget 的上下文物件，在 widget 卸載後不可使用
- **context.mounted**: Flutter 3.x 新增的屬性，檢查 widget 是否仍掛載

## Bug Details

### Bug Condition 1: WebSocket 訊息大小限制

群組訊息使用 Fan-out E2EE 時，為每個成員產生獨立密文。當群組成員數量較多或訊息內容較長時，JSON Payload 可能超過 8KB。

**Formal Specification:**
```
FUNCTION isBugCondition1(message)
  INPUT: message of type WebSocketMessage
  OUTPUT: boolean
  
  RETURN message.isGroupMessage == true
         AND message.payloadSize > 8192
         AND message.payloadSize <= 1048576
END FUNCTION
```

**Examples:**
- 10 人群組發送包含 Link Preview 的訊息，每個成員密文約 1KB，總 Payload 約 10KB → 連線中斷
- 5 人群組發送長文字訊息（2000 字），總 Payload 約 12KB → 連線中斷
- 單人對話發送 5KB 訊息 → 正常運作（不觸發 bug）

### Bug Condition 2: Link Preview 類型強制覆寫

後端在 `message_usecase.go` 的 `SendMessage` 函數中，當偵測到 `msg.LinkPreview != nil` 時，強制設定 `msg.Type = "link"`。但 Flutter 前端的 `MessageType` 列舉不包含 `"link"` 值。

**Formal Specification:**
```
FUNCTION isBugCondition2(message)
  INPUT: message of type domain.Message
  OUTPUT: boolean
  
  RETURN message.LinkPreview != nil
         AND message.LinkPreview.URL != ""
         AND backend.forcesTypeOverwrite == true
END FUNCTION
```

**Examples:**
- 使用者發送包含 YouTube 連結的文字訊息 → 後端設定 `Type = "link"` → 前端解析時拋出 `StateError`
- 使用者發送包含新聞網站連結的訊息 → 後端設定 `Type = "link"` → 前端崩潰
- 使用者發送純文字訊息（無連結）→ 正常運作（不觸發 bug）

### Bug Condition 3: Flutter 編譯錯誤（孤立底線）

Flutter 3.x 不允許孤立的底線 `_` 符號作為獨立表達式。受影響的檔案包含未使用的變數或參數標記為 `_`。

**Formal Specification:**
```
FUNCTION isBugCondition3(codeFile)
  INPUT: codeFile of type DartSourceFile
  OUTPUT: boolean
  
  RETURN codeFile.containsIsolatedUnderscore == true
         AND compiler.version >= "3.0.0"
END FUNCTION
```

**Examples:**
- `backup_manager.dart` line 103: `_; // ignore unused variable` → 編譯失敗
- `crypto_service.dart` line 225: 孤立 `_` → 編譯失敗
- `chat_room_provider.dart` line 617: 孤立 `_` → 編譯失敗
- `contact_info_page.dart` lines 376-378: 孤立 `_` → 編譯失敗

### Bug Condition 4: E2EE 解密失敗狀態管理

當前端解密失敗並發送 `re_encrypt_request` 時，若發送方離線超過 10 秒，訊息被標記為 `MessageStatus.failed` 永久失敗狀態，無法恢復。

**Formal Specification:**
```
FUNCTION isBugCondition4(message, sender)
  INPUT: message of type Message, sender of type User
  OUTPUT: boolean
  
  RETURN message.decryptionFailed == true
         AND message.reEncryptRequestSent == true
         AND sender.isOffline == true
         AND timeSinceRequest > 10 seconds
END FUNCTION
```

**Examples:**
- 接收者解密失敗，發送 re_encrypt_request，發送方離線 15 秒 → 訊息標記為永久失敗
- 接收者解密失敗，發送 re_encrypt_request，發送方離線 5 秒後上線 → 可能正常重新加密（不穩定）
- 接收者解密成功 → 正常顯示（不觸發 bug）

### Bug Condition 5: BuildContext 非同步使用風險

Flutter UI 元件在 `await` 非同步操作後使用 `BuildContext`，若 widget 已卸載，會導致崩潰或未定義行為。

**Formal Specification:**
```
FUNCTION isBugCondition5(codeBlock)
  INPUT: codeBlock of type DartAsyncFunction
  OUTPUT: boolean
  
  RETURN codeBlock.containsAwait == true
         AND codeBlock.usesContextAfterAwait == true
         AND codeBlock.hasMountedCheck == false
END FUNCTION
```

**Examples:**
- `contact_info_page.dart`: `await` 後使用 `Navigator.of(context)` 且無 `mounted` 檢查 → 潛在崩潰
- `notification_service.dart`: `await` 後使用 `context` 且無檢查 → 潛在崩潰
- `qr_scanner_page.dart`: `await` 後使用 `context` 且無檢查 → 潛在崩潰

### Bug Condition 6: Flutter 廢棄 API 使用

程式碼使用 `Color.withOpacity()` 和不必要的 `import 'package:flutter/foundation.dart'`，產生編譯警告。

**Formal Specification:**
```
FUNCTION isBugCondition6(codeFile)
  INPUT: codeFile of type DartSourceFile
  OUTPUT: boolean
  
  RETURN codeFile.usesDeprecatedAPI == true
         OR codeFile.hasUnnecessaryImport == true
END FUNCTION
```

**Examples:**
- 使用 `Colors.black.withOpacity(0.5)` → 產生廢棄警告
- 引入 `package:flutter/foundation.dart` 但未使用 → 產生多餘引入警告

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- 群組訊息 Payload 小於 1MB 時，WebSocket 連線正常傳輸
- 訊息不包含 Link Preview 時，後端正常處理訊息類型
- Flutter 程式碼不包含語法錯誤時，編譯成功完成
- 前端解密成功時，訊息正常顯示為 `MessageStatus.sent` 或其他正確狀態
- Flutter UI 元件在同步操作中使用 `BuildContext` 時，程式碼正常運作
- Flutter 程式碼使用現代 API 時，編譯不產生廢棄警告

**Scope:**
所有不涉及以下條件的輸入應完全不受影響：
- 群組訊息 Payload 超過 8KB 但小於 1MB
- 包含 Link Preview 的訊息類型處理
- 包含孤立底線符號的 Dart 程式碼
- E2EE 解密失敗且發送方離線的情況
- 非同步操作後使用 BuildContext 的情況
- 使用廢棄 API 的程式碼

## Hypothesized Root Cause

基於 bug 描述和程式碼分析，最可能的原因包括：

### 1. WebSocket 訊息大小限制過小
- `backend/internal/delivery/websocket/client.go` 的 `maxMessageSize` 設定為 8192 (8KB)
- 群組訊息使用 Fan-out E2EE 時，每個成員的密文獨立儲存在 JSON 中
- 當群組成員數量增加或訊息內容較長時，總 Payload 容易超過 8KB
- 註解提到「Increased to 8KB to accommodate link preview data」，但未考慮群組訊息的放大效應

### 2. 後端強制覆寫訊息類型
- `backend/internal/usecase/message_usecase.go` line 120-124 強制設定 `msg.Type = "link"`
- 前端 Flutter 的 `MessageType` 列舉不包含 `"link"` 值
- 前端在 `Message.fromJson()` 解析時，遇到未知的列舉值會拋出 `StateError`

### 3. Flutter 3.x 編譯器規則變更
- Flutter 3.x 不允許孤立的底線 `_` 作為獨立表達式
- 舊版程式碼使用 `_` 來標記未使用的變數或忽略返回值
- 編譯器現在要求明確的變數名稱或使用 `// ignore: unused_local_variable` 註解

### 4. E2EE 解密失敗的超時邏輯過於嚴格
- 當前邏輯在發送 `re_encrypt_request` 後，若發送方離線超過 10 秒，直接標記為永久失敗
- 未考慮發送方可能稍後上線的情況
- 缺乏重試機制或持久化的等待狀態

### 5. Flutter 非同步操作後缺少 mounted 檢查
- 在 `await` 非同步操作期間，使用者可能導航離開當前頁面
- Widget 卸載後，`BuildContext` 變為無效
- 若未檢查 `context.mounted`，使用 `Navigator.of(context)` 或其他 context 操作會導致崩潰

### 6. 使用廢棄的 Flutter API
- `Color.withOpacity()` 在新版 Flutter 中被標記為廢棄，建議使用 `.withValues(alpha: ...)`
- 不必要的 `import 'package:flutter/foundation.dart'` 引入未使用的套件

## Correctness Properties

Property 1: Bug Condition - WebSocket 訊息大小支援

_For any_ WebSocket 訊息，當其為群組訊息且使用 Fan-out E2EE 加密產生的 JSON Payload 大小在 8KB 到 1MB 之間時，後端 WebSocket 連線 SHALL 成功接收並處理該訊息，不中斷連線，確保群組通訊的穩定性。

**Validates: Requirements 2.1**

Property 2: Bug Condition - Link Preview 類型保持

_For any_ 訊息，當其包含 Link Preview 資料時，後端 SHALL 保持前端原始設定的 `msg.Type` 不變，不強制覆寫為 `"link"`，確保前端能正確解析訊息類型列舉。

**Validates: Requirements 2.2**

Property 3: Bug Condition - Flutter 編譯成功

_For any_ Dart 原始碼檔案，當其包含孤立的底線 `_` 符號時，SHALL 移除或替換為有效的變數名稱或註解，確保 Flutter 3.x 編譯器能成功編譯。

**Validates: Requirements 2.3**

Property 4: Bug Condition - E2EE 解密失敗狀態管理

_For any_ 訊息，當前端解密失敗並發送 `re_encrypt_request` 且發送方離線或超時時，訊息 SHALL 保持 `MessageStatus.decryptingRetry` 狀態並顯示「🔒 等待對方上線以重新解密...」，而非標記為永久失敗，確保使用者體驗和訊息可恢復性。

**Validates: Requirements 2.4**

Property 5: Bug Condition - BuildContext 安全使用

_For any_ Flutter UI 元件，當其在 `await` 非同步操作後需要使用 `BuildContext` 時，SHALL 先檢查 `if (!context.mounted) return;`，防止在 widget 已卸載時存取 context 導致崩潰。

**Validates: Requirements 2.5**

Property 6: Bug Condition - Flutter 現代 API 使用

_For any_ Flutter 程式碼，當其需要調整顏色透明度時，SHALL 使用 `.withValues(alpha: ...)` 取代 `Color.withOpacity()`，並移除不必要的 `import 'package:flutter/foundation.dart'`，確保編譯不產生廢棄警告。

**Validates: Requirements 2.6**

Property 7: Preservation - 小型訊息正常傳輸

_For any_ WebSocket 訊息，當其 Payload 小於 1MB 時，修復後的 WebSocket 連線 SHALL 產生與原始實作相同的行為，保持正常傳輸功能。

**Validates: Requirements 3.1**

Property 8: Preservation - 無 Link Preview 訊息處理

_For any_ 訊息，當其不包含 Link Preview 資料時，修復後的後端 SHALL 產生與原始實作相同的訊息類型處理行為。

**Validates: Requirements 3.2**

Property 9: Preservation - 無語法錯誤編譯

_For any_ Dart 原始碼檔案，當其不包含孤立底線符號或其他語法錯誤時，修復後的程式碼 SHALL 產生與原始實作相同的編譯結果。

**Validates: Requirements 3.3**

Property 10: Preservation - 解密成功訊息顯示

_For any_ 訊息，當前端解密成功時，修復後的程式碼 SHALL 產生與原始實作相同的訊息狀態和顯示行為。

**Validates: Requirements 3.4**

Property 11: Preservation - 同步 BuildContext 使用

_For any_ Flutter UI 元件，當其在同步操作中使用 `BuildContext` 時，修復後的程式碼 SHALL 產生與原始實作相同的行為。

**Validates: Requirements 3.5**

Property 12: Preservation - 現代 API 編譯

_For any_ Flutter 程式碼，當其使用現代 API 時，修復後的程式碼 SHALL 產生與原始實作相同的編譯結果，不產生廢棄警告。

**Validates: Requirements 3.6**

## Fix Implementation

### Changes Required

假設我們的根本原因分析正確，以下是具體的修復方案：

### Fix 1: 增加 WebSocket 訊息大小限制

**File**: `backend/internal/delivery/websocket/client.go`

**Specific Changes**:
1. **修改 maxMessageSize 常數**: 將 `maxMessageSize = 8192` 改為 `maxMessageSize = 1048576` (1MB)
   - 位置: line 20
   - 理由: 支援群組訊息的 Fan-out E2EE 加密，確保最多約 100 人的群組能正常傳送訊息
   - 計算: 假設每個成員密文約 8KB，100 人 = 800KB，加上 JSON 結構約 1MB

2. **更新註解**: 修改 line 19 的註解，說明新的限制是為了支援群組訊息
   - 原註解: `// Increased to 8KB to accommodate link preview data`
   - 新註解: `// Increased to 1MB to accommodate group messages with Fan-out E2EE encryption`

### Fix 2: 移除 Link Preview 類型強制覆寫

**File**: `backend/internal/usecase/message_usecase.go`

**Specific Changes**:
1. **移除強制類型設定**: 刪除或註解 lines 120-124 的類型覆寫邏輯
   - 原邏輯:
     ```go
     if msg.LinkPreview != nil && msg.LinkPreview.URL != "" {
         msg.Type = "link"
     } else {
         msg.LinkPreview = nil
     }
     ```
   - 新邏輯: 保持前端原始設定的 `msg.Type`，僅清除無效的 LinkPreview
     ```go
     if msg.LinkPreview != nil && msg.LinkPreview.URL == "" {
         msg.LinkPreview = nil
     }
     ```

2. **保留 LinkPreview 資料**: 確保 `msg.LinkPreview` 資料正確儲存和傳遞，不影響前端顯示

### Fix 3: 移除孤立底線符號

**Files**: 
- `app/lib/services/backup_manager.dart` (line 103)
- `app/lib/services/crypto_service.dart` (line 225)
- `app/lib/providers/chat_room_provider.dart` (line 617)
- `app/lib/pages/contact_info_page.dart` (lines 376-378)

**Specific Changes**:
1. **移除孤立底線**: 刪除所有孤立的 `_` 符號
2. **替代方案**: 
   - 若是忽略未使用的變數，使用 `// ignore: unused_local_variable` 註解
   - 若是忽略函數返回值，直接呼叫函數不賦值
   - 若是佔位符，使用有意義的變數名稱如 `unusedValue`

**Example**:
```dart
// 原程式碼 (會編譯失敗)
final result = someFunction();
_; // ignore unused variable

// 修復方案 1: 移除底線
final result = someFunction();

// 修復方案 2: 使用註解
// ignore: unused_local_variable
final result = someFunction();

// 修復方案 3: 不賦值
someFunction();
```

### Fix 4: 改善 E2EE 解密失敗狀態管理

**Files**: 需要檢查前端處理 `re_encrypt_request` 的相關檔案（可能在 `app/lib/providers/` 或 `app/lib/services/`）

**Specific Changes**:
1. **移除超時永久失敗邏輯**: 刪除將訊息標記為 `MessageStatus.failed` 的 10 秒超時邏輯
2. **保持重試狀態**: 當發送 `re_encrypt_request` 後，訊息保持 `MessageStatus.decryptingRetry` 狀態
3. **顯示等待訊息**: UI 顯示「🔒 等待對方上線以重新解密...」
4. **實作重試機制**: 當發送方上線時，自動重新嘗試解密
5. **提供手動重試**: 使用者可以手動觸發重新解密請求

**Pseudocode**:
```dart
// 原邏輯 (不良)
if (reEncryptRequestSent && senderOfflineTime > 10.seconds) {
  message.status = MessageStatus.failed;
}

// 新邏輯 (改善)
if (reEncryptRequestSent) {
  message.status = MessageStatus.decryptingRetry;
  message.statusText = "🔒 等待對方上線以重新解密...";
  // 當發送方上線時，自動重試
  onSenderOnline(() => retryDecryption(message));
}
```

### Fix 5: 新增 BuildContext mounted 檢查

**Files**:
- `app/lib/pages/contact_info_page.dart`
- `app/lib/services/notification_service.dart`
- `app/lib/pages/qr_scanner_page.dart`

**Specific Changes**:
1. **識別非同步操作**: 找出所有 `await` 後使用 `BuildContext` 的位置
2. **新增 mounted 檢查**: 在使用 `context` 前加入 `if (!context.mounted) return;`
3. **確保安全性**: 對於 `Navigator.of(context)`, `ScaffoldMessenger.of(context)` 等操作都需檢查

**Example**:
```dart
// 原程式碼 (有風險)
Future<void> deleteContact() async {
  await contactService.delete(contactId);
  Navigator.of(context).pop(); // 可能崩潰
}

// 修復後 (安全)
Future<void> deleteContact() async {
  await contactService.delete(contactId);
  if (!context.mounted) return; // 檢查 widget 是否仍掛載
  Navigator.of(context).pop();
}
```

### Fix 6: 更新廢棄 API 使用

**Files**: 需要搜尋所有使用 `withOpacity` 和不必要 `foundation.dart` 引入的檔案

**Specific Changes**:
1. **替換 withOpacity**: 將 `Color.withOpacity(value)` 改為 `Color.withValues(alpha: value)`
2. **移除多餘引入**: 刪除未使用的 `import 'package:flutter/foundation.dart'`

**Example**:
```dart
// 原程式碼 (廢棄 API)
final color = Colors.black.withOpacity(0.5);

// 修復後 (現代 API)
final color = Colors.black.withValues(alpha: 0.5);
```

## Testing Strategy

### Validation Approach

測試策略採用三階段方法：
1. **探索性測試**: 在未修復的程式碼上執行測試，確認 bug 存在並理解根本原因
2. **修復驗證**: 在修復後的程式碼上執行測試，確認 bug 已解決
3. **保持性測試**: 確保修復不影響現有功能

### Exploratory Bug Condition Checking

**Goal**: 在實作修復前，先在未修復的程式碼上執行測試，觀察失敗情況並確認根本原因。若測試結果與假設不符，需重新分析。

**Test Plan**: 

1. **WebSocket 大小限制測試**: 
   - 建立包含 10 個成員的測試群組
   - 發送包含 Link Preview 的訊息（每個成員密文約 1KB）
   - 觀察後端 WebSocket 日誌，預期看到 `read limit exceeded` 錯誤
   - 預期結果: 連線中斷，訊息未送達

2. **Link Preview 類型測試**:
   - 發送包含 YouTube 連結的訊息
   - 觀察後端日誌，確認 `msg.Type` 被設定為 `"link"`
   - 觀察前端日誌，預期看到 `StateError` 崩潰
   - 預期結果: 前端應用程式崩潰或訊息無法顯示

3. **Flutter 編譯測試**:
   - 執行 `flutter build` 或 `flutter run`
   - 觀察編譯器輸出，預期看到 `Undefined name '_'` 錯誤
   - 預期結果: 編譯失敗，列出所有受影響的檔案和行號

4. **E2EE 解密失敗測試**:
   - 模擬解密失敗情境（例如使用錯誤的金鑰）
   - 觀察訊息狀態變化
   - 等待超過 10 秒，觀察訊息是否被標記為永久失敗
   - 預期結果: 訊息狀態變為 `MessageStatus.failed`，無法恢復

5. **BuildContext 非同步測試**:
   - 在 `contact_info_page.dart` 中觸發刪除聯絡人操作
   - 在非同步操作期間快速導航離開頁面
   - 觀察是否產生崩潰或錯誤日誌
   - 預期結果: 可能產生 `BuildContext` 相關錯誤

6. **廢棄 API 測試**:
   - 執行 `flutter analyze`
   - 觀察警告訊息，預期看到 `withOpacity` 廢棄警告
   - 預期結果: 編譯成功但產生警告

**Expected Counterexamples**:
- WebSocket 連線在群組訊息超過 8KB 時中斷
- 前端在解析 `"link"` 類型時拋出 `StateError`
- Flutter 編譯器拒絕包含孤立底線的程式碼
- E2EE 解密失敗後訊息被永久標記為失敗
- 非同步操作後使用 `BuildContext` 可能導致崩潰
- 使用廢棄 API 產生編譯警告

### Fix Checking

**Goal**: 驗證修復後，所有觸發 bug 條件的輸入都能產生預期的正確行為。

**Pseudocode**:
```
FOR ALL message WHERE isBugCondition1(message) DO
  result := websocket_fixed.handleMessage(message)
  ASSERT result.connectionMaintained == true
  ASSERT result.messageDelivered == true
END FOR

FOR ALL message WHERE isBugCondition2(message) DO
  result := backend_fixed.SendMessage(message)
  ASSERT result.typePreserved == true
  ASSERT frontend.parseMessage(result) succeeds
END FOR

FOR ALL file WHERE isBugCondition3(file) DO
  result := flutter_compiler.compile(file_fixed)
  ASSERT result.success == true
END FOR

FOR ALL message WHERE isBugCondition4(message) DO
  result := frontend_fixed.handleDecryptionFailure(message)
  ASSERT result.status == MessageStatus.decryptingRetry
  ASSERT result.statusText contains "等待對方上線"
END FOR

FOR ALL component WHERE isBugCondition5(component) DO
  result := component_fixed.asyncOperation()
  ASSERT result.noContextError == true
END FOR

FOR ALL code WHERE isBugCondition6(code) DO
  result := flutter_analyzer.analyze(code_fixed)
  ASSERT result.noDeprecationWarnings == true
END FOR
```

### Preservation Checking

**Goal**: 驗證修復後，所有不觸發 bug 條件的輸入都能產生與原始實作相同的行為。

**Pseudocode**:
```
FOR ALL message WHERE NOT isBugCondition1(message) DO
  ASSERT websocket_original.handleMessage(message) = websocket_fixed.handleMessage(message)
END FOR

FOR ALL message WHERE NOT isBugCondition2(message) DO
  ASSERT backend_original.SendMessage(message) = backend_fixed.SendMessage(message)
END FOR

FOR ALL file WHERE NOT isBugCondition3(file) DO
  ASSERT flutter_compiler.compile(file_original) = flutter_compiler.compile(file_fixed)
END FOR

FOR ALL message WHERE NOT isBugCondition4(message) DO
  ASSERT frontend_original.handleMessage(message) = frontend_fixed.handleMessage(message)
END FOR

FOR ALL component WHERE NOT isBugCondition5(component) DO
  ASSERT component_original.behavior() = component_fixed.behavior()
END FOR

FOR ALL code WHERE NOT isBugCondition6(code) DO
  ASSERT flutter_analyzer.analyze(code_original) = flutter_analyzer.analyze(code_fixed)
END FOR
```

**Testing Approach**: 屬性基礎測試（Property-Based Testing）建議用於保持性檢查，因為：
- 自動產生大量測試案例，涵蓋輸入域
- 捕捉手動單元測試可能遺漏的邊界情況
- 提供強有力的保證，確保所有非 bug 輸入的行為不變

**Test Plan**: 

1. **小型訊息傳輸保持性**: 
   - 觀察未修復程式碼處理小於 8KB 訊息的行為
   - 編寫測試驗證修復後相同行為
   - 測試案例: 單人對話、小型群組（2-3 人）、短文字訊息

2. **無 Link Preview 訊息保持性**:
   - 觀察未修復程式碼處理純文字訊息的行為
   - 編寫測試驗證修復後相同行為
   - 測試案例: 純文字、圖片、檔案、語音訊息

3. **正常程式碼編譯保持性**:
   - 觀察未修復程式碼的編譯結果
   - 編寫測試驗證修復後相同編譯結果
   - 測試案例: 不包含孤立底線的所有其他檔案

4. **解密成功訊息保持性**:
   - 觀察未修復程式碼處理解密成功訊息的行為
   - 編寫測試驗證修復後相同行為
   - 測試案例: 正常的單人對話、群組訊息、各種訊息類型

5. **同步 BuildContext 使用保持性**:
   - 觀察未修復程式碼在同步操作中使用 `BuildContext` 的行為
   - 編寫測試驗證修復後相同行為
   - 測試案例: 按鈕點擊、表單提交、即時導航

6. **現代 API 使用保持性**:
   - 觀察未修復程式碼使用現代 API 的編譯結果
   - 編寫測試驗證修復後相同結果
   - 測試案例: 所有不使用廢棄 API 的程式碼

### Unit Tests

**Fix 1: WebSocket 訊息大小**
- 測試 8KB 訊息正常傳輸（邊界下限）
- 測試 100KB 群組訊息正常傳輸
- 測試 500KB 群組訊息正常傳輸
- 測試 1MB 訊息正常傳輸（邊界上限）
- 測試超過 1MB 訊息被拒絕

**Fix 2: Link Preview 類型**
- 測試包含 Link Preview 的訊息保持原始類型
- 測試前端能正確解析包含 Link Preview 的訊息
- 測試 Link Preview 資料正確儲存和顯示
- 測試無效的 Link Preview 被清除

**Fix 3: Flutter 編譯**
- 測試所有受影響檔案編譯成功
- 測試移除底線後功能不變
- 測試編譯器不產生 `Undefined name '_'` 錯誤

**Fix 4: E2EE 解密失敗**
- 測試解密失敗後訊息保持 `decryptingRetry` 狀態
- 測試顯示正確的等待訊息
- 測試發送方上線後自動重試
- 測試手動重試功能

**Fix 5: BuildContext 安全**
- 測試非同步操作後 widget 已卸載時不崩潰
- 測試非同步操作後 widget 仍掛載時正常運作
- 測試所有受影響的頁面和服務

**Fix 6: 廢棄 API**
- 測試 `withValues` 產生與 `withOpacity` 相同的顏色
- 測試移除多餘引入後編譯成功
- 測試 `flutter analyze` 不產生廢棄警告

### Property-Based Tests

**Property 1: WebSocket 訊息大小範圍**
- 產生隨機大小（1 byte 到 1MB）的訊息
- 驗證所有小於 1MB 的訊息都能成功傳輸
- 驗證所有超過 1MB 的訊息都被拒絕

**Property 2: 訊息類型保持**
- 產生隨機的訊息類型和 Link Preview 組合
- 驗證後端不覆寫前端設定的類型
- 驗證前端能正確解析所有有效的訊息類型

**Property 3: 解密狀態轉換**
- 產生隨機的訊息狀態和發送方線上狀態組合
- 驗證解密失敗時不會轉換為永久失敗狀態
- 驗證解密成功時正常轉換為 `sent` 狀態

**Property 4: BuildContext 安全性**
- 產生隨機的非同步操作和 widget 生命週期組合
- 驗證所有情況下都不會因 `BuildContext` 使用而崩潰
- 驗證 `mounted` 檢查正確防止錯誤

### Integration Tests

**Test 1: 大型群組訊息端到端流程**
- 建立 20 人測試群組
- 發送包含 Link Preview 的長文字訊息
- 驗證所有成員都能接收並正確顯示訊息
- 驗證 WebSocket 連線保持穩定

**Test 2: E2EE 解密失敗恢復流程**
- 模擬解密失敗情境
- 驗證訊息顯示等待狀態
- 模擬發送方上線
- 驗證訊息自動重新解密並正確顯示

**Test 3: Flutter 應用程式完整編譯和執行**
- 執行 `flutter clean && flutter build`
- 驗證編譯成功，無錯誤和警告
- 執行應用程式，測試所有受影響的功能
- 驗證使用者體驗流暢，無崩潰

**Test 4: 頁面導航和非同步操作**
- 開啟聯絡人資訊頁面
- 觸發刪除操作
- 在非同步操作期間快速導航離開
- 驗證應用程式不崩潰，操作正確完成

**Test 5: 跨平台相容性**
- 在 iOS、Android、Web 平台測試所有修復
- 驗證 WebSocket 連線在所有平台穩定
- 驗證 UI 在所有平台正確顯示
- 驗證 E2EE 在所有平台正常運作
