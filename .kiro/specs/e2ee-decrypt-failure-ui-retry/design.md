# E2EE 解密失敗 UI 改善 Bugfix Design

## Overview

當訊息解密失敗時，當前 UI 只顯示「🔒 無法解密」的純文字，缺乏視覺提示和互動元素。用戶不知道可以點擊重試，導致體驗不佳。

此 bugfix 將改善解密失敗的 UI 體驗，新增：
1. 橘色邊框的視覺提示
2. 明確的重試文字提示「🔒 無法解密 點擊重試 ↺」
3. 點擊事件處理，觸發重新解密流程
4. 解密中狀態的動畫顯示「⏳ 解密中…」

## Glossary

- **Bug_Condition (C)**: 訊息解密失敗時缺乏視覺提示和互動元素的條件
- **Property (P)**: 解密失敗時應顯示橘色邊框、重試提示，並支援點擊重試
- **Preservation**: 解密成功、首次解密中、未加密訊息的顯示行為必須保持不變
- **MessageBubble**: `app/lib/features/chat/ui/widgets/message_bubble.dart` 中的訊息氣泡 Widget
- **isDecryptionFailure**: 判斷訊息是否解密失敗的條件（包含 🔒 前綴、status 為 failed 或看起來像密文）
- **isDecryptingRetry**: 判斷訊息是否正在重試解密的條件（status 為 decryptingRetry）
- **chatRoomProvider**: 聊天室狀態管理 Provider，位於 `app/lib/features/chat/providers/chat_room_provider.dart`
- **retryDecryptMessage**: 需要新增的方法，用於重新發送 re_encrypt_request 並更新訊息狀態

## Bug Details

### Bug Condition

Bug 發生在訊息解密失敗時，UI 缺乏明確的視覺提示和互動元素。當前實現只顯示純文字「🔒 無法解密」，沒有邊框、沒有重試提示、點擊也沒有反應。

**Formal Specification:**
```
FUNCTION isBugCondition(message)
  INPUT: message of type Message
  OUTPUT: boolean
  
  RETURN (message.content.startsWith('🔒') OR 
          message.status == MessageStatus.failed OR 
          looksLikeCiphertext(message.content))
         AND NOT hasOrangeBorder(message)
         AND NOT hasRetryHint(message)
         AND NOT hasClickHandler(message)
END FUNCTION
```

### Examples

- **範例 1**: 訊息內容為「🔒 無法解密」，但沒有橘色邊框，用戶不知道這是錯誤狀態
- **範例 2**: 訊息解密失敗（status = failed），顯示鎖頭圖示，但沒有「點擊重試」的文字提示
- **範例 3**: 用戶點擊解密失敗的訊息，沒有任何反應，無法觸發重試
- **範例 4**: 訊息正在重試解密（status = decryptingRetry），但沒有顯示「⏳ 解密中…」的動畫狀態

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- 訊息解密成功時，必須繼續正常顯示解密後的內容
- 訊息首次解密中時，必須繼續顯示原有的解密中狀態
- 未加密訊息必須繼續正常顯示內容
- 非解密失敗訊息的點擊行為（長按選單、回覆、刪除等）必須保持不變

**Scope:**
所有不涉及解密失敗狀態的訊息顯示和互動行為都應完全不受影響。這包括：
- 正常文字、圖片、語音、檔案訊息的顯示
- 長按訊息顯示操作選單（回覆、刪除、收回、表情符號）
- 訊息狀態圖示（pending, sending, sent, delivered, read）
- 訊息時間戳記和已讀狀態
- 回覆訊息和 Link Preview 的顯示

## Hypothesized Root Cause

基於 bug 描述和代碼分析，主要問題在於：

1. **缺乏視覺區分**: 當前解密失敗訊息使用與正常訊息相同的氣泡樣式，沒有橘色邊框來突顯錯誤狀態

2. **缺乏操作提示**: 文字只顯示「🔒 無法解密」，沒有告知用戶可以點擊重試，缺少「點擊重試 ↺」的提示

3. **缺乏互動處理**: MessageBubble 的 GestureDetector 只處理 onLongPress（長按選單），沒有為解密失敗訊息新增 onTap 處理

4. **缺乏重試方法**: chatRoomProvider 中沒有 retryDecryptMessage 方法來處理重新解密的邏輯

5. **缺乏重試狀態顯示**: 當訊息狀態為 decryptingRetry 時，沒有顯示「⏳ 解密中…」的動畫，用戶不知道系統正在處理

## Correctness Properties

Property 1: Bug Condition - 解密失敗視覺提示與互動

_For any_ 訊息 message 其中 isDecryptionFailure(message) 為 true（解密失敗），修復後的 MessageBubble SHALL 顯示橘色邊框、顯示「🔒 無法解密 點擊重試 ↺」文字提示，並在點擊時呼叫 chatRoomProvider.notifier.retryDecryptMessage(message.id) 觸發重新解密流程。

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Bug Condition - 重試狀態動畫顯示

_For any_ 訊息 message 其中 isDecryptingRetry(message) 為 true（正在重試解密），修復後的 MessageBubble SHALL 顯示「⏳ 解密中…」的動畫狀態，並在重試完成後更新為對應的結果狀態（成功或失敗）。

**Validates: Requirements 2.4, 2.5**

Property 3: Preservation - 非解密失敗訊息行為

_For any_ 訊息 message 其中 isDecryptionFailure(message) 為 false（非解密失敗），修復後的代碼 SHALL 產生與原始代碼完全相同的顯示和互動行為，保留所有現有功能（正常顯示、長按選單、回覆、刪除等）。

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

## Fix Implementation

### Changes Required

假設我們的根本原因分析正確：

**File**: `app/lib/features/chat/ui/widgets/message_bubble.dart`

**Function**: `_MessageBubbleState.build`

**Specific Changes**:

1. **修改解密失敗文字提示**:
   - 將 `errorText` 從「🔒 解密失敗」改為「🔒 無法解密 點擊重試 ↺」
   - 位置：第 115 行附近的 `isDecryptionFailure` 條件分支

2. **新增橘色邊框樣式**:
   - 在 MessageBubble 的 Container decoration 中，當 `isDecryptionFailure` 為 true 時，新增 `border: Border.all(color: Colors.orange, width: 2)`
   - 位置：第 680 行附近的 Container decoration

3. **新增點擊事件處理**:
   - 在 GestureDetector 中新增 `onTap` 處理
   - 當 `isDecryptionFailure` 為 true 且 `!isDecryptingRetry` 時，呼叫 `ref.read(chatRoomProvider(widget.params).notifier).retryDecryptMessage(msg.id)`
   - 位置：第 670 行附近的 GestureDetector

4. **修改重試狀態顯示**:
   - 將 `isDecryptingRetry` 條件分支的文字從「🔒 等待對方上線以重新解密...」改為「⏳ 解密中…」
   - 保留 CircularProgressIndicator 動畫
   - 位置：第 85 行附近的 `isDecryptingRetry` 條件分支

**File**: `app/lib/features/chat/providers/chat_room_provider.dart`

**Class**: `ChatRoomNotifier`

**Specific Changes**:

5. **新增 retryDecryptMessage 方法**:
   - 方法簽名：`Future<void> retryDecryptMessage(String messageId)`
   - 功能：
     1. 找到對應的訊息
     2. 更新訊息狀態為 `MessageStatus.decryptingRetry`
     3. 呼叫現有的 re_encrypt_request 發送邏輯（可能需要重用或提取現有代碼）
     4. 更新本地資料庫和 UI 狀態
   - 位置：在 ChatRoomNotifier 類別中新增此方法

## Testing Strategy

### Validation Approach

測試策略採用兩階段方法：首先在未修復的代碼上展示 bug（探索性測試），然後驗證修復後的代碼正確實現預期行為並保留現有功能。

### Exploratory Bug Condition Checking

**Goal**: 在實施修復前，在未修復的代碼上展示 bug。確認或反駁根本原因分析。如果反駁，需要重新假設。

**Test Plan**: 撰寫測試模擬解密失敗的訊息，檢查 UI 是否缺乏橘色邊框、重試提示和點擊處理。在未修復的代碼上執行這些測試，觀察失敗並理解根本原因。

**Test Cases**:
1. **解密失敗視覺測試**: 創建 status = failed 的訊息，檢查是否沒有橘色邊框（未修復代碼上會失敗）
2. **解密失敗文字測試**: 創建內容為「🔒 無法解密」的訊息，檢查是否沒有「點擊重試 ↺」提示（未修復代碼上會失敗）
3. **點擊事件測試**: 模擬點擊解密失敗訊息，檢查是否沒有呼叫 retryDecryptMessage（未修復代碼上會失敗）
4. **重試狀態測試**: 創建 status = decryptingRetry 的訊息，檢查是否沒有顯示「⏳ 解密中…」（未修復代碼上會失敗）

**Expected Counterexamples**:
- 解密失敗訊息沒有橘色邊框，與正常訊息無法區分
- 文字提示不包含「點擊重試」，用戶不知道可以重試
- 點擊解密失敗訊息沒有任何反應
- 重試狀態顯示「等待對方上線」而非「解密中」

可能原因：缺乏視覺樣式、缺乏文字提示、缺乏點擊處理、缺乏狀態顯示

### Fix Checking

**Goal**: 驗證對於所有解密失敗的訊息，修復後的代碼產生預期行為。

**Pseudocode:**
```
FOR ALL message WHERE isDecryptionFailure(message) DO
  widget := MessageBubble_fixed(message)
  ASSERT widget.hasOrangeBorder()
  ASSERT widget.text.contains('點擊重試 ↺')
  ASSERT widget.onTap() calls retryDecryptMessage(message.id)
END FOR

FOR ALL message WHERE isDecryptingRetry(message) DO
  widget := MessageBubble_fixed(message)
  ASSERT widget.text.contains('⏳ 解密中…')
  ASSERT widget.hasLoadingAnimation()
END FOR
```

### Preservation Checking

**Goal**: 驗證對於所有非解密失敗的訊息，修復後的代碼產生與原始代碼相同的結果。

**Pseudocode:**
```
FOR ALL message WHERE NOT isDecryptionFailure(message) DO
  ASSERT MessageBubble_original(message) = MessageBubble_fixed(message)
END FOR
```

**Testing Approach**: 建議使用 Property-Based Testing 進行保留檢查，因為：
- 它自動生成許多測試案例覆蓋輸入域
- 它能捕捉手動單元測試可能遺漏的邊緣案例
- 它提供強保證，確保所有非 bug 輸入的行為不變

**Test Plan**: 首先在未修復的代碼上觀察正常訊息、圖片、語音、檔案訊息的行為，然後撰寫 property-based tests 捕捉這些行為。

**Test Cases**:
1. **正常訊息顯示保留**: 觀察未修復代碼上解密成功訊息的顯示，撰寫測試驗證修復後繼續正常顯示
2. **長按選單保留**: 觀察未修復代碼上長按訊息顯示選單的行為，撰寫測試驗證修復後繼續正常工作
3. **訊息狀態圖示保留**: 觀察未修復代碼上各種狀態（pending, sending, sent, delivered, read）的圖示顯示，撰寫測試驗證修復後保持不變
4. **回覆和 Link Preview 保留**: 觀察未修復代碼上回覆訊息和 Link Preview 的顯示，撰寫測試驗證修復後保持不變

### Unit Tests

- 測試 isDecryptionFailure 條件判斷（包含 🔒 前綴、status = failed、密文特徵）
- 測試解密失敗訊息顯示橘色邊框
- 測試解密失敗訊息顯示「🔒 無法解密 點擊重試 ↺」文字
- 測試點擊解密失敗訊息呼叫 retryDecryptMessage
- 測試 isDecryptingRetry 狀態顯示「⏳ 解密中…」和動畫
- 測試正常訊息不受影響（無橘色邊框、無重試提示）
- 測試邊緣案例（空內容、超長內容、特殊字元）

### Property-Based Tests

- 生成隨機訊息狀態，驗證解密失敗訊息正確顯示視覺提示和互動元素
- 生成隨機訊息類型（text, image, voice, file），驗證非解密失敗訊息保留原有顯示行為
- 生成隨機訊息內容，驗證長按選單和其他互動行為在修復後保持不變
- 測試多種訊息狀態組合，確保狀態轉換正確（failed -> decryptingRetry -> sent/failed）

### Integration Tests

- 測試完整的解密失敗流程：訊息解密失敗 -> 顯示橘色邊框和重試提示 -> 點擊重試 -> 顯示解密中動畫 -> 更新為成功或失敗狀態
- 測試在聊天室中切換不同訊息類型，驗證解密失敗訊息的視覺提示正確顯示
- 測試重試解密後的狀態更新，驗證 UI 正確反映最新狀態
- 測試與其他功能的互動（回覆解密失敗訊息、刪除解密失敗訊息、表情符號反應）
