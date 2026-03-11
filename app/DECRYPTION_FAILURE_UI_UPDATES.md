# 解密失敗 UI 更新說明

## 概述

為了改善用戶體驗，當媒體內容（圖片、影片、文件、連結）解密失敗時，不再顯示空白或導致應用崩潰，而是顯示友好的錯誤佔位符。

## 更新的檔案

### 1. `media_tab_content.dart` - 媒體標籤頁
- **新增元件**: `_DecryptionFailedTile`
- **檢測邏輯**: 當 `resolveFullUrl(message.content)` 返回空字串時，顯示解密失敗佔位符
- **UI 設計**:
  - 使用 `surfaceContainerHighest` 作為背景色
  - 紅色邊框 (`error` 顏色，透明度 0.2)
  - 中央顯示鎖頭圖示 (`Icons.lock_outline`)
  - 下方顯示「檔案未能解密」文字
  - 完美填滿 GridView 格子

### 2. `docs_tab_content.dart` - 文件標籤頁
- **新增元件**: `_DecryptionFailedCard`
- **檢測邏輯**: 在渲染每個文件項目前，先檢查 `resolveFullUrl(msg.content)` 是否為空
- **UI 設計**:
  - 卡片式設計，與正常文件項目大小一致
  - 左側：鎖頭圖示，紅色背景
  - 中間：「檔案未能解密」標題 + 「無法讀取此文件」副標題
  - 右側：錯誤圖示 (`Icons.error_outline`)
  - 使用 12px 圓角，與其他卡片一致

### 3. `links_tab_content.dart` - 連結標籤頁
- **新增元件**: `_DecryptionFailedCard`
- **檢測邏輯**: 
  - 檢查 URL 提取是否失敗
  - 檢測加密內容特徵（長度 >= 40 且包含 Base64 字符）但無法解密的情況
- **UI 設計**:
  - 卡片式設計，與正常連結項目大小一致
  - 左側：鎖頭圖示，紅色背景
  - 中間：「連結未能解密」標題 + 「無法讀取此連結」副標題
  - 右側：錯誤圖示 (`Icons.error_outline`)

## 設計原則

### 顏色方案
- **背景**: `cs.surfaceContainerHighest.withValues(alpha: 0.5)` - 柔和的灰色
- **邊框**: `cs.error.withValues(alpha: 0.2)` - 淡紅色邊框
- **圖示**: `cs.error.withValues(alpha: 0.6)` - 半透明紅色
- **文字**: `cs.onSurface.withValues(alpha: 0.5-0.7)` - 次要文字顏色

### 圖示選擇
- **主圖示**: `Icons.lock_outline` - 表示加密/解密問題
- **輔助圖示**: `Icons.error_outline` - 表示錯誤狀態

### 文字內容
- **媒體標籤**: 「檔案未能解密」
- **文件標籤**: 「檔案未能解密」+ 「無法讀取此文件」
- **連結標籤**: 「連結未能解密」+ 「無法讀取此連結」

## 技術實現

### 解密失敗檢測
所有三個標籤頁都使用相同的檢測邏輯：
```dart
final url = resolveFullUrl(message.content);
if (url.isEmpty) {
  // 顯示解密失敗佔位符
}
```

### 佔位符尺寸
- **GridView (媒體)**: 自動填滿格子，與正常圖片大小一致
- **ListView (文件/連結)**: 使用相同的 padding 和 margin，保持列表一致性

## 用戶體驗改善

1. **視覺一致性**: 解密失敗的項目不會破壞整體佈局
2. **清晰反饋**: 用戶明確知道這是解密問題，而非網路或其他錯誤
3. **無崩潰**: 應用不會因為解密失敗而崩潰或顯示空白
4. **專業外觀**: 錯誤狀態的設計與整體 UI 風格保持一致

## 測試建議

1. 測試加密內容無法解密的情況
2. 測試混合內容（部分成功、部分失敗）的顯示
3. 測試深色/淺色主題下的顯示效果
4. 測試不同螢幕尺寸下的佈局

## 相關檔案

- `app/lib/features/chat/ui/widgets/media_tab_content.dart`
- `app/lib/features/chat/ui/widgets/docs_tab_content.dart`
- `app/lib/features/chat/ui/widgets/links_tab_content.dart`
- `app/lib/features/chat/utils/chat_url_utils.dart` (解密邏輯)
- `app/lib/features/chat/providers/room_media_provider.dart` (ECDH 解密)
