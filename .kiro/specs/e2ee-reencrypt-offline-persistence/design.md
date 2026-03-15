# E2EE Re-encrypt Offline Persistence Bugfix Design

## Overview

此 bug 修復針對 E2EE 系統中 re_encrypt_request 在發送方離線時遺失的問題。目前系統僅使用 WebSocket 即時傳輸，當發送方離線時請求會永久遺失，導致訊息無法解密。修復策略是在後端新增 MongoDB 持久化層，當發送方離線時儲存請求，並在發送方重新上線時自動下發。同時移除接收方的 2 次重試上限，改用 7 天 TTL 過期機制。

## Glossary

- **Bug_Condition (C)**: 發送方離線時接收方發送 re_encrypt_request 的情況
- **Property (P)**: re_encrypt_request 應被持久化並在發送方上線時自動下發
- **Preservation**: 發送方在線時的即時 WebSocket 轉發行為必須保持不變
- **re_encrypt_request**: 接收方無法解密訊息時向發送方請求重新加密的訊息
- **re_encrypt_response**: 發送方回應的重新加密後的訊息內容
- **MessageID**: 需要重新加密的原始訊息 ID
- **SenderID**: 原始訊息的發送方 User ID
- **ReceiverID**: 請求重新加密的接收方 User ID
- **RoomID**: 訊息所屬的聊天室 ID
- **TTL (Time To Live)**: MongoDB 自動過期機制，設定為 7 天

## Bug Details

### Bug Condition

此 bug 發生在發送方離線時接收方嘗試請求重新加密訊息的情況。系統目前僅透過 WebSocket 即時傳輸 re_encrypt_request，當發送方不在線上時，請求無法送達且不會被儲存，導致接收方在重試 2 次後永久放棄解密。

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type ReEncryptRequestEvent
  OUTPUT: boolean
  
  RETURN input.eventType == 're_encrypt_request'
         AND input.senderID EXISTS
         AND NOT isUserOnline(input.senderID)
         AND NOT requestPersistedInDatabase(input.messageID, input.receiverID)
END FUNCTION
```

### Examples

- **範例 1**: 使用者 A 發送加密訊息給使用者 B，使用者 B 無法解密（可能因為金鑰輪換）。使用者 B 發送 re_encrypt_request，但使用者 A 此時網路斷線。請求遺失，使用者 B 重試 2 次後標記失敗，即使使用者 A 5 分鐘後重新上線，訊息仍永久無法解密。

- **範例 2**: 使用者 A 在行動裝置上發送訊息後關閉應用程式。使用者 B 嘗試解密失敗並發送 re_encrypt_request。由於使用者 A 已離線，請求遺失。使用者 A 隔天重新開啟應用程式時，系統不會通知有待處理的重新加密請求。

- **範例 3**: 使用者 A 在網路不穩定的環境中，頻繁斷線重連。使用者 B 在使用者 A 斷線期間發送 re_encrypt_request，請求遺失。使用者 A 重新連線後，系統無法恢復該請求。

- **邊界情況**: 使用者 A 在線上，使用者 B 發送 re_encrypt_request 的瞬間使用者 A 斷線。系統應能偵測到發送失敗並將請求持久化。

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- 發送方在線時，re_encrypt_request 必須繼續透過 WebSocket 即時轉發，不經過資料庫
- 發送方收到 re_encrypt_request 後的處理邏輯（生成 re_encrypt_response）必須保持不變
- 接收方收到 re_encrypt_response 後的解密流程必須保持不變
- 一般訊息的發送和接收流程必須完全不受影響
- 其他 WebSocket 事件（typing indicators, read receipts 等）必須正常運作

**Scope:**
所有不涉及「發送方離線時的 re_encrypt_request」的輸入都應完全不受此修復影響。這包括：
- 發送方在線時的所有 re_encrypt_request 處理
- 一般加密訊息的發送和接收
- 其他類型的 WebSocket 事件
- 已成功解密的訊息處理

## Hypothesized Root Cause

基於 bug 描述，最可能的問題是：

1. **缺少持久化層**: 系統目前僅依賴 WebSocket 即時傳輸，沒有任何後端儲存機制來處理離線情況
   - re_encrypt_request 事件處理器直接嘗試透過 WebSocket 轉發
   - 當 WebSocket 連線不存在時，請求被丟棄且沒有錯誤處理

2. **缺少上線通知機制**: 系統沒有在使用者重新上線時檢查待處理請求的邏輯
   - WebSocket 連線建立時沒有觸發查詢待處理 re_encrypt_request 的流程
   - 沒有背景任務定期檢查並下發待處理請求

3. **硬性重試上限**: 接收方的 2 次重試上限過於嚴格，沒有考慮暫時性離線情況
   - 重試邏輯在 2 次失敗後永久標記訊息為解密失敗
   - 沒有提供手動重試或自動恢復機制

4. **缺少過期機制**: 沒有清理長期未處理請求的機制，可能導致資料庫累積過期記錄

## Correctness Properties

Property 1: Bug Condition - Offline Re-encrypt Request Persistence

_For any_ re_encrypt_request where the sender is offline (isBugCondition returns true), the fixed system SHALL persist the request to MongoDB with fields (MessageID, SenderID, ReceiverID, RoomID, CreatedAt, ExpiresAt), and SHALL automatically deliver the request when the sender comes back online, and SHALL delete the request from database after successful delivery.

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Preservation - Online Re-encrypt Request Behavior

_For any_ re_encrypt_request where the sender is online (isBugCondition returns false), the fixed system SHALL produce exactly the same behavior as the original system, directly forwarding the request via WebSocket without database persistence, preserving the real-time message flow and all existing WebSocket event handling.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

## Fix Implementation

### Changes Required

假設我們的根本原因分析正確：

**File**: `backend/src/services/websocket/handlers/reEncryptHandler.ts` (或類似的 WebSocket 事件處理檔案)

**Function**: `handleReEncryptRequest`

**Specific Changes**:
1. **新增 MongoDB Schema**: 建立 `PendingReEncryptRequest` collection
   - 欄位: `messageId`, `senderId`, `receiverId`, `roomId`, `createdAt`, `expiresAt`
   - 建立 TTL index 在 `expiresAt` 欄位，設定為 7 天後自動過期
   - 建立複合 index 在 `senderId` + `createdAt` 以優化查詢效能

2. **修改 re_encrypt_request 處理邏輯**: 在 `handleReEncryptRequest` 函數中新增離線檢查
   - 檢查發送方是否在線（查詢 WebSocket 連線池或 Redis session）
   - 如果在線：保持現有邏輯，直接透過 WebSocket 轉發
   - 如果離線：將請求儲存至 MongoDB，回傳成功狀態給接收方

3. **新增上線通知處理**: 在 WebSocket 連線建立時觸發查詢
   - 在 `onConnection` 或 `onAuthenticated` 事件中新增邏輯
   - 查詢該使用者的所有待處理 re_encrypt_request（按 `createdAt` 排序）
   - 逐一透過 WebSocket 下發給使用者
   - 成功下發後從資料庫中刪除記錄

4. **移除接收方重試上限**: 修改接收方的解密重試邏輯
   - 移除 2 次硬性上限的檢查
   - 改用指數退避策略（exponential backoff）持續重試
   - 依賴後端的 7 天 TTL 作為最終過期機制

5. **新增錯誤處理和日誌**: 確保系統穩定性
   - 資料庫寫入失敗時的錯誤處理
   - 下發失敗時的重試機制（可能使用者剛上線又立即斷線）
   - 記錄關鍵操作的日誌以便追蹤和除錯

**File**: `backend/src/models/PendingReEncryptRequest.ts` (新檔案)

**Specific Changes**:
1. 定義 Mongoose Schema 和 Model
2. 設定 TTL index 和複合 index
3. 提供 CRUD 操作的輔助方法

**File**: `frontend/src/services/encryption/decryptionRetry.ts` (或類似的前端解密邏輯檔案)

**Function**: `retryDecryption`

**Specific Changes**:
1. 移除 `maxRetries = 2` 的硬性限制
2. 實作指數退避重試策略
3. 新增使用者手動重試的介面（可選）

## Testing Strategy

### Validation Approach

測試策略採用兩階段方法：首先在未修復的程式碼上展示 bug 的反例，然後驗證修復後的程式碼正確運作且保留現有行為。

### Exploratory Bug Condition Checking

**Goal**: 在實作修復前，在未修復的程式碼上展示 bug 的反例。確認或反駁根本原因分析。如果反駁，需要重新假設。

**Test Plan**: 撰寫測試模擬發送方離線時接收方發送 re_encrypt_request 的情況，並斷言請求未被持久化且發送方上線後未收到請求。在未修復的程式碼上執行這些測試以觀察失敗並理解根本原因。

**Test Cases**:
1. **Offline Sender Test**: 模擬發送方離線，接收方發送 re_encrypt_request，檢查資料庫中沒有記錄（在未修復程式碼上會通過，因為確實沒有持久化）
2. **Sender Reconnect Test**: 模擬發送方重新上線，檢查是否收到先前的 re_encrypt_request（在未修復程式碼上會失敗，因為請求已遺失）
3. **Retry Limit Test**: 模擬接收方重試 2 次後標記失敗（在未修復程式碼上會通過，確認硬性上限存在）
4. **Message Permanent Failure Test**: 驗證訊息被標記為永久失敗後無法再次嘗試（在未修復程式碼上會通過，確認問題存在）

**Expected Counterexamples**:
- re_encrypt_request 在發送方離線時未被儲存至資料庫
- 發送方重新上線後沒有收到先前的請求
- 接收方在 2 次重試後永久放棄解密
- Possible causes: 缺少持久化層、缺少上線通知機制、硬性重試上限

### Fix Checking

**Goal**: 驗證對於所有符合 bug 條件的輸入，修復後的系統產生預期行為。

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := handleReEncryptRequest_fixed(input)
  ASSERT requestPersistedInDatabase(input.messageId, input.receiverId)
  
  // 模擬發送方上線
  senderReconnects(input.senderId)
  ASSERT requestDeliveredToSender(input.senderId, input.messageId)
  ASSERT NOT requestExistsInDatabase(input.messageId, input.receiverId)
END FOR
```

### Preservation Checking

**Goal**: 驗證對於所有不符合 bug 條件的輸入，修復後的系統產生與原始系統相同的結果。

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT handleReEncryptRequest_original(input) = handleReEncryptRequest_fixed(input)
END FOR
```

**Testing Approach**: 建議使用 Property-based testing 進行 preservation checking，因為：
- 它自動生成大量測試案例涵蓋輸入域
- 它能捕捉手動單元測試可能遺漏的邊界情況
- 它提供強有力的保證，確保所有非 bug 輸入的行為保持不變

**Test Plan**: 首先在未修復的程式碼上觀察發送方在線時的行為，然後撰寫 property-based tests 捕捉該行為。

**Test Cases**:
1. **Online Sender Preservation**: 觀察發送方在線時 re_encrypt_request 直接透過 WebSocket 轉發，撰寫測試驗證修復後此行為不變
2. **Normal Message Flow Preservation**: 觀察一般訊息的發送和接收流程，撰寫測試驗證修復後完全不受影響
3. **Other WebSocket Events Preservation**: 觀察其他 WebSocket 事件（typing indicators, read receipts）的處理，撰寫測試驗證修復後正常運作
4. **Successful Decryption Preservation**: 觀察接收方成功收到 re_encrypt_response 後的解密流程，撰寫測試驗證修復後行為一致

### Unit Tests

- 測試 MongoDB schema 的建立和 TTL index 設定
- 測試發送方離線時 re_encrypt_request 的持久化邏輯
- 測試發送方在線時 re_encrypt_request 的即時轉發邏輯
- 測試發送方上線時查詢和下發待處理請求的邏輯
- 測試成功下發後從資料庫刪除記錄的邏輯
- 測試接收方的指數退避重試策略
- 測試邊界情況（發送方在下發過程中斷線、資料庫寫入失敗等）

### Property-Based Tests

- 生成隨機的線上/離線狀態組合，驗證 re_encrypt_request 處理邏輯正確
- 生成隨機的訊息和使用者組合，驗證一般訊息流程不受影響
- 生成隨機的 WebSocket 事件序列，驗證所有事件類型正常處理
- 測試大量並發的 re_encrypt_request，驗證系統穩定性和資料一致性

### Integration Tests

- 測試完整流程：發送方離線 → 接收方請求重新加密 → 請求持久化 → 發送方上線 → 自動下發 → 發送方回應 → 接收方成功解密
- 測試多個待處理請求的場景：發送方離線期間收到多個 re_encrypt_request，上線後全部下發
- 測試 TTL 過期機制：驗證 7 天後請求自動從資料庫清除
- 測試網路不穩定情況：發送方頻繁斷線重連，驗證系統能正確處理
- 測試跨裝置場景：發送方在多個裝置上線，驗證請求只下發一次
