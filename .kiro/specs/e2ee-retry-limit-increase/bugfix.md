# Bugfix Requirements Document

## Introduction

當訊息解密失敗時，系統在重試 2 次後就會將訊息標記為永久失敗。這個限制過於嚴格，因為發送方可能只是短暫離線（例如網路不穩定、切換 WiFi），導致接收方過早放棄解密，即使發送方很快就會重新上線。此 bug 影響端對端加密訊息的可靠性，造成用戶體驗不佳。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN decrypt_retry_count 達到 2 次 THEN 系統將訊息標記為永久失敗，不再嘗試解密

1.2 WHEN 訊息被標記為永久失敗 THEN 系統不提供任何手動重試的機制

1.3 WHEN 發送方短暫離線（例如切換 WiFi、網路不穩定）導致解密失敗 2 次 THEN 系統永久放棄解密，即使發送方隨後上線

### Expected Behavior (Correct)

2.1 WHEN decrypt_retry_count 達到 10 次 THEN 系統才將訊息標記為失敗（而非永久失敗）

2.2 WHEN 訊息達到重試上限後 THEN 系統 SHALL 顯示提示訊息「🔒 無法解密（可點擊重試）」，讓用戶知道可以手動重試

2.3 WHEN 用戶點擊手動重試 THEN 系統 SHALL 提供 retryDecryptMessage(messageId) 方法重新嘗試解密

2.4 WHEN 手動重試被觸發 THEN 系統 SHALL 重置重試計數器並重新開始解密流程

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 解密成功（重試次數小於上限）THEN 系統 SHALL CONTINUE TO 正常顯示解密後的訊息內容

3.2 WHEN 解密失敗但未達重試上限 THEN 系統 SHALL CONTINUE TO 自動重試解密

3.3 WHEN 訊息解密過程中 THEN 系統 SHALL CONTINUE TO 顯示「🔒 解密中...」的狀態訊息

3.4 WHEN 重試計數器遞增 THEN 系統 SHALL CONTINUE TO 正確記錄和更新 decrypt_retry_count 值
