# 群組圖片訊息 sender_id 問題調查

## 問題描述

接收方收到的群組圖片訊息，`sender_id` 是 `room_id`（69ab59d79af3619dbfd152b7）而不是發送方的 `user_id`（69a48bc91d0032558c21d900），導致前端嘗試用 room_id 去取 public key → 404 錯誤。

## 已添加的 Debug Log

### 前端 (app/lib/features/chat/providers/chat_room_provider.dart)

在接收 `chat_message` 事件時添加 log：

```dart
} else if (event == 'chat_message') {
  try {
    // 🔍 DEBUG: 檢查接收到的 sender_id 和 room_id
    debugPrint('[DEBUG] received chat_message: sender_id=${payload['sender_id']}, room_id=${payload['room_id']}, type=${payload['type']}');
    
    final rawMessage = Message.fromJson(payload);
    _tryDecryptMessage(rawMessage).then((message) async {
```

**預期輸出：**
- 如果後端正確：`sender_id` 應該是發送方的 user_id（例如：69a48bc91d0032558c21d900）
- 如果後端錯誤：`sender_id` 會是 room_id（例如：69ab59d79af3619dbfd152b7）

### 後端 Log 1：OnChatMessage (backend/internal/delivery/websocket/controller.go)

在訊息創建時添加 log：

```go
// Set system fields
msg.SenderID = client.userID
msg.CreatedAt = time.Now()

// 🔍 DEBUG: 檢查訊息創建時的 SenderID
log.Printf("[DEBUG] OnChatMessage: client.userID=%s, msg.SenderID=%s, msg.RoomID=%s, msg.Type=%s", 
    client.userID, msg.SenderID, msg.RoomID, msg.Type)
```

**預期輸出：**
- `client.userID` 和 `msg.SenderID` 應該相同
- 都應該是發送方的 user_id，不是 room_id

### 後端 Log 2：routeMessage 複製後 (backend/internal/delivery/websocket/hub.go)

在複製訊息結構後添加 log：

```go
// 為每個接收方建立個人化訊息
personalMsg := *msg // 複製訊息結構

// 🔍 DEBUG: 檢查複製後的 SenderID
log.Printf("[DEBUG] routeMessage: original msg.SenderID=%s, personalMsg.SenderID=%s, memberID=%s, roomID=%s", 
    msg.SenderID, personalMsg.SenderID, memberID, msg.RoomID)
```

**預期輸出：**
- `original msg.SenderID` 和 `personalMsg.SenderID` 應該相同
- 都應該是發送方的 user_id，不是 room_id

### 後端 Log 3：routeMessage 序列化前 (backend/internal/delivery/websocket/hub.go)

在序列化前添加 log：

```go
// 🔍 DEBUG: 檢查序列化前的 personalMsg
log.Printf("[DEBUG] Before marshal: personalMsg.SenderID=%s, personalMsg.RoomID=%s, personalMsg.Type=%s", 
    personalMsg.SenderID, personalMsg.RoomID, personalMsg.Type)
```

**預期輸出：**
- `personalMsg.SenderID` 應該是發送方的 user_id
- `personalMsg.RoomID` 應該是群組的 room_id

## 程式碼審查結果

已檢查以下程式碼路徑，確認都沒有錯誤修改 SenderID：

### ✅ 1. OnChatMessage (controller.go)
```go
msg.SenderID = client.userID  // ✅ 正確設置
```

### ✅ 2. SendMessage Usecase (message_usecase.go)
- 驗證 SenderID 不為空
- 沒有修改 SenderID
- 正確傳遞給 repository

### ✅ 3. StoreMessage Repository (message_repository.go)
```go
func (r *MessageRepository) fromDomain(m *domain.Message) (*mongoMessage, error) {
    return &mongoMessage{
        SenderID: m.SenderID,  // ✅ 正確複製
        // ...
    }, nil
}
```

### ✅ 4. routeMessage Hub (hub.go)
```go
personalMsg := *msg  // ✅ 結構複製應該會複製所有欄位
```

## 可能的問題點

基於程式碼審查，問題可能出在以下幾個地方：

### 1. JSON 序列化問題

Go 的 `json.Marshal` 可能在某些情況下序列化錯誤。需要檢查：
- `domain.Message` 的 JSON 標籤是否正確
- 是否有自定義的 `MarshalJSON` 方法

### 2. 指標問題

雖然 `personalMsg := *msg` 應該複製所有欄位，但如果 `msg` 本身的 `SenderID` 在複製前就是錯的，那麼複製後也會是錯的。

### 3. RabbitMQ 傳輸問題

如果使用 RabbitMQ，訊息在序列化/反序列化過程中可能出錯：
```go
if c.hub.rabbitMQ != nil {
    if err := c.hub.rabbitMQ.Publish(&msg); err != nil {
        // ...
    }
}
```

### 4. 前端發送時的問題

雖然我們已經修復了前端創建訊息時的 senderId，但如果前端在發送 WebSocket 訊息時沒有包含正確的資料，後端可能會收到錯誤的值。

## 測試步驟

### 1. 重新編譯並啟動後端

```bash
cd backend
go build -o bin/server cmd/server/main.go
./bin/server
```

### 2. 重新啟動前端

```bash
cd app
flutter run
```

### 3. 發送測試圖片

1. 在群組聊天中發送一張圖片
2. 觀察後端日誌輸出（按順序）：
   - `[DEBUG] OnChatMessage: ...`
   - `[DEBUG] routeMessage: original msg.SenderID=...`
   - `[DEBUG] Before marshal: personalMsg.SenderID=...`
3. 觀察前端日誌輸出：
   - `[DEBUG] received chat_message: sender_id=...`

### 4. 分析日誌

根據日誌輸出，確定問題發生在哪個階段：

#### 場景 A：OnChatMessage 就錯了
```
[DEBUG] OnChatMessage: client.userID=69a48bc91d0032558c21d900, msg.SenderID=69ab59d79af3619dbfd152b7, ...
```
**結論：** `client.userID` 本身就是錯的，或者賦值失敗

#### 場景 B：複製時出錯
```
[DEBUG] OnChatMessage: msg.SenderID=69a48bc91d0032558c21d900, ...
[DEBUG] routeMessage: original msg.SenderID=69a48bc91d0032558c21d900, personalMsg.SenderID=69ab59d79af3619dbfd152b7, ...
```
**結論：** 結構複製出現問題（極不可能）

#### 場景 C：序列化前正確，前端收到錯誤
```
[DEBUG] Before marshal: personalMsg.SenderID=69a48bc91d0032558c21d900, ...
[DEBUG] received chat_message: sender_id=69ab59d79af3619dbfd152b7, ...
```
**結論：** JSON 序列化或網路傳輸問題

#### 場景 D：全部正確
```
[DEBUG] OnChatMessage: msg.SenderID=69a48bc91d0032558c21d900, ...
[DEBUG] routeMessage: original msg.SenderID=69a48bc91d0032558c21d900, personalMsg.SenderID=69a48bc91d0032558c21d900, ...
[DEBUG] Before marshal: personalMsg.SenderID=69a48bc91d0032558c21d900, ...
[DEBUG] received chat_message: sender_id=69a48bc91d0032558c21d900, ...
```
**結論：** 問題已解決（可能是前端修復生效）

## 下一步行動

1. **執行測試**：按照上述步驟發送測試圖片，收集日誌
2. **分析日誌**：根據日誌輸出確定問題位置
3. **針對性修復**：根據問題位置進行修復
4. **移除 Debug Log**：問題解決後移除所有 debug log

## 相關檔案

- **前端：** `app/lib/features/chat/providers/chat_room_provider.dart`
- **後端：** `backend/internal/delivery/websocket/hub.go`
- **後端：** `backend/internal/delivery/websocket/controller.go`
- **後端：** `backend/internal/domain/message.go`
- **後端：** `backend/internal/usecase/message_usecase.go`
- **後端：** `backend/internal/repository/mongo_repo/message_repository.go`

## 編譯狀態

✅ 前端編譯通過  
✅ 後端需要重新編譯（已添加 debug log）
