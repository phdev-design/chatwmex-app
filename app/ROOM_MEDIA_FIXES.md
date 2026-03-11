# RoomMediaPage 修復說明

## 問題分析

### 1. MessageType 枚舉缺少類型
**問題**: `MessageType` 枚舉只有 `text, image, voice, video, file`，缺少 `link` 和 `document` 類型。
**影響**: 後端返回的 `link` 和 `document` 類型訊息被錯誤地映射為 `file` 或 `text`，導致無法正確顯示。

**修復**:
```dart
// 修改前
enum MessageType { text, image, voice, video, file }

// 修改後
enum MessageType { text, image, voice, video, file, link, document }
```

### 2. MessageType 解析邏輯不完整
**問題**: `_parseType()` 方法將 `document` 映射為 `file`，沒有獨立的 `link` 處理。
**影響**: Links 和 Docs 標籤無法正確識別訊息類型。

**修復**:
```dart
static MessageType _parseType(String? type) {
  switch (type) {
    case 'audio':
      return MessageType.voice;
    case 'image':
      return MessageType.image;
    case 'voice':
      return MessageType.voice;
    case 'video':
      return MessageType.video;
    case 'file':
      return MessageType.file;
    case 'document':
      return MessageType.document;  // ✅ 新增
    case 'link':
      return MessageType.link;      // ✅ 新增
    default:
      return MessageType.text;
  }
}
```

### 3. 解密邏輯改進
**問題**: 
- URL 檢查不夠嚴謹（只檢查 `startsWith('http')`，漏掉 `http://`）
- 錯誤日誌可能輸出過長內容

**修復**:
- 改進 URL 檢查邏輯，明確檢查 `http://`, `https://`, `/uploads/`
- 限制錯誤日誌輸出長度（最多 50 字元）
- 保留原有的 ECDH 解密邏輯（使用發送者公鑰是正確的）

### 4. 移除冗餘過濾
**問題**: `media_tab_content.dart` 在 UI 層再次過濾訊息類型。
**影響**: 造成雙重過濾，可能導致性能問題和邏輯混亂。

**修復**:
```dart
// 修改前
final mediaMessages = entry.value
    .where((m) => m.type == MessageType.image || m.type == MessageType.video)
    .toList();

// 修改後
final mediaMessages = entry.value;  // Provider 已經按 type 過濾
```

## 修復後的工作流程

### Media Tab
1. Provider 使用 `type: 'media'` 從後端獲取 image/video 訊息
2. `_decryptMediaContent()` 解密所有訊息的 content
3. UI 直接顯示，不再額外過濾

### Links Tab
1. Provider 使用 `type: 'link'` 從後端獲取 link 訊息
2. `_decryptMediaContent()` 解密 URL
3. `extractAllUrls()` 從 content 提取所有 URL 並顯示

### Docs Tab
1. Provider 使用 `type: 'doc'` 從後端獲取 document 訊息
2. `_decryptMediaContent()` 解密文件路徑
3. UI 顯示文件列表，支援 PDF 預覽

## E2EE 解密邏輯說明

當前使用的是 **ECDH (Elliptic Curve Diffie-Hellman)** 加密架構：

1. **加密方**: 使用接收者的公鑰 + 自己的私鑰 → 生成共享密鑰 → 加密內容
2. **解密方**: 使用發送者的公鑰 + 自己的私鑰 → 生成相同的共享密鑰 → 解密內容

因此，`_decryptMediaContent()` 使用發送者的公鑰是正確的。

## 測試建議

1. **測試 Media Tab**: 上傳圖片和影片，確認能正確顯示
2. **測試 Links Tab**: 發送包含 URL 的訊息，確認能提取並顯示
3. **測試 Docs Tab**: 上傳文件（PDF、Word 等），確認能正確顯示和打開
4. **測試 E2EE**: 在啟用端對端加密的聊天室中測試所有類型
5. **測試舊訊息**: 確認歷史訊息（可能未加密）仍能正常顯示

## 潛在問題排查

如果修復後仍有問題，檢查以下項目：

1. **後端 API**: 確認 `/api/rooms/{roomId}/resources?type=media|link|doc` 返回正確的訊息類型
2. **公鑰快取**: 確認 `publicKeyCacheService` 能正確獲取發送者公鑰
3. **URL 解析**: 檢查 `resolveFullUrl()` 是否正確處理相對路徑和絕對路徑
4. **加密狀態**: 確認 E2EE 是否在該聊天室啟用（可能需要檢查 `e2eeEnabledProvider`）

## 相關文件

- `app/lib/models/message.dart` - 訊息模型和類型定義
- `app/lib/features/chat/providers/room_media_provider.dart` - 媒體數據提供者
- `app/lib/features/chat/ui/widgets/media_tab_content.dart` - Media 標籤 UI
- `app/lib/features/chat/ui/widgets/links_tab_content.dart` - Links 標籤 UI
- `app/lib/features/chat/ui/widgets/docs_tab_content.dart` - Docs 標籤 UI
- `app/lib/core/crypto/crypto_service.dart` - E2EE 加密服務
