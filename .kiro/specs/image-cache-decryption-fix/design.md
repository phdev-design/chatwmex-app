# Image Cache Decryption Fix Bugfix Design

## Overview

此 bugfix 修復 Flutter 應用程式中圖片快取和 Link Preview 功能處理加密內容時的錯誤。當訊息內容（包含圖片 URL 或 Link Preview 的 imageUrl）尚未解密時，系統嘗試使用加密的 Base64 字串作為 URL 進行圖片下載和快取，導致「No host specified in URI」錯誤。修復策略包括：(1) 在 `ImageCacheService.cacheImage()` 中添加 URL 驗證，提前返回 null 避免 DioException；(2) 確保訊息解密流程在 URL 解析和圖片快取之前完成；(3) 在 Link Preview 渲染時處理空 imageUrl 的情況。

## Glossary

- **Bug_Condition (C)**: 當加密的 Base64 字串（長度 ≥40 且包含 +/= 字符）被傳遞給 `resolveFullUrl` 或 `ImageCacheService.cacheImage()` 時觸發的條件
- **Property (P)**: 系統應該在解密完成後才進行 URL 解析和圖片快取，且對於無效 URL 應該優雅地處理而不拋出異常
- **Preservation**: 已解密訊息的圖片快取、Link Preview 顯示、URL 解析邏輯必須保持不變
- **ImageCacheService**: 位於 `app/lib/core/media/image_cache_service.dart` 的服務，負責管理圖片的本地快取，支援 E2EE 加密圖片
- **resolveFullUrl**: 位於 `app/lib/features/chat/utils/chat_url_utils.dart` 的函數，將路徑或 ID 轉換為完整 URL，對於長 Base64 字串返回空字串
- **LinkPreview**: 位於 `app/lib/models/message.dart` 的模型類，包含 url、title、description 和 imageUrl 欄位
- **cacheImage**: `ImageCacheService` 的方法，從 URL 下載圖片並儲存到本地快取，或直接儲存提供的 imageData

## Bug Details

### Bug Condition

當訊息內容包含加密的圖片 URL 或 Link Preview 資料（長 Base64 字串）且尚未解密時，系統將加密字串傳遞給 `resolveFullUrl` 函數。`resolveFullUrl` 檢測到長 Base64 字串（≥40 字符且包含 +/= 字符）後返回空字串並印出警告。然而，`ImageCacheService.cacheImage()` 沒有驗證 URL 是否為空或無效，直接嘗試使用 Dio 下載，導致「No host specified in URI」錯誤。

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type String (URL or content)
  OUTPUT: boolean
  
  isEncryptedBase64 := (input.length >= 40) 
                       AND (input.contains('+') OR input.contains('/') OR input.contains('='))
  
  isEmptyOrNull := (input == null OR input.isEmpty)
  
  isInvalidUrl := NOT (input.startsWith('http://') OR input.startsWith('https://'))
                  AND NOT (input.startsWith('/uploads/'))
                  AND NOT (input.length == 24 AND input.matches('[a-f0-9]{24}'))
  
  RETURN (isEncryptedBase64 OR isEmptyOrNull OR isInvalidUrl)
         AND cacheImageAttempted(input)
END FUNCTION
```

### Examples

- 訊息內容為 `"U2FsdGVkX1+abc123...xyz789=="` (長 Base64 字串) → `resolveFullUrl` 返回空字串並印出「⚠️ [resolveFullUrl] 收到未解密內容」→ `ImageCacheService.cacheImage("")` 嘗試下載 → DioException: "No host specified in URI"
- Link Preview 的 `imageUrl` 為 `"U2FsdGVkX1+def456...uvw012=="` → 系統嘗試使用加密字串作為圖片 URL → 圖片無法載入
- 訊息內容為空字串 `""` → `resolveFullUrl` 返回空字串 → `ImageCacheService.cacheImage("")` 嘗試下載 → DioException: "No host specified in URI"
- 訊息內容為 `"https://example.com/image.jpg"` (已解密的完整 URL) → `resolveFullUrl` 返回相同 URL → `ImageCacheService.cacheImage()` 成功下載 (正確行為)

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- 已解密訊息包含有效圖片 URL 時，系統必須繼續正確下載並快取圖片
- Link Preview 包含有效 imageUrl 時，系統必須繼續正確顯示圖片縮圖
- 訊息內容為明文（非加密）且包含 URL 時，系統必須繼續正確生成 Link Preview
- `resolveFullUrl` 接收到完整 URL (http:// 或 https://) 時，必須繼續直接返回該 URL
- `resolveFullUrl` 接收到相對路徑 (/uploads/...) 或 MongoDB ObjectID (24 個十六進制字符) 時，必須繼續正確拼接為完整 URL
- 圖片快取超過大小限制 (500MB) 時，系統必須繼續自動清理最舊的快取檔案
- 訊息解密失敗且觸發 E2EE Auto-Resend 機制時，系統必須繼續正確處理重新加密流程

**Scope:**
所有不涉及加密 Base64 字串或空/無效 URL 的輸入應該完全不受此修復影響。這包括：
- 已解密的完整 URL (http://, https://)
- 相對路徑 (/uploads/...)
- MongoDB ObjectID (24 個十六進制字符)
- 明文訊息中的 URL 提取和 Link Preview 生成

## Hypothesized Root Cause

基於 bug 描述和程式碼分析，最可能的問題是：

1. **缺少 URL 驗證**: `ImageCacheService.cacheImage()` 方法在 `imageData` 為 null 時，直接使用 `dio.download(url, filePath)` 下載圖片，沒有檢查 `url` 是否為空字串或無效 URL。當 `resolveFullUrl` 返回空字串時，Dio 嘗試解析空字串作為 URI，導致「No host specified in URI」錯誤。

2. **解密時機問題**: 訊息內容的解密可能發生在 URL 解析和圖片快取之後，導致加密的 Base64 字串被傳遞給 `resolveFullUrl` 和 `ImageCacheService`。雖然 `resolveFullUrl` 已經有檢測機制返回空字串，但下游的 `ImageCacheService` 沒有處理這種情況。

3. **Link Preview 的 imageUrl 處理**: Link Preview 的 `imageUrl` 欄位可能包含加密內容，但渲染邏輯沒有檢查 `imageUrl` 是否為空或無效，直接嘗試載入圖片。

4. **錯誤傳播**: `resolveFullUrl` 返回空字串是一種靜默失敗（只印出警告），但調用方（如 `ImageCacheService`）沒有檢查返回值，繼續執行導致更嚴重的錯誤（DioException）。

## Correctness Properties

Property 1: Bug Condition - URL Validation Before Caching

_For any_ input where the URL is empty, null, or invalid (isBugCondition returns true), the fixed ImageCacheService.cacheImage() function SHALL return null immediately without attempting to download, preventing "No host specified in URI" errors.

**Validates: Requirements 2.2, 2.5**

Property 2: Preservation - Valid URL Caching Behavior

_For any_ input where the URL is valid (complete URL, relative path, or MongoDB ObjectID) and isBugCondition returns false, the fixed ImageCacheService SHALL continue to download and cache images exactly as before, preserving all existing functionality including cache size management, expiry checking, and cleanup.

**Validates: Requirements 3.1, 3.2, 3.4, 3.5, 3.6**

## Fix Implementation

### Changes Required

假設我們的根本原因分析正確：

**File**: `app/lib/core/media/image_cache_service.dart`

**Function**: `cacheImage`

**Specific Changes**:
1. **添加 URL 驗證**: 在 `cacheImage` 方法開頭，檢查 `url` 參數是否為空字串或 null。如果是，立即返回 null 並印出警告訊息，避免調用 `dio.download()`。

2. **添加 URL 格式驗證**: 使用 `Uri.tryParse(url)` 檢查 URL 是否可以被解析。如果解析失敗或解析後的 URI 沒有 host，返回 null。

3. **改進錯誤訊息**: 將現有的通用錯誤訊息「❌ [ImageCache] 快取圖片失敗」改為更具體的訊息，區分「URL 無效」和「下載失敗」兩種情況。

**File**: `app/lib/features/chat/utils/chat_url_utils.dart`

**Function**: `resolveFullUrl`

**Specific Changes**:
4. **保持現有邏輯**: `resolveFullUrl` 已經正確檢測長 Base64 字串並返回空字串，不需要修改。此函數作為第一道防線，防止加密內容被當作 URL 使用。

**File**: Link Preview 渲染相關檔案（需要進一步確認具體位置）

**Specific Changes**:
5. **處理空 imageUrl**: 在渲染 Link Preview 時，檢查 `linkPreview.imageUrl` 是否為空或 null。如果是，顯示預設的 fallback 圖示，不嘗試載入圖片。

6. **使用 resolveFullUrl 驗證**: 在嘗試載入 Link Preview 圖片之前，先通過 `resolveFullUrl` 處理 `imageUrl`，確保只有有效 URL 才會被傳遞給圖片載入元件。

## Testing Strategy

### Validation Approach

測試策略遵循兩階段方法：首先，在未修復的程式碼上執行測試以展示 bug 的存在（探索性測試），然後驗證修復後的程式碼正確處理 bug 條件並保持現有行為不變。

### Exploratory Bug Condition Checking

**Goal**: 在實施修復之前，展示 bug 存在的反例。確認或反駁根本原因分析。如果反駁，我們需要重新假設。

**Test Plan**: 編寫測試模擬各種無效 URL 輸入（空字串、null、長 Base64 字串）傳遞給 `ImageCacheService.cacheImage()`，並斷言會拋出 DioException 或印出錯誤訊息。在未修復的程式碼上執行這些測試以觀察失敗並理解根本原因。

**Test Cases**:
1. **Empty String URL Test**: 調用 `cacheImage("")` (將在未修復的程式碼上失敗，拋出 DioException)
2. **Null URL Test**: 調用 `cacheImage(null)` (可能在未修復的程式碼上失敗)
3. **Encrypted Base64 URL Test**: 調用 `cacheImage("U2FsdGVkX1+abc123...xyz789==")` (將在未修復的程式碼上失敗)
4. **Link Preview with Encrypted imageUrl Test**: 創建包含加密 imageUrl 的 LinkPreview 並嘗試渲染 (將在未修復的程式碼上失敗或顯示錯誤)

**Expected Counterexamples**:
- DioException 被拋出，錯誤訊息為「No host specified in URI」
- 可能的原因：缺少 URL 驗證、直接調用 dio.download() 而不檢查 URL 有效性

### Fix Checking

**Goal**: 驗證對於所有 bug 條件成立的輸入，修復後的函數產生預期行為。

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := cacheImage_fixed(input)
  ASSERT result == null
  ASSERT NO DioException thrown
  ASSERT warning message printed
END FOR
```

### Preservation Checking

**Goal**: 驗證對於所有 bug 條件不成立的輸入，修復後的函數產生與原始函數相同的結果。

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT cacheImage_original(input) = cacheImage_fixed(input)
END FOR
```

**Testing Approach**: 建議使用 Property-based testing 進行保留檢查，因為：
- 它自動生成許多測試案例覆蓋輸入域
- 它捕獲手動單元測試可能遺漏的邊緣案例
- 它提供強有力的保證，確保所有非 bug 輸入的行為保持不變

**Test Plan**: 首先在未修復的程式碼上觀察有效 URL 的行為（完整 URL、相對路徑、MongoDB ObjectID），然後編寫 property-based tests 捕獲該行為。

**Test Cases**:
1. **Complete URL Preservation**: 觀察 `cacheImage("https://example.com/image.jpg")` 在未修復程式碼上正確工作，然後編寫測試驗證修復後繼續工作
2. **Relative Path Preservation**: 觀察 `cacheImage("/uploads/images/abc123.jpg")` 在未修復程式碼上正確工作，然後編寫測試驗證修復後繼續工作
3. **MongoDB ObjectID Preservation**: 觀察 `cacheImage("507f1f77bcf86cd799439011")` 在未修復程式碼上正確工作，然後編寫測試驗證修復後繼續工作
4. **Cache Cleanup Preservation**: 驗證快取大小超過 500MB 時，清理邏輯繼續正確工作

### Unit Tests

- 測試 `cacheImage` 對空字串、null、無效 URL 的處理
- 測試 `cacheImage` 對有效 URL（完整 URL、相對路徑、MongoDB ObjectID）的處理
- 測試 Link Preview 渲染時對空 imageUrl 的處理
- 測試 `resolveFullUrl` 對長 Base64 字串的檢測（已存在，確保不被破壞）

### Property-Based Tests

- 生成隨機的有效 URL（完整 URL、相對路徑、MongoDB ObjectID）並驗證 `cacheImage` 正確下載和快取
- 生成隨機的無效 URL（空字串、長 Base64 字串、無 host 的 URL）並驗證 `cacheImage` 返回 null 且不拋出異常
- 生成隨機的訊息內容（包含加密和明文）並驗證 Link Preview 生成邏輯正確處理

### Integration Tests

- 測試完整的訊息解密流程，確保解密在 URL 解析和圖片快取之前完成
- 測試 E2EE 訊息的圖片顯示流程，從接收加密訊息到顯示解密後的圖片
- 測試 Link Preview 生成流程，從接收包含 URL 的訊息到顯示 Link Preview
- 測試快取清理流程，驗證超過大小限制時自動清理最舊的快取檔案
