# E2EE 圖片/影片 Content Validation 修正

## 問題描述

在實作圖片與影片的 E2EE 加密功能時，發現群組訊息發送失敗，畫面底部出現錯誤：
```
"Media content (URL) is required"
```

## 根本原因

### 後端 Validation 邏輯
在 `backend/internal/delivery/websocket/controller.go` 的 `handleMediaMessage()` 函式中：
```go
if msg.Content == "" {
    c.respondError(client, "error", "Media content (URL) is required")
    return context.DeadlineExceeded
}
```

### 前端發送邏輯
對於群組訊息，使用 `encrypted_contents_fanout` 儲存每個成員的加密 URL：
- 每個成員的 URL 用該成員的公鑰加密
- 儲存在 `encrypted_contents_fanout[userId]` 中
- `content` 欄位為空（因為沒有單一的明文 URL）

### 衝突點
後端 validation 要求 `content` 不能為空，但群組 E2EE 訊息的 `content` 必須為空（使用 fanout）。

## 解決方案

### 方案選擇
採用 **方案 A**：修改後端 validation 邏輯，允許 fanout 訊息的 content 為空。

理由：
1. 符合 E2EE 架構設計（群組訊息使用 fanout）
2. 後端已有處理 `encrypted_contents_fanout` 的邏輯（在 hub.go 中）
3. 不需要在 payload 中重複傳送 content

### 後端修改位置

修改了三個地方的 validation 邏輯：

1. **WebSocket Controller - Media Message Validation**
2. **WebSocket Controller - Text Message Validation**
3. **Message Usecase - SendMessage Validation**

### 後端修改詳情

### 後端修改詳情

#### 1. WebSocket Controller - Media Message Validation

**檔案：** `backend/internal/delivery/websocket/controller.go`

**修改前：**
```go
func (c *SocketController) handleMediaMessage(client *Client, msg *domain.Message) error {
	if msg.Content == "" {
		c.respondError(client, "error", "Media content (URL) is required")
		return context.DeadlineExceeded
	}
	// ...
}
```

**修改後：**
```go
func (c *SocketController) handleMediaMessage(client *Client, msg *domain.Message) error {
	// 🔐 E2EE: 對於群組訊息，content 可能為空（使用 encrypted_contents_fanout）
	// 只有在非 fanout 模式下才檢查 content
	hasFanout := msg.EncryptedContentsFanout != nil && len(msg.EncryptedContentsFanout) > 0
	if msg.Content == "" && !hasFanout {
		c.respondError(client, "error", "Media content (URL) is required")
		return context.DeadlineExceeded
	}
	// ...
}
```

#### 2. WebSocket Controller - Text Message Validation

**檔案：** `backend/internal/delivery/websocket/controller.go`

**修改前：**
```go
// Validate common fields
if msg.Content == "" && msg.Type == "text" {
	c.respondError(client, "error", "Content is required")
	return
}
```

**修改後：**
```go
// Validate common fields
// 🔐 E2EE: 允許使用 EncryptedContentsFanout 的訊息 content 為空
if msg.Content == "" && msg.Type == "text" && len(msg.EncryptedContentsFanout) == 0 {
	c.respondError(client, "error", "Content is required")
	return
}
```

#### 3. Message Usecase - SendMessage Validation

**檔案：** `backend/internal/usecase/message_usecase.go`

**修改前：**
```go
// 1) Basic Validation
if strings.TrimSpace(msg.SenderID) == "" {
	return errors.New("sender ID cannot be empty")
}

if strings.TrimSpace(msg.Content) == "" {
	return errors.New("message content cannot be empty")
}
```

**修改後：**
```go
// 1) Basic Validation
if strings.TrimSpace(msg.SenderID) == "" {
	return errors.New("sender ID cannot be empty")
}

// 🔐 E2EE: 允許使用 EncryptedContentsFanout 的訊息 content 為空
// 群組訊息使用 fanout 時，每個成員的內容在 EncryptedContentsFanout 中
if strings.TrimSpace(msg.Content) == "" && len(msg.EncryptedContentsFanout) == 0 {
	return errors.New("message content cannot be empty")
}
```

### 前端修改

**檔案：** `app/lib/features/chat/repositories/chat_repository.dart`

#### sendImageMessage() 修改

**修改前：**
```dart
final payload = <String, dynamic>{
  'client_msg_id': clientMsgId,
  'type': 'image',
  'content': encryptedContent ?? imageUrl,  // ❌ 群組訊息會傳送原始 URL
  'room_id': roomId,
  'receiver_id': receiverId,
};

if (fileKeysFanout != null) {
  payload['file_keys_fanout'] = fileKeysFanout;
  payload['encrypted_contents_fanout'] = encryptedContentsFanout;
}
```

**修改後：**
```dart
final payload = <String, dynamic>{
  'client_msg_id': clientMsgId,
  'type': 'image',
  'room_id': roomId,
  'receiver_id': receiverId,
};

// 🔐 群組訊息：使用 fanout，content 留空
if (fileKeysFanout != null) {
  payload['file_keys_fanout'] = fileKeysFanout;
  payload['encrypted_contents_fanout'] = encryptedContentsFanout;
  payload['content'] = ''; // ✅ 空字串，後端允許 fanout 訊息的 content 為空
  debugPrint('[sendImageMessage] 🔐 Sending with fanout (content empty)');
} else {
  // DM：傳送加密的 content 和明文 fileKey
  payload['content'] = encryptedContent ?? imageUrl;
  payload['file_key'] = fileKey;
  debugPrint('[sendImageMessage] 📤 Sending DM with encrypted content');
}
```

#### sendVideoMessage() 修改
與 `sendImageMessage()` 相同的修改邏輯。

## 驗證結果

### 編譯檢查
- ✅ 後端編譯通過：`go build ./...`
- ✅ 前端編譯通過：`flutter analyze`
- ✅ 無診斷錯誤

### 修改位置總結
後端共修改了 3 個 validation 點：
1. ✅ `backend/internal/delivery/websocket/controller.go` - handleMediaMessage()
2. ✅ `backend/internal/delivery/websocket/controller.go` - OnChatMessage() 文字訊息檢查
3. ✅ `backend/internal/usecase/message_usecase.go` - SendMessage()

所有 validation 都加入了 fanout 例外判斷：
- 檢查 `EncryptedContentsFanout` 是否存在且非空
- 若存在，允許 `content` 為空字串
- 若不存在，則要求 `content` 不能為空

### 邏輯驗證
1. ✅ 群組訊息：content 為空字串，使用 encrypted_contents_fanout
2. ✅ DM 訊息：content 包含加密的 URL，使用 file_key
3. ✅ 後端 validation：允許 fanout 訊息的 content 為空
4. ✅ 後端 hub.go：已有邏輯處理 encrypted_contents_fanout

## 測試建議

### 群組訊息測試
1. 發送圖片到群組
2. 確認後端不回傳 "Media content (URL) is required" 錯誤
3. 確認每個成員能正確解密並顯示圖片
4. 檢查資料庫中的訊息：
   - `content` 為空字串
   - `encrypted_contents_fanout` 包含每個成員的加密 URL
   - `file_keys_fanout` 包含每個成員的加密 fileKey

### DM 訊息測試
1. 發送圖片到 DM
2. 確認接收方能正確解密並顯示圖片
3. 檢查資料庫中的訊息：
   - `content` 包含加密的 URL
   - `file_key` 包含明文 fileKey

## 相關檔案

### 後端
- `backend/internal/delivery/websocket/controller.go` (2 處修改)
- `backend/internal/usecase/message_usecase.go` (1 處修改)
- `backend/internal/delivery/websocket/hub.go`（已有 fanout 處理邏輯）
- `backend/internal/domain/message.go`

### 前端
- `app/lib/features/chat/repositories/chat_repository.dart`
- `app/lib/models/message.dart`

## 參考文件
- E2EE_IMAGE_VIDEO_IMPLEMENTATION.md
- E2EE_GROUP_MEDIA_FILEKEY_FANOUT_IMPLEMENTATION.md
- E2EE_GROUP_FANOUT_IMPLEMENTATION.md
