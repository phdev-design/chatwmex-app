# Bugfix Requirements Document

## Introduction

當發送方不在線時，接收方發送的 `re_encrypt_request` 會永久消失，導致接收方無法解密訊息。這是因為 `OnReEncryptRequest` 收到請求後直接呼叫 `hub.SendNotification(senderID, ...)` 轉發，若發送方不在線，`SendNotification` 會靜默失敗，請求永久消失。

此問題造成：
- 接收方永久無法解密訊息（即使發送方稍後上線）
- E2EE 自動重試機制失效（請求已發送但永遠不會被處理）
- 用戶體驗嚴重受損（訊息永久顯示為解密失敗狀態）
- 無法利用發送方上線的時機自動恢復解密

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN 接收方發送 re_encrypt_request 且發送方不在線 THEN hub.SendNotification 靜默失敗，請求永久消失，接收方永遠無法解密該訊息

1.2 WHEN 發送方稍後上線 THEN 系統不會重新發送之前丟失的 re_encrypt_request，導致接收方仍然無法解密訊息

1.3 WHEN OnReEncryptRequest 呼叫 hub.SendNotification THEN 方法沒有返回值，無法判斷轉發是否成功，也無法觸發持久化邏輯

### Expected Behavior (Correct)

2.1 WHEN 接收方發送 re_encrypt_request 且發送方不在線 THEN 系統 SHALL 將請求持久化到 MongoDB pending_reencrypt_requests collection，包含 message_id、sender_id、receiver_id、room_id、created_at 和 expires_at（7 天 TTL）

2.2 WHEN 發送方上線（WebSocket connect）THEN 系統 SHALL 自動從 MongoDB 拉取該用戶的所有 pending re_encrypt_request，並逐一轉發給已在線的發送方

2.3 WHEN OnReEncryptRequest 呼叫 hub.SendNotification THEN hub.SendNotification SHALL 返回 bool 值表示轉發是否成功（用戶是否在線），若返回 false 則觸發持久化邏輯

2.4 WHEN pending re_encrypt_request 成功轉發給發送方 THEN 系統 SHALL 從 MongoDB 中刪除該 pending 請求，避免重複處理

2.5 WHEN pending re_encrypt_request 在 MongoDB 中存在超過 7 天 THEN MongoDB TTL index SHALL 自動刪除該請求

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 接收方發送 re_encrypt_request 且發送方在線 THEN 系統 SHALL CONTINUE TO 即時轉發請求給發送方，不進行持久化

3.2 WHEN 發送方收到 re_encrypt_request THEN 系統 SHALL CONTINUE TO 從 LocalDB 取得原始訊息並重新加密後回傳 re_encrypt_response

3.3 WHEN 接收方收到 re_encrypt_response THEN 系統 SHALL CONTINUE TO 嘗試重新解密並更新訊息狀態

3.4 WHEN 同一個 message_id 的 re_encrypt_request 已經在 pending 狀態 THEN 系統 SHALL CONTINUE TO 避免重複插入（使用 unique index 或檢查邏輯）
