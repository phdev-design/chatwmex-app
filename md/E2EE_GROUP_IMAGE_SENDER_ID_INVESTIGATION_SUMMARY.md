# 群組圖片訊息 sender_id 問題調查總結

## 問題描述

接收方收到的群組圖片訊息，`sender_id` 是 `room_id`（69ab59d79af3619dbfd152b7）而不是發送方的 `user_id`（69a48bc91d0032558c21d900），導致前端嘗試用 room_id 去取 public key → 404 錯誤。

## 已完成的修復

### 1. 前端修復（已完成）

**檔案：** `app/lib/features/chat/repositories/chat_repository.dart`

修復了前端創建本地訊息時 `senderId` 設為空字串的問題：

```dart
// 🔐 獲取當前用戶 ID
final currentUserId = await _storageService.read('user_id') ?? '';

final message = Message(
  // ...
  senderId: currentUserId,  // ✅ 修改：從空字串改為 currentUserId
  // ...
);
```

**影響：**
- 本地訊息顯示正確（發送方看到的訊息）
- 但不影響 WebSocket 發送的 payload（後端會覆寫）

### 2. 前端解密邏輯修復（已完成）

**檔案：** `app/lib/features/chat/providers/chat_room_provider.dart`

添加了對 image/video 訊息 URL 的解密邏輯：

```dart
// 🔐 群組媒體訊息：從 encryptedContentsFanout 解密圖片/影片 URL
if ((m.type == MessageType.image || m.type == MessageType.video) &&
    m.encryptedContentsFanout != null &&
    (m.content.isEmpty || _looksLikeE2EECiphertext(m.content))) {
  final myEncryptedUrl = m.encryptedContentsFanout![arg.currentUserId];
  if (myEncryptedUrl != null && myEncryptedUrl.isNotEmpty) {
    // 解密 URL
  }
}
```

### 3. _getPublicKey 修復（已完成）

**檔案：** `app/lib/features/chat/providers/chat_room_provider.dart`

移除了錯誤的 `isRoom` 檢查：

```dart
Future<String?> _getPublicKey(String userId) async {
  // 🔐 修復：群組聊天也需要獲取成員的公鑰來解密訊息
  return await _publicKeyCacheService.getPublicKey(userId);
}
```

## 待確認的問題：後端 sender_id 設置

### 程式碼審查結果

已檢查完整的後端程式碼路徑，確認所有地方都正確處理 SenderID：

#### ✅ 1. WebSocket 接收訊息（controller.go）
```go
// Set system fields
msg.SenderID = client.userID  // ✅ 正確設置為發送方的 user_id
msg.CreatedAt = time.Now()
```

#### ✅ 2. 訊息持久化（message_usecase.go）
- 驗證 SenderID 不為空
- 沒有修改 SenderID
- 正確傳遞給 repository

#### ✅ 3. 資料庫儲存（message_repository.go）
```go
return &mongoMessage{
    SenderID: m.SenderID,  // ✅ 正確複製
    // ...
}
```

#### ✅ 4. 群組訊息廣播（hub.go）
```go
personalMsg := *msg  // ✅ 結構複製會複製所有欄位包括 SenderID

if hasFanout {
    if ciphertext, exists := msg.EncryptedContentsFanout[memberID]; exists {
        personalMsg.Content = ciphertext  // ✅ 只修改 Content
    }
    personalMsg.EncryptedContentsFanout = nil  // ✅ 只修改 EncryptedContentsFanout
}
// ✅ 沒有修改 personalMsg.SenderID
```

### 前端 WebSocket Payload

前端發送圖片訊息時的 payload：

```dart
final payload = <String, dynamic>{
  'client_msg_id': clientMsgId,
  'type': 'image',
  'room_id': roomId,
  'receiver_id': receiverId,
  'file_keys_fanout': fileKeysFanout,
  'encrypted_contents_fanout': encryptedContentsFanout,
  'content': '',
};
// ❌ 注意：沒有包含 'sender_id'
```

**這是正確的！** 因為後端會在 `OnChatMessage` 中自動設置：
```go
msg.SenderID = client.userID
```

## 已添加的 Debug Log

為了確認問題的確切位置，已在以下三個關鍵點添加 debug log：

### 1. 前端接收訊息
```dart
debugPrint('[DEBUG] received chat_message: sender_id=${payload['sender_id']}, room_id=${payload['room_id']}, type=${payload['type']}');
```

### 2. 後端訊息創建
```go
log.Printf("[DEBUG] OnChatMessage: client.userID=%s, msg.SenderID=%s, msg.RoomID=%s, msg.Type=%s", 
    client.userID, msg.SenderID, msg.RoomID, msg.Type)
```

### 3. 後端訊息複製
```go
log.Printf("[DEBUG] routeMessage: original msg.SenderID=%s, personalMsg.SenderID=%s, memberID=%s, roomID=%s", 
    msg.SenderID, personalMsg.SenderID, memberID, msg.RoomID)
```

### 4. 後端序列化前
```go
log.Printf("[DEBUG] Before marshal: personalMsg.SenderID=%s, personalMsg.RoomID=%s, personalMsg.Type=%s", 
    personalMsg.SenderID, personalMsg.RoomID, personalMsg.Type)
```

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
在群組聊天中發送一張圖片，觀察日誌輸出。

### 4. 分析日誌

根據日誌輸出，確定問題發生在哪個階段：

#### 預期正常輸出（問題已解決）
```
後端：
[DEBUG] OnChatMessage: client.userID=69a48bc91d0032558c21d900, msg.SenderID=69a48bc91d0032558c21d900, msg.RoomID=69ab59d79af3619dbfd152b7, msg.Type=image
[DEBUG] routeMessage: original msg.SenderID=69a48bc91d0032558c21d900, personalMsg.SenderID=69a48bc91d0032558c21d900, memberID=xxx, roomID=69ab59d79af3619dbfd152b7
[DEBUG] Before marshal: personalMsg.SenderID=69a48bc91d0032558c21d900, personalMsg.RoomID=69ab59d79af3619dbfd152b7, personalMsg.Type=image

前端：
[DEBUG] received chat_message: sender_id=69a48bc91d0032558c21d900, room_id=69ab59d79af3619dbfd152b7, type=image
```

#### 異常輸出 A：client.userID 就是錯的
```
[DEBUG] OnChatMessage: client.userID=69ab59d79af3619dbfd152b7, msg.SenderID=69ab59d79af3619dbfd152b7, ...
```
**問題：** WebSocket 連接時 `client.userID` 設置錯誤

#### 異常輸出 B：序列化問題
```
後端：
[DEBUG] Before marshal: personalMsg.SenderID=69a48bc91d0032558c21d900, ...

前端：
[DEBUG] received chat_message: sender_id=69ab59d79af3619dbfd152b7, ...
```
**問題：** JSON 序列化或網路傳輸問題

## 可能的根本原因

如果測試後仍然出現問題，可能的原因：

### 1. WebSocket 連接時 client.userID 設置錯誤

檢查 WebSocket 連接建立時如何設置 `client.userID`：

```go
// 應該從 JWT token 或認證資訊中獲取真實的 user_id
client.userID = authenticatedUserID

// 而不是從請求參數中獲取（可能被篡改）
client.userID = req.Query("room_id")  // ❌ 錯誤
```

### 2. RabbitMQ 序列化/反序列化問題

如果使用 RabbitMQ，檢查訊息在序列化和反序列化過程中是否正確保留 SenderID。

### 3. 多伺服器環境下的問題

如果有多個後端伺服器實例，檢查訊息在伺服器間傳遞時是否正確保留 SenderID。

## 下一步行動

1. **執行測試**：按照上述步驟發送測試圖片，收集完整的日誌輸出
2. **分析日誌**：根據日誌確定問題的確切位置
3. **針對性修復**：根據日誌分析結果進行修復
4. **移除 Debug Log**：問題解決後移除所有 debug log
5. **回歸測試**：確保修復不影響其他功能

## 相關檔案

### 前端
- `app/lib/features/chat/providers/chat_room_provider.dart`
- `app/lib/features/chat/repositories/chat_repository.dart`

### 後端
- `backend/internal/delivery/websocket/hub.go`
- `backend/internal/delivery/websocket/controller.go`
- `backend/internal/domain/message.go`
- `backend/internal/usecase/message_usecase.go`
- `backend/internal/repository/mongo_repo/message_repository.go`

## 編譯狀態

✅ 前端編譯通過（已添加 debug log）  
✅ 後端需要重新編譯（已添加 debug log）  
✅ 所有程式碼審查完成  
⏳ 等待實際測試確認問題位置
