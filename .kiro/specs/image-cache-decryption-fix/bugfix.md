# Bugfix Requirements Document

## Introduction

此 bugfix 修復 Flutter 應用程式中圖片快取和 Link Preview 功能處理加密內容時的錯誤。當訊息內容（包含圖片 URL 或 Link Preview 的 imageUrl）尚未解密時，系統嘗試使用加密的 Base64 字串作為 URL 進行圖片下載和快取，導致「No host specified in URI」錯誤。此問題影響端對端加密（E2EE）訊息的圖片顯示和 Link Preview 功能。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN 訊息內容包含加密的圖片 URL（長 Base64 字串）且尚未解密 THEN 系統將加密字串傳遞給 `resolveFullUrl` 函數，該函數返回空字串並印出警告「⚠️ [resolveFullUrl] 收到未解密內容」

1.2 WHEN `resolveFullUrl` 返回空字串或無效 URL THEN `ImageCacheService.cacheImage()` 嘗試使用空字串或無效 URL 下載圖片，導致 DioException 並印出錯誤「❌ [ImageCache] 快取圖片失敗: DioException [unknown]: null」，根本原因為「Error: Invalid argument(s): No host specified in URI」

1.3 WHEN Link Preview 的 `imageUrl` 欄位包含加密內容（長 Base64 字串）THEN 系統嘗試使用加密字串作為圖片 URL，導致圖片無法載入

1.4 WHEN 訊息內容包含 URL 但內容尚未解密 THEN Link Preview 無法正確生成，因為 URL 提取發生在解密之前

### Expected Behavior (Correct)

2.1 WHEN 訊息內容包含加密的圖片 URL 或 Link Preview 資料 THEN 系統 SHALL 先完成訊息內容解密，再進行 URL 解析和圖片快取操作

2.2 WHEN `resolveFullUrl` 接收到空字串、null 或無效 URL THEN 系統 SHALL 返回空字串，且 `ImageCacheService` SHALL 不嘗試下載圖片

2.3 WHEN Link Preview 的 `imageUrl` 欄位為空字串或 null THEN 系統 SHALL 顯示預設的 fallback 圖示，不嘗試下載圖片

2.4 WHEN 訊息解密完成後包含 URL THEN 系統 SHALL 正確提取 URL 並生成 Link Preview

2.5 WHEN `ImageCacheService.cacheImage()` 接收到空字串或無效 URL THEN 系統 SHALL 提前返回 null，不執行 Dio 下載操作，避免拋出「No host specified in URI」錯誤

### Unchanged Behavior (Regression Prevention)

3.1 WHEN 訊息內容已解密且包含有效的圖片 URL THEN 系統 SHALL CONTINUE TO 正確下載並快取圖片

3.2 WHEN Link Preview 包含有效的 `imageUrl` THEN 系統 SHALL CONTINUE TO 正確顯示圖片縮圖

3.3 WHEN 訊息內容為明文（非加密）且包含 URL THEN 系統 SHALL CONTINUE TO 正確生成 Link Preview

3.4 WHEN `resolveFullUrl` 接收到完整 URL（http:// 或 https://）THEN 系統 SHALL CONTINUE TO 直接返回該 URL

3.5 WHEN `resolveFullUrl` 接收到相對路徑（/uploads/...）或 MongoDB ObjectID（24 個十六進制字符）THEN 系統 SHALL CONTINUE TO 正確拼接為完整 URL

3.6 WHEN 圖片快取超過大小限制（500MB）THEN 系統 SHALL CONTINUE TO 自動清理最舊的快取檔案

3.7 WHEN 訊息解密失敗且觸發 E2EE Auto-Resend 機制 THEN 系統 SHALL CONTINUE TO 正確處理重新加密流程
