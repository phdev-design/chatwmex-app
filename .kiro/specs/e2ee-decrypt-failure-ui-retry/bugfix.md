# Bugfix Requirements Document

## Introduction

當訊息解密失敗時，UI 只顯示「🔒 無法解密」的純文字，沒有任何視覺提示或互動元素告知用戶可以重試。用戶不知道這個訊息是可以點擊重試的，導致體驗不佳且無法輕鬆恢復解密失敗的訊息。

此 bug 影響用戶在遇到解密失敗時的體驗，缺乏明確的操作指引和視覺反饋。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN 訊息解密失敗 THEN 系統只顯示「🔒 無法解密」的純文字，沒有視覺提示

1.2 WHEN 訊息解密失敗 THEN 系統不提供任何重試的互動元素或文字提示

1.3 WHEN 用戶點擊解密失敗的訊息 THEN 系統沒有任何反應或重試行為

1.4 WHEN 訊息正在重試解密 THEN 系統沒有顯示解密中的狀態或動畫

### Expected Behavior (Correct)

2.1 WHEN 訊息解密失敗 THEN 系統 SHALL 顯示橘色邊框的視覺提示

2.2 WHEN 訊息解密失敗 THEN 系統 SHALL 顯示「🔒 無法解密 點擊重試 ↺」的文字提示

2.3 WHEN 用戶點擊解密失敗的訊息 THEN 系統 SHALL 呼叫 chatRoomProvider.notifier.retryDecryptMessage(messageId) 並重新發送 re_encrypt_request

2.4 WHEN 訊息正在重試解密 THEN 系統 SHALL 顯示「⏳ 解密中…」的動畫狀態

2.5 WHEN 重試解密完成（成功或失敗）THEN 系統 SHALL 更新 UI 顯示對應的結果狀態

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 訊息解密成功 THEN 系統 SHALL CONTINUE TO 正常顯示解密後的訊息內容

3.2 WHEN 訊息正在首次解密中 THEN 系統 SHALL CONTINUE TO 顯示原有的解密中狀態

3.3 WHEN 訊息不需要解密（未加密訊息）THEN 系統 SHALL CONTINUE TO 正常顯示訊息內容

3.4 WHEN 用戶點擊非解密失敗的訊息 THEN 系統 SHALL CONTINUE TO 維持原有的點擊行為（如選擇、複製等）
