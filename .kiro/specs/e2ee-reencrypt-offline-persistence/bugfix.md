# Bugfix Requirements Document

## Introduction

在 E2EE（端對端加密）系統中，當接收方無法解密訊息時，需要向發送方請求重新加密（re_encrypt_request）。目前的實作使用純 WebSocket 即時訊息，不進行後端持久化。當發送方離線時，re_encrypt_request 會遺失，導致接收方在重試 2 次後永久標記失敗，訊息內容永久不可讀。

此 bug 嚴重影響使用者體驗，因為發送方暫時離線（網路不穩、關閉應用等常見情況）會導致訊息永久無法解密。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN 發送方離線且接收方發送 re_encrypt_request THEN 該請求石沉大海，後端不儲存任何記錄

1.2 WHEN 接收方重試 2 次後仍未收到 re_encrypt_response THEN 系統永久標記該訊息為解密失敗

1.3 WHEN 發送方稍後重新上線 THEN 系統不會自動下發先前遺失的 re_encrypt_request

1.4 WHEN 訊息被標記為永久解密失敗 THEN 接收方無法再次嘗試解密，訊息內容永久不可讀

### Expected Behavior (Correct)

2.1 WHEN 發送方離線且接收方發送 re_encrypt_request THEN 系統 SHALL 將該請求持久化至 MongoDB（包含 MessageID, SenderID, ReceiverID, RoomID, CreatedAt, ExpiresAt 欄位）

2.2 WHEN 發送方重新上線 THEN 系統 SHALL 自動查詢並下發所有待處理的 re_encrypt_request 給該發送方

2.3 WHEN re_encrypt_request 成功下發給發送方 THEN 系統 SHALL 從資料庫中刪除該請求記錄

2.4 WHEN 接收方無法解密訊息 THEN 系統 SHALL 允許持續重試（移除 2 次硬性上限），直到收到 re_encrypt_response 或請求過期

2.5 WHEN re_encrypt_request 在資料庫中存在超過 7 天 THEN 系統 SHALL 透過 TTL index 自動清除該過期記錄

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 發送方在線且接收方發送 re_encrypt_request THEN 系統 SHALL CONTINUE TO 直接透過 WebSocket 即時轉發該請求

3.2 WHEN 發送方收到 re_encrypt_request THEN 系統 SHALL CONTINUE TO 正常處理並回覆 re_encrypt_response

3.3 WHEN 接收方收到 re_encrypt_response THEN 系統 SHALL CONTINUE TO 成功解密訊息並更新 isDecrypted 狀態為 true

3.4 WHEN 使用者在聊天室中發送和接收一般訊息 THEN 系統 SHALL CONTINUE TO 正常運作，不受此修改影響

3.5 WHEN 系統處理其他類型的 WebSocket 事件（如 typing indicators, read receipts）THEN 系統 SHALL CONTINUE TO 正常運作
