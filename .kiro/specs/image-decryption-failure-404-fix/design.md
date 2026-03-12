# Image Decryption Failure 404 Fix - Bugfix Design

## Overview

當 E2EE 圖片訊息解密失敗時，系統將 `msg.content` 設定為錯誤文字（如 '🔒 此訊息無法解密（金鑰已更新）'），但 `message_bubble.dart` 未驗證內容是否為有效 URL，導致將錯誤文字當作 URL 發送網路請求，產生 404 錯誤。

修復策略：在渲染圖片訊息前，檢查 `msg.content` 是否為解密失敗文字（以 '🔒' 開頭），若是則渲染為文字氣泡，避免無效的網路請求。

## Glossary

- **Bug_Condition (C)**: 當 `msg.type == MessageType.image` 且 `msg.content` 包含解密失敗文字（以 '🔒' 開頭）而非有效 URL
- **Property (P)**: 解密失敗的圖片訊息應渲染為文字氣泡，不發起網路請求，並顯示清楚的錯誤提示
- **Preservation**: 有效圖片 URL 的正常載入、其他訊息類型的處理、以及真實圖片載入錯誤的處理必須保持不變
- **message_bubble.dart**: 位於 `lib/widgets/message_bubble.dart` 的 Widget，負責根據 `msg.type` 渲染不同類型的訊息氣泡
- **CachedNetworkImageWidget**: 用於載入和快取網路圖片的 Widget
- **MessageType.image**: 表示訊息類型為圖片的列舉值
- **msg.content**: 訊息內容欄位，對於圖片訊息通常包含圖片 URL，但解密失敗時包含錯誤文字

## Bug Details

### Bug Condition

當圖片訊息解密失敗時，系統將 `msg.content` 設定為錯誤文字，但 `message_bubble.dart` 的圖片處理邏輯僅檢查 `msg.type`，未驗證 `msg.content` 是否為有效 URL，導致將錯誤文字當作 URL 傳遞給 `CachedNetworkImageWidget`。

**Formal Specification:**
```
FUNCTION isBugCondition(msg)
  INPUT: msg of type Message
  OUTPUT: boolean
  
  RETURN msg.type == MessageType.image
         AND msg.content IS NOT NULL
         AND msg.content STARTS WITH '🔒'
         AND NOT isValidImageUrl(msg.content)
END FUNCTION
```

### Examples

- **Example 1**: `msg.type = MessageType.image`, `msg.content = '🔒 此訊息無法解密（金鑰已更新）'`
  - **Expected**: 渲染為文字氣泡，顯示 '🔒 此訊息無法解密（金鑰已更新）'
  - **Actual**: 嘗試載入 URL `http://127.0.0.1:8080/🔒 此訊息無法解密...`，產生 404 錯誤


- **Example 2**: `msg.type = MessageType.image`, `msg.content = '🔒 解密失敗'`
  - **Expected**: 渲染為文字氣泡，顯示 '🔒 解密失敗'
  - **Actual**: 嘗試載入無效 URL，產生網路錯誤

- **Example 3**: `msg.type = MessageType.image`, `msg.content = 'https://example.com/image.jpg'`
  - **Expected**: 正常載入並顯示圖片
  - **Actual**: 正常載入並顯示圖片（此為正常情況，不是 bug）

- **Edge Case**: `msg.type = MessageType.image`, `msg.content = ''`
  - **Expected**: 顯示 broken_image 錯誤圖示（現有行為）
  - **Actual**: 顯示 broken_image 錯誤圖示（正常）

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- 有效圖片 URL（如 `https://example.com/image.jpg`）必須繼續使用 `CachedNetworkImageWidget` 正常載入
- 其他訊息類型（text, voice, file 等）的渲染邏輯必須保持不變
- 真實的圖片載入錯誤（網路錯誤、檔案不存在）必須繼續顯示 `errorWidget`（broken_image 圖示）
- 空字串 `msg.content` 的處理必須保持現有行為

**Scope:**
所有不涉及「`msg.type == MessageType.image` 且 `msg.content` 以 '🔒' 開頭」的輸入都應完全不受此修復影響。這包括：
- 有效的圖片 URL 訊息
- 其他類型的訊息（文字、語音、檔案等）
- 真實的圖片載入失敗情況
- 空內容的圖片訊息

## Hypothesized Root Cause

基於 bug 描述，最可能的問題是：

1. **缺少內容驗證**: `message_bubble.dart` 中的圖片處理邏輯僅檢查 `msg.type == MessageType.image`，未驗證 `msg.content` 是否為有效的 URL 或是否為解密失敗文字

2. **類型與內容不一致**: 當解密失敗時，系統保留 `msg.type = MessageType.image`，但將 `msg.content` 改為錯誤文字，造成類型與內容語義不一致

3. **缺少早期檢測**: 在調用 `CachedNetworkImageWidget` 之前，沒有檢查 `msg.content` 是否以 '🔒' 開頭或是否符合 URL 格式

4. **錯誤處理不足**: 現有的 `errorWidget` 僅處理網路載入失敗，無法處理「內容本身就不是 URL」的情況

## Correctness Properties

Property 1: Bug Condition - Decryption Failure Messages Render as Text

_For any_ message where `msg.type == MessageType.image` and `msg.content` starts with '🔒' (indicating decryption failure), the fixed rendering logic SHALL display the content as a text bubble (similar to `MessageType.text` styling) without invoking `CachedNetworkImageWidget` or making any network requests.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

Property 2: Preservation - Valid Image URLs Continue to Load

_For any_ message where `msg.type == MessageType.image` and `msg.content` does NOT start with '🔒' (valid image URLs or other content), the fixed code SHALL produce exactly the same behavior as the original code, preserving normal image loading via `CachedNetworkImageWidget` and existing error handling for network failures.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**


## Fix Implementation

### Changes Required

假設我們的根本原因分析正確：

**File**: `lib/widgets/message_bubble.dart`

**Function**: 圖片訊息渲染邏輯（可能在 `build` 方法或專門的圖片處理方法中）

**Specific Changes**:
1. **添加解密失敗檢測**: 在處理 `MessageType.image` 時，首先檢查 `msg.content` 是否以 '🔒' 開頭
   - 實作方式：`if (msg.type == MessageType.image && msg.content?.startsWith('🔒') == true)`
   - 建議：考慮建立 extension method 如 `extension on Message { bool get isDecryptionFailure => ... }`

2. **條件分支渲染**: 當檢測到解密失敗時，使用文字氣泡渲染而非圖片 Widget
   - 返回與 `MessageType.text` 相同的 Widget 結構
   - 確保套用相同的樣式（背景顏色、邊距、文字顏色等）

3. **保留原有圖片邏輯**: 當 `msg.content` 不是解密失敗文字時，繼續使用 `CachedNetworkImageWidget`
   - 確保所有現有的圖片載入邏輯、錯誤處理、快取機制都不受影響

4. **避免硬編碼**: 考慮將 '🔒' 字串定義為常量或使用已存在的常量
   - 檢查是否有 `Constants` 類別或類似的配置檔案
   - 如果不存在，可以在檔案頂部定義 `const String _decryptionFailurePrefix = '🔒';`

5. **測試邊界情況**: 確保處理 `msg.content` 為 null 或空字串的情況
   - 使用安全導航運算子 `?.` 避免 null 錯誤
   - 空字串應繼續現有的錯誤處理流程

## Testing Strategy

### Validation Approach

測試策略採用兩階段方法：首先在未修復的程式碼上展示 bug 的反例，然後驗證修復後的程式碼正確運作且保留現有行為。

### Exploratory Bug Condition Checking

**Goal**: 在實作修復前，在未修復的程式碼上展示 bug 的反例。確認或反駁根本原因分析。如果反駁，需要重新假設。

**Test Plan**: 撰寫測試模擬解密失敗的圖片訊息（`msg.type = MessageType.image`, `msg.content = '🔒 ...'`），並斷言系統不應調用網路請求或 `CachedNetworkImageWidget`。在未修復的程式碼上執行這些測試以觀察失敗並理解根本原因。

**Test Cases**:
1. **Decryption Failure Text Test**: 建立 `msg.content = '🔒 此訊息無法解密（金鑰已更新）'` 的訊息，驗證是否嘗試網路請求（在未修復程式碼上會失敗）
2. **Lock Icon Prefix Test**: 建立 `msg.content = '🔒 解密失敗'` 的訊息，驗證渲染結果（在未修復程式碼上會顯示 broken_image）
3. **Widget Type Test**: 驗證解密失敗訊息應渲染為文字 Widget 而非圖片 Widget（在未修復程式碼上會失敗）
4. **Network Request Monitor**: 監控是否發出無效的網路請求（在未修復程式碼上會觀察到 404 錯誤）

**Expected Counterexamples**:
- 系統嘗試將 '🔒 此訊息無法解密...' 當作 URL 發送網路請求
- 可能原因：缺少內容驗證、類型與內容不一致、缺少早期檢測

### Fix Checking

**Goal**: 驗證對於所有符合 bug 條件的輸入，修復後的函數產生預期行為。

**Pseudocode:**
```
FOR ALL msg WHERE isBugCondition(msg) DO
  widget := renderMessage_fixed(msg)
  ASSERT widget is TextBubbleWidget (not ImageWidget)
  ASSERT msg.content is displayed as text
  ASSERT NO network request is made
  ASSERT widget styling matches MessageType.text
END FOR
```


### Preservation Checking

**Goal**: 驗證對於所有不符合 bug 條件的輸入，修復後的函數產生與原始函數相同的結果。

**Pseudocode:**
```
FOR ALL msg WHERE NOT isBugCondition(msg) DO
  ASSERT renderMessage_original(msg) = renderMessage_fixed(msg)
END FOR
```

**Testing Approach**: 建議使用 property-based testing 進行保留檢查，因為：
- 它自動生成許多測試案例覆蓋輸入域
- 它能捕捉手動單元測試可能遺漏的邊界情況
- 它提供強有力的保證，確保所有非 bug 輸入的行為保持不變

**Test Plan**: 首先在未修復的程式碼上觀察有效圖片 URL 和其他訊息類型的行為，然後撰寫 property-based tests 捕捉該行為。

**Test Cases**:
1. **Valid Image URL Preservation**: 在未修復程式碼上觀察 `msg.content = 'https://example.com/image.jpg'` 正常載入，然後驗證修復後繼續正常載入
2. **Other Message Types Preservation**: 驗證 `MessageType.text`, `MessageType.voice`, `MessageType.file` 等類型的渲染邏輯完全不受影響
3. **Empty Content Preservation**: 驗證 `msg.content = ''` 的圖片訊息繼續顯示現有的錯誤處理
4. **Network Error Preservation**: 驗證真實的圖片載入錯誤（如無效 URL `https://invalid.url/image.jpg`）繼續顯示 errorWidget

### Unit Tests

- 測試解密失敗訊息（以 '🔒' 開頭）渲染為文字氣泡
- 測試有效圖片 URL 繼續使用 `CachedNetworkImageWidget`
- 測試邊界情況（null content, 空字串, 只有 '🔒' 字元）
- 測試其他訊息類型不受影響
- 測試文字氣泡樣式與 `MessageType.text` 一致

### Property-Based Tests

- 生成隨機的解密失敗訊息（以 '🔒' 開頭的各種文字），驗證都渲染為文字氣泡且不發起網路請求
- 生成隨機的有效圖片 URL，驗證保留原有的圖片載入行為
- 生成隨機的訊息類型和內容組合，驗證非 bug 條件的訊息行為完全不變
- 測試大量訊息渲染場景，確保沒有效能退化或記憶體洩漏

### Integration Tests

- 測試完整的訊息流程：接收解密失敗的圖片訊息 → 渲染為文字氣泡 → 使用者看到清楚的錯誤提示
- 測試混合訊息列表：包含正常圖片、解密失敗圖片、文字訊息等，驗證所有訊息都正確渲染
- 測試日誌輸出：驗證修復後不再產生 404 錯誤日誌
- 測試網路監控：驗證解密失敗訊息不會觸發任何網路請求
