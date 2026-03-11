# Link Preview 修復說明

## 🔍 問題診斷

### 根本原因
Link Preview 功能的**數據流斷裂**發生在前端發送訊息時：

1. ✅ 前端成功抓取 Link Preview（`chat_input_bar.dart` 的 `_fetchLinkPreview()`）
2. ✅ 前端成功顯示預覽卡片
3. ❌ **發送訊息時，Link Preview 數據被丟棄**
4. ❌ WebSocket payload 中沒有包含 `link_preview` 欄位
5. ❌ 後端收到訊息但 `LinkPreview` 為 `nil`
6. ❌ 訊息儲存到資料庫時沒有預覽數據
7. ❌ 前端收到訊息後只顯示純文字 URL

### 數據流斷點位置

```
chat_input_bar.dart (_sendMessage)
    ↓
    ❌ 只傳送 text，沒有傳送 _previewData
    ↓
chat_room_provider.dart (sendMessage)
    ↓
    ❌ 沒有接收 linkPreview 參數
    ↓
WebSocket payload
    ↓
    ❌ payload 中沒有 link_preview 欄位
    ↓
後端收到訊息
    ↓
    ❌ msg.LinkPreview = nil
```

## 🔧 修復內容

### 1. 前端修改

#### `app/lib/features/chat/ui/widgets/chat_input_bar.dart`

**修改點 1：`_sendMessage()` 方法**
```dart
void _sendMessage() {
  final text = _textController.text.trim();
  if (text.isNotEmpty) {
    // 🔥 修復：將 link preview 數據傳遞給 sendMessage
    LinkPreview? linkPreview;
    if (_previewData != null && !_isUrlPreviewCancelled) {
      linkPreview = LinkPreview(
        url: _previewData!.url,
        title: _previewData!.title,
        description: _previewData!.description,
        imageUrl: _previewData?.imageUrl,
      );
      print('📎 [ChatInput] 發送訊息附帶 Link Preview: ${linkPreview.url}');
    }
    
    ref.read(chatRoomProvider(widget.params).notifier).sendMessage(
      text,
      linkPreview: linkPreview, // 🔥 新增參數
    );
    // ... rest of the code
  }
}
```

#### `app/lib/features/chat/providers/chat_room_provider.dart`

**修改點 2：`sendMessage()` 方法簽名**
```dart
Future<void> sendMessage(
  String content, {
  MessageType type = MessageType.text,
  LinkPreview? linkPreview, // 🔥 新增參數
}) async {
  // ...
}
```

**修改點 3：將 linkPreview 加入 tempMessage**
```dart
final tempMessage = Message(
  // ... other fields
  linkPreview: linkPreview, // 🔥 新增
);
```

**修改點 4：將 linkPreview 加入 WebSocket payload**
```dart
final payload = {
  'receiver_id': arg.isRoom ? null : arg.roomId,
  'room_id': arg.isRoom ? arg.roomId : null,
  'reply_to_message_id': replyToId,
  'content': payloadContent,
  'type': type.toString().split('.').last,
  'client_msg_id': clientMsgId,
  // 🔥 新增：將 link preview 加入 payload
  if (linkPreview != null) 'link_preview': {
    'url': linkPreview.url,
    'title': linkPreview.title,
    'description': linkPreview.description,
    if (linkPreview.imageUrl != null) 'image_url': linkPreview.imageUrl,
  },
};
```

### 2. 後端修改

#### `backend/internal/delivery/websocket/controller.go`

**修改點：添加日誌記錄**
```go
func (c *SocketController) OnChatMessage(client *Client, data []byte) {
	var msg domain.Message
	if err := json.Unmarshal(data, &msg); err != nil {
		c.respondError(client, "error", "Invalid message format")
		return
	}

	// 🔥 新增：記錄收到的訊息資訊
	if msg.LinkPreview != nil {
		log.Printf("📎 [WebSocket] 收到訊息附帶 Link Preview: URL=%s, Title=%s", 
			msg.LinkPreview.URL, msg.LinkPreview.Title)
	} else {
		log.Printf("📝 [WebSocket] 收到純文字訊息，無 Link Preview")
	}
	// ...
}
```

#### `backend/internal/usecase/message_usecase.go`

**修改點：添加日誌記錄**
```go
func (u *messageUsecase) SendMessage(c context.Context, msg *domain.Message) error {
	// ... validation code

	// 🔥 新增：記錄 LinkPreview 資訊
	if msg.LinkPreview != nil {
		log.Printf("📎 [MessageUsecase] 收到訊息附帶 Link Preview: URL=%s, Title=%s", 
			msg.LinkPreview.URL, msg.LinkPreview.Title)
	} else {
		log.Printf("📝 [MessageUsecase] 收到純文字訊息，無 Link Preview")
	}
	// ...
}
```

### 3. 前端 UI 修改

#### `app/lib/features/chat/ui/widgets/message_bubble.dart`

**修改點：添加調試日誌**
```dart
final preview = msg.linkPreview;
final hasPreview = !msg.isUnsent && preview != null && 
    (preview.url.isNotEmpty || preview.title.isNotEmpty || preview.description.isNotEmpty);

// 🔥 新增：記錄 Link Preview 狀態
if (msg.type == MessageType.text && msg.content.contains('http')) {
  if (hasPreview) {
    print('✅ [MessageBubble] 訊息 ${msg.id} 有 Link Preview: ${preview!.url}');
  } else {
    print('⚠️ [MessageBubble] 訊息 ${msg.id} 包含 URL 但沒有 Link Preview');
  }
}
```

## 📊 測試步驟

### 1. 測試 Link Preview 抓取
1. 啟動應用
2. 在聊天輸入框貼上任何 URL（例如：`https://flutter.dev`）
3. 等待 500ms（debounce 時間）
4. **預期結果**：輸入框上方顯示預覽卡片

### 2. 測試 Link Preview 發送
1. 在顯示預覽卡片的狀態下點擊發送按鈕
2. **檢查前端日誌**：
   ```
   📎 [ChatInput] 發送訊息附帶 Link Preview: https://flutter.dev
   📤 [ChatRoom] 發送訊息 payload: 包含 Link Preview
   ```

### 3. 測試後端接收
1. **檢查後端日誌**：
   ```
   📎 [WebSocket] 收到訊息附帶 Link Preview: URL=https://flutter.dev, Title=Flutter
   📎 [MessageUsecase] 收到訊息附帶 Link Preview: URL=https://flutter.dev, Title=Flutter
   ```

### 4. 測試 UI 顯示
1. 訊息發送後，檢查聊天室中的訊息
2. **預期結果**：訊息下方顯示 Link Preview 卡片
3. **檢查前端日誌**：
   ```
   ✅ [MessageBubble] 訊息 xxx 有 Link Preview: https://flutter.dev
   ```

## 🐛 故障排除

### 問題 1：前端沒有顯示預覽卡片
**檢查**：
- 確認 `_fetchLinkPreview()` 是否成功調用
- 確認後端 `/messages/link-preview` API 是否正常運作
- 檢查網路連線

### 問題 2：發送後沒有 Link Preview
**檢查前端日誌**：
- 如果沒有看到 `📎 [ChatInput] 發送訊息附帶 Link Preview`
  - 檢查 `_previewData` 是否為 `null`
  - 檢查 `_isUrlPreviewCancelled` 是否為 `true`

### 問題 3：後端沒有收到 Link Preview
**檢查後端日誌**：
- 如果看到 `📝 [WebSocket] 收到純文字訊息，無 Link Preview`
  - 檢查 WebSocket payload 是否包含 `link_preview` 欄位
  - 檢查 JSON 序列化是否正確

### 問題 4：訊息顯示時沒有 Link Preview
**檢查前端日誌**：
- 如果看到 `⚠️ [MessageBubble] 訊息 xxx 包含 URL 但沒有 Link Preview`
  - 檢查資料庫中的訊息是否包含 `link_preview` 欄位
  - 檢查 `Message.fromJson()` 是否正確解析

## 📝 注意事項

1. **E2EE 加密**：Link Preview 的 URL、標題、描述都是**明文儲存**，不會被加密。這是設計上的考量，因為：
   - Link Preview 需要在後端抓取（無法在前端解密後抓取）
   - 預覽資訊不包含敏感內容
   - 只有訊息的 `content` 欄位會被加密

2. **取消預覽**：用戶可以點擊預覽卡片上的 ❌ 按鈕取消預覽，此時：
   - `_isUrlPreviewCancelled` 設為 `true`
   - 發送訊息時不會包含 `linkPreview`
   - 訊息會以純文字形式發送

3. **多個 URL**：如果訊息包含多個 URL，只會為**第一個 URL** 生成預覽

4. **快取機制**：後端使用 Redis 快取 Link Preview 結果（24 小時），避免重複抓取

## 🎯 預期效果

修復後，當用戶發送包含 URL 的訊息時：

1. ✅ 輸入框上方顯示預覽卡片
2. ✅ 點擊發送後，訊息包含 Link Preview 數據
3. ✅ 後端正確接收並儲存 Link Preview
4. ✅ 聊天室中顯示精美的預覽卡片
5. ✅ 點擊預覽卡片可以打開外部瀏覽器

## 📂 相關檔案

### 前端
- `app/lib/features/chat/ui/widgets/chat_input_bar.dart` - 輸入框與預覽抓取
- `app/lib/features/chat/providers/chat_room_provider.dart` - 訊息發送邏輯
- `app/lib/features/chat/ui/widgets/message_bubble.dart` - 訊息顯示 UI
- `app/lib/models/message.dart` - Message 和 LinkPreview 模型

### 後端
- `backend/internal/delivery/websocket/controller.go` - WebSocket 訊息處理
- `backend/internal/usecase/message_usecase.go` - 訊息業務邏輯
- `backend/internal/utils/link_preview.go` - Link Preview 抓取邏輯
- `backend/internal/domain/message.go` - Message 和 LinkPreview 定義


## 🔧 Query 23: WebSocket Message Size Limit Fix

### 問題診斷

在 Query 22 中發現 WebSocket 連線不穩定，立即斷線：

```
flutter: WebSocket closed
flutter: Reconnecting in 1 seconds...
flutter: Send failed, queuing message: TimeoutException: Message ACK timeout
```

後端日誌顯示：
```
2026/03/11 16:41:32 Client connected: 69a48bc91d0032558c21d900
2026/03/11 16:41:32 Client disconnected: 69a48bc91d0032558c21d900
```

**根本原因**：
- `backend/internal/delivery/websocket/client.go` 中的 `maxMessageSize = 512` bytes 太小
- Link Preview 數據（URL、title、description、imageUrl）很容易超過 512 bytes
- 當訊息超過限制時，WebSocket 連線會立即關閉
- 後端的 `📎 [WebSocket]` 日誌沒有出現，表示訊息從未到達 `OnChatMessage()`

### 修復內容

#### 1. 增加 `maxMessageSize` 限制

**檔案**：`backend/internal/delivery/websocket/client.go`

```go
const (
	// Time allowed to write a message to the peer.
	writeWait = 10 * time.Second

	// Time allowed to read the next pong message from the peer.
	pongWait = 60 * time.Second

	// Send pings to peer with this period. Must be less than pongWait.
	pingPeriod = (pongWait * 9) / 10

	// Maximum message size allowed from peer.
	// Increased to 8KB to accommodate link preview data (URL, title, description, image URL)
	maxMessageSize = 8192  // 🔥 從 512 增加到 8192 bytes
)
```

**變更說明**：
- 從 512 bytes 增加到 8192 bytes (8KB)
- 足以容納包含 Link Preview 的訊息
- 添加註解說明增加原因

#### 2. 增強錯誤日誌記錄

**檔案**：`backend/internal/delivery/websocket/client.go`

在 `readPump()` 函數中添加：

```go
func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()
	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error { c.conn.SetReadDeadline(time.Now().Add(pongWait)); return nil })
	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				// 🔥 改進：記錄用戶 ID
				log.Printf("WebSocket error for user %s: %v", c.userID, err)
			}
			break
		}

		// 🔥 新增：記錄大型訊息
		if len(message) > 1024 {
			log.Printf("📦 [WebSocket] Large message received from user %s: %d bytes", c.userID, len(message))
		}

		// Delegate to Controller
		c.controller.HandleMessage(c, message)
	}
}
```

**檔案**：`backend/internal/delivery/websocket/controller.go`

在 `HandleMessage()` 函數中添加：

```go
func (c *SocketController) HandleMessage(client *Client, message []byte) {
	var req WSRequest
	if err := json.Unmarshal(message, &req); err != nil {
		// 🔥 新增：詳細的 JSON 解析錯誤日誌
		log.Printf("❌ [WebSocket] JSON parse error from user %s: %v | Raw message (first 200 chars): %s", 
			client.userID, err, string(message[:min(200, len(message))]))
		c.respondError(client, "error", "Invalid JSON format")
		return
	}
	// ...
}

// 🔥 新增：輔助函數
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
```

在 `OnChatMessage()` 函數中添加：

```go
func (c *SocketController) OnChatMessage(client *Client, data []byte) {
	var msg domain.Message
	if err := json.Unmarshal(data, &msg); err != nil {
		// 🔥 新增：詳細的訊息解析錯誤日誌
		log.Printf("❌ [WebSocket] Message parse error from user %s: %v | Raw data (first 200 chars): %s", 
			client.userID, err, string(data[:min(200, len(data))]))
		c.respondError(client, "error", "Invalid message format")
		return
	}
	// ...
}
```

### 測試步驟

1. **重啟後端服務**以應用新的 `maxMessageSize` 限制

2. **測試發送包含 Link Preview 的訊息**：
   - 在聊天輸入框貼上 URL
   - 等待預覽卡片出現
   - 點擊發送

3. **檢查後端日誌**，應該看到：
   ```
   📦 [WebSocket] Large message received from user xxx: 1234 bytes
   📎 [WebSocket] 收到訊息附帶 Link Preview: URL=https://..., Title=...
   📎 [MessageUsecase] 收到訊息附帶 Link Preview: URL=https://..., Title=...
   ```

4. **檢查前端**：
   - WebSocket 連線保持穩定（不會立即斷線）
   - 訊息成功發送並收到 ACK
   - 聊天室中顯示 Link Preview 卡片

5. **如果仍然失敗**，檢查後端日誌中的錯誤訊息：
   - `❌ [WebSocket] JSON parse error` - JSON 格式錯誤
   - `❌ [WebSocket] Message parse error` - 訊息結構錯誤

### 預期效果

修復後：
- ✅ WebSocket 連線穩定，不會因訊息過大而斷線
- ✅ 包含 Link Preview 的訊息可以正常傳送
- ✅ 後端正確接收並記錄 Link Preview 資訊
- ✅ 前端顯示完整的 Link Preview 卡片
- ✅ 詳細的錯誤日誌幫助快速診斷問題

### 相關檔案

- `backend/internal/delivery/websocket/client.go` - WebSocket 客戶端與訊息大小限制
- `backend/internal/delivery/websocket/controller.go` - WebSocket 訊息處理與錯誤日誌
