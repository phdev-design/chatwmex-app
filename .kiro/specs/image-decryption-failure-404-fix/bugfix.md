# Bugfix Requirements Document

## Introduction

當 E2EE（端對端加密）圖片訊息解密失敗時，系統會將 `msg.content` 設定為純文字錯誤訊息（例如：'🔒 此訊息無法解密（金鑰已更新）'）。然而，`message_bubble.dart` 中的圖片處理邏輯僅檢查 `msg.type == MessageType.image`，並未驗證 `msg.content` 是否為有效的 URL，導致系統嘗試將解密失敗的文字訊息當作 URL 進行網路請求，產生 404 錯誤（例如：`http://127.0.0.1:8080/🔒 此訊息無法解密...`）。

此 bug 影響使用者體驗，在日誌中產生大量無意義的 404 錯誤，並可能導致不必要的網路請求。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN msg.type == MessageType.image AND msg.content 包含解密失敗文字（例如以 '🔒' 開頭）THEN 系統仍嘗試將 msg.content 作為 URL 傳遞給 CachedNetworkImageWidget

1.2 WHEN CachedNetworkImageWidget 接收到非 URL 的文字內容 THEN 系統發出無效的 HTTP 請求並產生 404 錯誤

1.3 WHEN 解密失敗的圖片訊息顯示時 THEN 使用者看到圖片載入錯誤圖示（broken_image），而非清楚的解密失敗提示

### Expected Behavior (Correct)

2.1 WHEN msg.type == MessageType.image AND msg.content 以 '🔒' 開頭 THEN 系統 SHALL 將其識別為解密失敗訊息，並渲染為文字氣泡或錯誤提示 Widget

2.2 WHEN 解密失敗訊息被識別 THEN 系統 SHALL NOT 調用 CachedNetworkImageWidget 或發起任何網路請求

2.3 WHEN 解密失敗的圖片訊息顯示時 THEN 使用者 SHALL 看到清楚的文字提示（例如：'🔒 此訊息無法解密（金鑰已更新）'），而非圖片載入錯誤

2.4 WHEN 渲染解密失敗訊息 THEN 系統 SHALL 套用與 MessageType.text 相同的文字氣泡樣式（包括背景顏色、邊距、文字顏色等）

2.5 WHEN 檢查解密失敗條件時 THEN 系統 SHOULD 優先使用已定義的常量或 helper method（例如檢查是否存在 Constants 或建立 extension method），避免在 UI 邏輯中硬編碼 '🔒' 字串

### Unchanged Behavior (Regression Prevention)

3.1 WHEN msg.type == MessageType.image AND msg.content 包含有效的圖片 URL THEN 系統 SHALL CONTINUE TO 使用 CachedNetworkImageWidget 正常載入並顯示圖片

3.2 WHEN msg.type == MessageType.image AND msg.content 為空字串 THEN 系統 SHALL CONTINUE TO 顯示現有的錯誤處理（broken_image 圖示）

3.3 WHEN msg.type 為其他類型（text, voice, file 等）THEN 系統 SHALL CONTINUE TO 按照現有邏輯正常處理

3.4 WHEN 圖片訊息載入失敗（網路錯誤、檔案不存在等）THEN 系統 SHALL CONTINUE TO 顯示 errorWidget（broken_image 圖示）
