# Bugfix Requirements Document

## Introduction

E2EE Auto-Resend 機制在每次 hot restart 或 WebSocket 重連時，會重複發送 re_encrypt_request 給同樣的約 30 條訊息，且每條訊息會被發送兩輪（出現兩次）。更嚴重的是，即使訊息狀態已更新為 MessageStatus.read，系統仍然嘗試發送請求，導致 log 中出現 "Message is not in decryptingRetry status: MessageStatus.read" 錯誤訊息。

此問題造成：
- WebSocket 連線被大量重複請求污染
- 增加後端伺服器不必要的負擔
- 用戶體驗受影響（每次重連都觸發大量無效請求）
- 資料庫狀態與記憶體狀態不一致

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN app 執行 hot restart 或 WebSocket 重連 THEN 系統從 LocalDB 載入所有 status 為 decryptingRetry 的訊息並發送 re_encrypt_request，即使這些訊息在記憶體中的狀態已是 MessageStatus.read

1.2 WHEN E2EE auto-resend 初始化邏輯被觸發 THEN 同一個 WebSocket session 中會執行兩次初始化（可能來自 initState 和 onReconnect），導致每條訊息的 re_encrypt_request 被發送兩輪

1.3 WHEN 訊息成功解密並更新為 MessageStatus.read THEN LocalDB 中該訊息的 status 欄位仍然保持 decryptingRetry 狀態，導致下次重啟時再次被載入並重試

1.4 WHEN 系統嘗試對已經是 MessageStatus.read 的訊息發送 re_encrypt_request THEN log 中顯示錯誤訊息 "Message is not in decryptingRetry status: MessageStatus.read"，但請求仍然被發送

### Expected Behavior (Correct)

2.1 WHEN app 執行 hot restart 或 WebSocket 重連 THEN 系統 SHALL 在發送 re_encrypt_request 前，先檢查訊息在記憶體中的當前狀態，若狀態為 read/delivered/sent 則跳過該訊息

2.2 WHEN E2EE auto-resend 初始化邏輯被觸發 THEN 系統 SHALL 確保初始化邏輯在同一個 session 中只執行一次（使用 _isInitialized flag 或類似機制）

2.3 WHEN 訊息成功解密並更新為 MessageStatus.read THEN 系統 SHALL 立即將 LocalDB 中該訊息的 status 從 decryptingRetry 同步更新為實際狀態（read/delivered），確保資料庫與記憶體狀態一致

2.4 WHEN 系統檢測到訊息狀態已不是 decryptingRetry THEN 系統 SHALL 不發送 re_encrypt_request，並在 log 中記錄跳過原因

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 訊息狀態確實為 MessageStatus.decryptingRetry 且尚未達到重試上限 THEN 系統 SHALL CONTINUE TO 正常發送 re_encrypt_request

3.2 WHEN 訊息首次解密失敗 THEN 系統 SHALL CONTINUE TO 將訊息標記為 decryptingRetry 並發送 re_encrypt_request

3.3 WHEN 發送方收到 re_encrypt_request THEN 系統 SHALL CONTINUE TO 從 LocalDB 取得原始訊息並重新加密後回傳 re_encrypt_response

3.4 WHEN 接收方收到 re_encrypt_response THEN 系統 SHALL CONTINUE TO 嘗試重新解密並更新訊息狀態

3.5 WHEN 訊息重試次數達到上限（>= 2 次）THEN 系統 SHALL CONTINUE TO 將訊息標記為 MessageStatus.failed 並停止重試

