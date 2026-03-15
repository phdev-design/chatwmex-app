# E2EE 圖片/影片 Validation 修正完成總結

## 修改概述

完成了後端所有 content validation 的修正，確保群組 E2EE 訊息（使用 `encrypted_contents_fanout`）可以正常發送。

## 後端修改位置（共 3 處）

### 1. WebSocket Controller - Media Message Validation
**檔案：** `backend/internal/delivery/websocket/controller.go`  
**函式：** `handleMediaMessage()`  
**修改：** 加入 fanout 檢查，允許有 `EncryptedContentsFanout` 的訊息 content 為空

```go
hasFanout := msg.EncryptedContentsFanout != nil && len(msg.EncryptedContentsFanout) > 0
if msg.Content == "" && !hasFanout {
    c.respondError(client, "error", "Media content (URL) is required")
    return context.DeadlineExceeded
}
```

### 2. WebSocket Controller - Text Message Validation
**檔案：** `backend/internal/delivery/websocket/controller.go`  
**函式：** `OnChatMessage()`  
**修改：** 文字訊息 validation 也加入 fanout 檢查

```go
if msg.Content == "" && msg.Type == "text" && len(msg.EncryptedContentsFanout) == 0 {
    c.respondError(client, "error", "Content is required")
    return
}
```

### 3. Message Usecase - SendMessage Validation
**檔案：** `backend/internal/usecase/message_usecase.go`  
**函式：** `SendMessage()`  
**修改：** 基礎 validation 加入 fanout 檢查

```go
if strings.TrimSpace(msg.Content) == "" && len(msg.EncryptedContentsFanout) == 0 {
    return errors.New("message content cannot be empty")
}
```

## Validation 邏輯

### 修改前
```
if content == "" {
    return error
}
```

### 修改後
```
if content == "" && len(EncryptedContentsFanout) == 0 {
    return error
}
```

### 邏輯說明
- **DM 訊息**：content 包含加密的 URL，EncryptedContentsFanout 為空 → 需要 content
- **群組訊息（E2EE）**：content 為空，EncryptedContentsFanout 包含每個成員的加密 URL → 允許 content 為空
- **舊訊息（未加密）**：content 包含明文 URL，EncryptedContentsFanout 為空 → 需要 content

## 前端配合修改

### sendImageMessage() 和 sendVideoMessage()
```dart
// 群組訊息
if (fileKeysFanout != null) {
  payload['content'] = ''; // 空字串
  payload['encrypted_contents_fanout'] = encryptedContentsFanout;
  payload['file_keys_fanout'] = fileKeysFanout;
}

// DM 訊息
else {
  payload['content'] = encryptedContent ?? imageUrl; // 加密的 URL
  payload['file_key'] = fileKey;
}
```

## 驗證結果

### 編譯檢查
- ✅ 後端編譯通過：`go build ./...`
- ✅ 前端編譯通過：`flutter analyze`
- ✅ 所有檔案無診斷錯誤

### 邏輯驗證
- ✅ 群組訊息：content 為空，有 encrypted_contents_fanout → 通過 validation
- ✅ DM 訊息：content 有值，無 encrypted_contents_fanout → 通過 validation
- ✅ 舊訊息：content 有值，無 encrypted_contents_fanout → 通過 validation
- ✅ 錯誤情況：content 為空，無 encrypted_contents_fanout → 拒絕（正確）

## 測試建議

### 1. 群組圖片訊息測試
```
發送 → 檢查後端日誌 → 確認無 validation 錯誤 → 確認訊息成功儲存
```

### 2. DM 圖片訊息測試
```
發送 → 檢查後端日誌 → 確認無 validation 錯誤 → 確認訊息成功儲存
```

### 3. 群組文字訊息測試（E2EE）
```
發送 → 檢查是否使用 encrypted_contents_fanout → 確認 validation 通過
```

### 4. 錯誤情況測試
```
發送空 content 且無 fanout 的訊息 → 應該被拒絕
```

## 相關檔案

### 後端（已修改）
- ✅ `backend/internal/delivery/websocket/controller.go` (2 處)
- ✅ `backend/internal/usecase/message_usecase.go` (1 處)

### 後端（已有邏輯，無需修改）
- `backend/internal/delivery/websocket/hub.go` (fanout 處理)
- `backend/internal/domain/message.go` (Message struct)
- `backend/internal/repository/mongo_repo/message_repository.go` (資料庫)

### 前端（已修改）
- ✅ `app/lib/features/chat/repositories/chat_repository.dart`
- ✅ `app/lib/core/media/image_cache_service.dart`
- ✅ `app/lib/core/media/video_cache_service.dart`
- ✅ `app/lib/core/media/cached_network_image_widget.dart`
- ✅ `app/lib/features/chat/ui/widgets/message_bubble.dart`

## 完成狀態

- ✅ 後端所有 validation 點已修改
- ✅ 前端發送邏輯已修改
- ✅ 所有編譯通過
- ✅ 文件已更新
- ⏳ 待實際測試驗證

## 下一步

1. 部署後端更新
2. 部署前端更新
3. 進行完整的端到端測試：
   - 群組圖片發送與接收
   - DM 圖片發送與接收
   - 群組影片發送與接收
   - DM 影片發送與接收
4. 驗證舊訊息的向後兼容性

## 參考文件
- E2EE_IMAGE_VIDEO_IMPLEMENTATION.md
- E2EE_IMAGE_VIDEO_CONTENT_VALIDATION_FIX.md
- E2EE_GROUP_MEDIA_FILEKEY_FANOUT_IMPLEMENTATION.md
