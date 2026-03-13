# E2EE Duplicate Re-encrypt Request Bugfix Design

## Overview

此 bug 導致 E2EE auto-resend 機制在每次 hot restart 或 WebSocket 重連時，重複發送 re_encrypt_request 給同樣的約 30 條訊息，且每條訊息會被發送兩輪。更嚴重的是，即使訊息狀態已更新為 MessageStatus.read，系統仍然嘗試發送請求。

修復策略採用三管齊下的方式：
1. **狀態檢查邏輯**：在發送 re_encrypt_request 前，檢查訊息在記憶體中的當前狀態
2. **初始化防護**：使用 _isInitialized flag 防止同一 session 中重複初始化
3. **資料庫同步**：在解密成功後立即同步更新 LocalDB 的 status 欄位

## Glossary

- **Bug_Condition (C)**: 當 app 執行 hot restart 或 WebSocket 重連時，系統從 LocalDB 載入 decryptingRetry 狀態的訊息，但未檢查記憶體中的實際狀態，導致重複發送 re_encrypt_request
- **Property (P)**: 系統應在發送 re_encrypt_request 前檢查訊息的當前狀態，若狀態為 read/delivered/sent 則跳過該訊息
- **Preservation**: 對於狀態確實為 decryptingRetry 的訊息，系統必須繼續正常發送 re_encrypt_request
- **ChatRoomProvider**: `app/lib/features/chat/providers/chat_room_provider.dart` 中的 ViewModel，負責處理聊天室訊息邏輯，包含 E2EE auto-resend 機制
- **LocalDbService**: `app/lib/core/storage/local_db_service.dart` 中的服務，負責本地訊息資料庫的 CRUD 操作
- **MessageStatus**: 訊息狀態枚舉，包含 pending/sent/delivered/read/failed/decryptingRetry
- **re_encrypt_request**: WebSocket 控制訊息，當接收方解密失敗時發送給發送方，請求重新加密
- **re_encrypt_response**: WebSocket 控制訊息，發送方收到 re_encrypt_request 後，重新加密訊息並回傳

## Bug Details

### Bug Condition

此 bug 在以下情況下觸發：
1. App 執行 hot restart 或 WebSocket 重連
2. 系統從 LocalDB 查詢所有 status = 'decryptingRetry' 的訊息
3. 系統未檢查這些訊息在記憶體（ChatRoomState）中的實際狀態
4. 系統對所有查詢結果發送 re_encrypt_request，即使訊息已經解密成功並更新為 read/delivered

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type {event: String, messages: List<Message>}
  OUTPUT: boolean
  
  RETURN (input.event IN ['hot_restart', 'ws_reconnected'])
         AND (EXISTS message IN input.messages WHERE 
              message.statusInDB == MessageStatus.decryptingRetry
              AND message.statusInMemory IN [MessageStatus.read, MessageStatus.delivered, MessageStatus.sent])
         AND re_encrypt_request_sent(message)
END FUNCTION
```

### Examples

- **Example 1**: 用戶在聊天室中收到 30 條加密訊息，其中 5 條解密失敗並標記為 decryptingRetry。發送方重新加密後，這 5 條訊息成功解密並在 UI 中顯示為 read 狀態。但 LocalDB 中的 status 欄位仍然是 'decryptingRetry'。當用戶執行 hot restart 時，系統再次從 LocalDB 載入這 5 條訊息並發送 re_encrypt_request，導致 log 顯示 "Message is not in decryptingRetry status: MessageStatus.read"

- **Example 2**: WebSocket 連線中斷後重連，系統觸發 resendPendingMessages()，同時也觸發了 E2EE auto-resend 初始化邏輯。由於沒有 _isInitialized flag，同一批訊息的 re_encrypt_request 被發送兩次

- **Example 3**: 用戶收到一條加密訊息解密失敗，系統發送 re_encrypt_request。發送方回傳 re_encrypt_response，接收方成功解密並在 ChatRoomState 中更新為 MessageStatus.delivered。但 LocalDB 中該訊息的 status 仍然是 'decryptingRetry'。下次 app 重啟時，系統再次嘗試發送 re_encrypt_request

- **Edge Case**: 訊息在 LocalDB 中狀態為 decryptingRetry，但在記憶體中已被標記為 failed（達到重試上限）。系統應跳過此訊息，不應再次發送 re_encrypt_request

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- 訊息首次解密失敗時，系統必須繼續將訊息標記為 decryptingRetry 並發送 re_encrypt_request
- 發送方收到 re_encrypt_request 時，系統必須繼續從 LocalDB 取得原始訊息並重新加密後回傳
- 接收方收到 re_encrypt_response 時，系統必須繼續嘗試重新解密並更新訊息狀態
- 訊息重試次數達到上限（>= 2 次）時，系統必須繼續將訊息標記為 MessageStatus.failed 並停止重試

**Scope:**
所有狀態確實為 MessageStatus.decryptingRetry 且尚未達到重試上限的訊息，應完全不受此修復影響。這包括：
- 首次解密失敗的訊息
- 重試次數 < 2 的訊息
- 在記憶體中狀態確實為 decryptingRetry 的訊息

## Hypothesized Root Cause

基於 bug 描述和程式碼分析，最可能的原因是：

1. **缺少狀態檢查邏輯**: ChatRoomProvider 中沒有實作在 hot restart 或 WebSocket 重連時，從 LocalDB 載入 decryptingRetry 訊息並檢查記憶體狀態的邏輯。目前的實作只在首次解密失敗時觸發 `_handleDecryptionFailure()`，但沒有處理重連後的重試邏輯

2. **缺少初始化防護**: 目前沒有 _isInitialized flag 來防止同一 session 中重複初始化 E2EE auto-resend 邏輯。可能在 `build()` 和 WebSocket 的 `ws_reconnected` 事件中都觸發了初始化

3. **資料庫狀態未同步**: 在 `_handleReEncryptResponse()` 中，當訊息成功解密後，只呼叫了 `updateMessageContentAndStatus()` 更新 content 和 status，但這個方法在 LocalDbService 中的實作會將 status 更新為 delivered，卻沒有確保在所有解密成功的路徑中都正確呼叫

4. **缺少重連後的自動重試機制**: 目前的實作依賴 `_handleDecryptionFailure()` 在解密失敗時立即發送 re_encrypt_request，但如果當時 WebSocket 未連線，則會跳過發送。重連後沒有機制自動重試這些訊息

## Correctness Properties

Property 1: Bug Condition - Skip Re-encrypt Request for Already Decrypted Messages

_For any_ message where the bug condition holds (message.statusInDB == decryptingRetry AND message.statusInMemory IN [read, delivered, sent]), the fixed system SHALL skip sending re_encrypt_request and log the reason for skipping.

**Validates: Requirements 2.1, 2.4**

Property 2: Preservation - Continue Re-encrypt Request for Decrypting Messages

_For any_ message where the bug condition does NOT hold (message.statusInMemory == decryptingRetry AND retryCount < 2), the fixed system SHALL produce the same behavior as the original system, continuing to send re_encrypt_request and handle re_encrypt_response normally.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

Property 3: Database Synchronization - Update LocalDB Status After Successful Decryption

_For any_ message that is successfully decrypted (either on first attempt or after re_encrypt_response), the fixed system SHALL immediately update the LocalDB status field to match the in-memory status (read/delivered), ensuring database and memory state consistency.

**Validates: Requirements 2.3**

Property 4: Initialization Guard - Prevent Duplicate Initialization

_For any_ WebSocket session, the E2EE auto-resend initialization logic SHALL execute at most once, preventing duplicate re_encrypt_request sends for the same messages.

**Validates: Requirements 2.2**

## Fix Implementation

### Changes Required

基於 root cause 分析，我們需要實作以下修改：

**File**: `app/lib/features/chat/providers/chat_room_provider.dart`

**Specific Changes**:

1. **新增 _isInitialized flag**:
   - 在 ChatRoomViewModel 類別中新增 `bool _isAutoResendInitialized = false;` 欄位
   - 用於防止同一 session 中重複初始化 E2EE auto-resend 邏輯

2. **新增 _initializeAutoResend() 方法**:
   - 檢查 `_isAutoResendInitialized` flag，若已初始化則直接返回
   - 從 LocalDB 查詢所有 status = 'decryptingRetry' 的訊息
   - 對每條訊息，檢查在 `state.messages` 中的當前狀態
   - 若記憶體中狀態為 read/delivered/sent/failed，則跳過並記錄 log
   - 若記憶體中狀態為 decryptingRetry 且 retryCount < 2，則發送 re_encrypt_request
   - 設定 `_isAutoResendInitialized = true`

3. **在 build() 中呼叫 _initializeAutoResend()**:
   - 在 `Future.microtask(() => loadHistory());` 之後
   - 使用 `Future.microtask(() => _initializeAutoResend());` 延遲執行

4. **在 ws_reconnected 事件中呼叫 _initializeAutoResend()**:
   - 在 `resendPendingMessages();` 之後
   - 確保重連後自動重試未完成的解密訊息

5. **在 ws_disconnected 事件中重置 flag**:
   - 設定 `_isAutoResendInitialized = false;`
   - **重要**: 必須在斷線時重置 flag，否則下次重連時不會再觸發 auto-resend
   - 這確保每次重連都能正常執行 auto-resend 邏輯

6. **修改 _tryDecryptMessage() 方法**:
   - 在成功解密後（`return m.copyWith(content: decrypted);` 之前）
   - 呼叫 `LocalDbService().updateMessageStatus(m.clientMsgId ?? m.id, MessageStatus.delivered);`
   - **重要**: 使用 `clientMsgId ?? m.id` 因為在 loadHistory 時 message.id 可能是 clientMsgId 而非 server id
   - 確保資料庫狀態與記憶體狀態同步

7. **修改 _handleReEncryptResponse() 方法**:
   - 確認在解密成功後，`updateMessageContentAndStatus()` 正確更新 status 為 delivered
   - 這部分目前已正確實作，無需修改

8. **新增 _getDecryptingRetryMessages() 輔助方法**:
   - 從 LocalDB 查詢所有 status = 'decryptingRetry' 的訊息
   - 返回 `Future<List<Message>>`

**File**: `app/lib/core/storage/local_db_service.dart`

**Specific Changes**:

1. **新增 getDecryptingRetryMessages() 方法**:
   - 查詢所有 status = 'decryptingRetry' 的訊息
   - 按 created_at ASC 排序（先處理較舊的訊息）
   - 返回 `Future<List<Message>>`

## Testing Strategy

### Validation Approach

測試策略分為三個階段：
1. **Exploratory Bug Condition Checking**: 在未修復的程式碼上執行測試，確認 bug 存在並理解 root cause
2. **Fix Checking**: 驗證修復後的程式碼對於 bug condition 的輸入產生正確行為
3. **Preservation Checking**: 驗證修復後的程式碼對於非 bug condition 的輸入保持原有行為

### Exploratory Bug Condition Checking

**Goal**: 在未修復的程式碼上表面化 counterexamples，確認或反駁 root cause 分析。如果反駁，則需要重新假設。

**Test Plan**: 撰寫測試模擬 hot restart 和 WebSocket 重連場景，觀察系統是否對已解密的訊息重複發送 re_encrypt_request。在未修復的程式碼上執行，預期會看到失敗並理解 root cause。

**Test Cases**:
1. **Hot Restart with Decrypted Messages**: 模擬 30 條訊息中有 5 條在 LocalDB 中狀態為 decryptingRetry，但在記憶體中已是 read。執行 hot restart，觀察是否重複發送 re_encrypt_request（在未修復程式碼上會失敗）
2. **WebSocket Reconnect Duplicate Initialization**: 模擬 WebSocket 重連，觀察是否同一批訊息的 re_encrypt_request 被發送兩次（在未修復程式碼上會失敗）
3. **Database Status Not Synced**: 模擬訊息成功解密後，檢查 LocalDB 中的 status 欄位是否仍然是 decryptingRetry（在未修復程式碼上會失敗）
4. **Edge Case - Failed Status**: 模擬訊息在記憶體中已標記為 failed，但 LocalDB 中仍是 decryptingRetry。觀察是否跳過該訊息（在未修復程式碼上可能失敗）

**Expected Counterexamples**:
- 系統對已解密的訊息重複發送 re_encrypt_request
- Log 中出現 "Message is not in decryptingRetry status: MessageStatus.read" 錯誤
- 同一批訊息的 re_encrypt_request 被發送兩次
- LocalDB 中的 status 欄位在解密成功後仍然是 decryptingRetry

### Fix Checking

**Goal**: 驗證對於所有 bug condition 成立的輸入，修復後的系統產生預期行為。

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := handleAutoResend_fixed(input)
  ASSERT NOT re_encrypt_request_sent_for_already_decrypted_messages(result)
  ASSERT log_contains_skip_reason(result)
END FOR
```

**Test Cases**:
1. **Property Test - Skip Already Decrypted**: 生成多種場景（不同數量的訊息、不同狀態組合），驗證系統跳過已解密的訊息
2. **Property Test - Database Sync**: 生成多種解密成功場景，驗證 LocalDB status 欄位正確更新
3. **Property Test - Initialization Guard**: 生成多種重連場景，驗證 _isInitialized flag 防止重複初始化

### Preservation Checking

**Goal**: 驗證對於所有 bug condition 不成立的輸入，修復後的系統產生與原系統相同的結果。

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT handleAutoResend_original(input) = handleAutoResend_fixed(input)
END FOR
```

**Testing Approach**: 使用 property-based testing 進行 preservation checking，因為：
- 自動生成大量測試案例，覆蓋整個輸入域
- 捕捉手動單元測試可能遺漏的 edge cases
- 提供強保證：對於所有非 buggy 輸入，行為保持不變

**Test Plan**: 先在未修復程式碼上觀察正常解密流程的行為，然後撰寫 property-based tests 捕捉該行為。

**Test Cases**:
1. **Preservation - First Time Decryption Failure**: 觀察未修復程式碼上首次解密失敗的行為，驗證修復後行為相同（標記為 decryptingRetry 並發送 re_encrypt_request）
2. **Preservation - Re-encrypt Request Handling**: 觀察未修復程式碼上發送方處理 re_encrypt_request 的行為，驗證修復後行為相同（從 LocalDB 取得原始訊息並重新加密）
3. **Preservation - Re-encrypt Response Handling**: 觀察未修復程式碼上接收方處理 re_encrypt_response 的行為，驗證修復後行為相同（重新解密並更新狀態）
4. **Preservation - Retry Limit**: 觀察未修復程式碼上重試次數達到上限的行為，驗證修復後行為相同（標記為 failed 並停止重試）

### Unit Tests

- 測試 `_initializeAutoResend()` 方法正確檢查記憶體狀態並跳過已解密訊息
- 測試 `_isAutoResendInitialized` flag 防止重複初始化
- 測試 `_tryDecryptMessage()` 在解密成功後正確更新 LocalDB status
- 測試 `getDecryptingRetryMessages()` 正確查詢 LocalDB
- 測試 edge cases（訊息在記憶體中不存在、訊息狀態為 failed 等）

### Property-Based Tests

- 生成隨機訊息集合（不同狀態組合），驗證 `_initializeAutoResend()` 正確處理
- 生成隨機重連場景，驗證 _isInitialized flag 防止重複初始化
- 生成隨機解密成功場景，驗證 LocalDB status 同步更新
- 測試 preservation：生成隨機正常解密流程，驗證修復後行為不變

### Integration Tests

- 測試完整的 hot restart 流程：app 重啟 → 載入訊息 → 檢查狀態 → 跳過已解密訊息
- 測試完整的 WebSocket 重連流程：斷線 → 重連 → 初始化 auto-resend → 不重複發送
- 測試完整的解密重試流程：解密失敗 → 發送 re_encrypt_request → 收到 re_encrypt_response → 解密成功 → LocalDB 狀態同步
- 測試視覺反饋：訊息狀態在 UI 中正確顯示（decryptingRetry → delivered → read）
