# Bugfix Requirements Document

## Introduction

本文件描述聊天應用程式中影響 E2EE（端到端加密）、WebSocket 連線穩定性以及 Flutter 前端編譯的多個關鍵問題。系統採用 Flutter 前端（Riverpod 狀態管理）、Golang 後端（Gorilla WebSocket、MongoDB/Redis），群組訊息使用 Fan-out 加密機制為每個成員單獨產生密文並透過 WebSocket 廣播。

這些問題導致：
- 群組訊息傳送時 WebSocket 連線中斷
- 前端解析訊息時崩潰
- Flutter 應用程式無法編譯
- E2EE 解密失敗後的不良使用者體驗
- 潛在的執行時期崩潰風險

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN 群組訊息使用 Fan-out E2EE 加密產生大於 8KB 的 JSON Payload THEN 後端 WebSocket 觸發 `read limit exceeded` 錯誤並斷開連線

1.2 WHEN 後端偵測到訊息包含 Link Preview THEN 後端強制覆寫 `msg.Type` 為 `"link"`，導致 Flutter 前端在 `Message.fromJson()` 解析列舉時拋出 `StateError` 崩潰

1.3 WHEN Flutter 編譯器遇到孤立的底線 `_` 符號 THEN 編譯失敗並顯示 `Undefined name '_'` 錯誤（影響檔案：`backup_manager.dart` line 103、`crypto_service.dart` line 225、`chat_room_provider.dart` line 617、`contact_info_page.dart` line 376-378）

1.4 WHEN 前端解密失敗發送 `re_encrypt_request` 且發送方離線超過 10 秒 THEN 訊息被標記為 `MessageStatus.failed` 永久失敗狀態

1.5 WHEN Flutter UI 元件在 `await` 非同步操作後使用 `BuildContext` THEN 可能在 widget 已卸載時存取 context 導致崩潰（影響檔案：`contact_info_page.dart`、`notification_service.dart`、`qr_scanner_page.dart`）

1.6 WHEN Flutter 程式碼使用 `Color.withOpacity()` 或不必要的 `import 'package:flutter/foundation.dart'` THEN 產生廢棄 API 警告和多餘引入

### Expected Behavior (Correct)

2.1 WHEN 群組訊息使用 Fan-out E2EE 加密產生大於 8KB 的 JSON Payload THEN 後端 WebSocket SHALL 成功接收並處理最大 1MB 的訊息而不中斷連線（`backend/internal/delivery/websocket/client.go` 的 `maxMessageSize` 設定為 `1048576`）

2.2 WHEN 後端偵測到訊息包含 Link Preview THEN 後端 SHALL 保持原有的 `msg.Type` 不變，不強制覆寫為 `"link"`（移除 `backend/internal/usecase/message_usecase.go` 中的強制設定邏輯）

2.3 WHEN Flutter 編譯器處理程式碼 THEN 所有孤立的底線 `_` 符號 SHALL 被移除或替換為有效的變數名稱，使編譯成功

2.4 WHEN 前端解密失敗發送 `re_encrypt_request` 且發送方離線或超時 THEN 訊息 SHALL 保持 `MessageStatus.decryptingRetry` 狀態並顯示「🔒 等待對方上線以重新解密...」，而非標記為永久失敗

2.5 WHEN Flutter UI 元件在 `await` 非同步操作後需要使用 `BuildContext` THEN 程式碼 SHALL 先檢查 `if (!context.mounted) return;` 以防止在 widget 已卸載時存取 context

2.6 WHEN Flutter 程式碼需要調整顏色透明度 THEN 使用 `.withValues(alpha: ...)` 取代 `Color.withOpacity()`，並移除不必要的 `import 'package:flutter/foundation.dart'`

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 群組訊息 Payload 小於 1MB THEN WebSocket 連線 SHALL CONTINUE TO 正常傳輸訊息

3.2 WHEN 訊息不包含 Link Preview THEN 後端 SHALL CONTINUE TO 正常處理訊息類型

3.3 WHEN Flutter 程式碼不包含語法錯誤 THEN 編譯過程 SHALL CONTINUE TO 成功完成

3.4 WHEN 前端解密成功 THEN 訊息 SHALL CONTINUE TO 正常顯示為 `MessageStatus.sent` 或其他正確狀態

3.5 WHEN Flutter UI 元件在同步操作中使用 `BuildContext` THEN 程式碼 SHALL CONTINUE TO 正常運作

3.6 WHEN Flutter 程式碼使用現代 API THEN 編譯 SHALL CONTINUE TO 不產生廢棄警告
