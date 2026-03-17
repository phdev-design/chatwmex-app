# 群組 E2EE Fan-out API 規格文件

## 📡 WebSocket 訊息格式

### 1. 發送群組訊息（新格式）

**Event**: `chat_message`

**Direction**: Client → Server

**Payload**:
```json
{
  "client_msg_id": "uuid-v4-string",
  "room_id": "group_room_id",
  "type": "text",
  "content": "",
  "encrypted_contents_fanout": {
    "user_id_1": "base64_encrypted_content_for_user_1",
    "user_id_2": "base64_encrypted_content_for_user_2",
    "user_id_3": "base64_encrypted_content_for_user_3"
  },
  "reply_to_message_id": "optional_message_id",
  "link_preview": {
    "url": "https://example.com",
    "title": "Example Title",
    "description": "Example Description",
    "image_url": "https://example.com/image.jpg"
  }
}
```

**欄位說明**：
- `content`: 保留空字串（向後相容），新格式不使用此欄位
- `encrypted_contents_fanout`: 每個成員的專屬密文
  - Key: 成員的 user_id
  - Value: 用該成員公鑰加密的訊息內容（base64 編碼）

### 2. 接收群組訊息（發送方）

**Event**: `chat_message`

**Direction**: Server → Client (Sender)

**Payload**:
```json
{
  "event": "chat_message",
  "data": {
    "id": "mongodb_object_id",
    "client_msg_id": "uuid-v4-string",
    "sender_id": "sender_user_id",
    "room_id": "group_room_id",
    "type": "text",
    "content": "",
    "encrypted_contents_fanout": {
      "user_id_1": "base64_encrypted_content_for_user_1",
      "user_id_2": "base64_encrypted_content_for_user_2",
      "user_id_3": "base64_encrypted_content_for_user_3"
    },
    "created_at": "2024-01-01T12:00:00Z",
    "status": "sent",
    "read_by": ["sender_user_id"]
  }
}
```

**特點**：
- 發送方收到完整的 `encrypted_contents_fanout`
- 用於存入 LocalDB，以便後續查詢和顯示

### 3. 接收群組訊息（接收方）

**Event**: `chat_message`

**Direction**: Server → Client (Receiver)

**Payload**:
```json
{
  "event": "chat_message",
  "data": {
    "id": "mongodb_object_id",
    "client_msg_id": "uuid-v4-string",
    "sender_id": "sender_user_id",
    "room_id": "group_room_id",
    "type": "text",
    "content": "base64_encrypted_content_for_this_receiver",
    "created_at": "2024-01-01T12:00:00Z",
    "status": "sent",
    "read_by": ["sender_user_id"]
  }
}
```

**特點**：
- 接收方只收到自己的密文（在 `content` 欄位）
- 沒有 `encrypted_contents_fanout` 欄位（安全性考量）

### 4. 發送群組訊息（舊格式 - 向後相容）

**Event**: `chat_message`

**Direction**: Client → Server

**Payload**:
```json
{
  "client_msg_id": "uuid-v4-string",
  "room_id": "group_room_id",
  "type": "text",
  "content": "{\"is_fanout\":true,\"ciphertexts\":{\"user_id_1\":\"...\",\"user_id_2\":\"...\"}}"
}
```

**欄位說明**：
- `content`: JSON 字串，包含 fan-out 結構
- 舊格式仍然支援，但建議使用新格式

## 🗄️ MongoDB 資料結構

### Message Document

```javascript
{
  _id: ObjectId("..."),
  sender_id: "user_id",
  room_id: "group_room_id",
  receiver_id: null,  // 群組訊息此欄位為空
  content: "",  // 新格式為空字串
  type: "text",
  encrypted_contents_fanout: {
    "user_id_1": "base64_encrypted_content_for_user_1",
    "user_id_2": "base64_encrypted_content_for_user_2",
    "user_id_3": "base64_encrypted_content_for_user_3"
  },
  file_keys_fanout: {  // 用於群組媒體加密
    "is_fanout": true,
    "keys": {
      "user_id_1": "encrypted_file_key_1",
      "user_id_2": "encrypted_file_key_2"
    }
  },
  created_at: ISODate("2024-01-01T12:00:00Z"),
  status: "sent",
  is_read: false,
  read_by: ["sender_user_id"],
  reactions: {},
  is_unsent: false,
  deleted_by: []
}
```

## 📱 SQLite 資料結構

### messages 表

```sql
CREATE TABLE messages(
  id TEXT PRIMARY KEY,
  client_msg_id TEXT,
  room_id TEXT,
  sender_id TEXT,
  receiver_id TEXT,
  reply_to_message_id TEXT,
  reactions TEXT,
  is_unsent INTEGER DEFAULT 0,
  content TEXT,
  type TEXT,
  created_at INTEGER,
  is_read INTEGER,
  read_at INTEGER,
  read_by TEXT,
  status TEXT DEFAULT "sent",
  link_preview TEXT,
  file_key TEXT,
  file_keys_fanout TEXT,
  encrypted_contents_fanout TEXT,  -- 新增欄位（JSON 字串）
  decrypt_retry_count INTEGER DEFAULT 0,
  is_decrypted INTEGER DEFAULT 0
);
```

**encrypted_contents_fanout 欄位格式**：
```json
"{\"user_id_1\":\"base64_encrypted_content_1\",\"user_id_2\":\"base64_encrypted_content_2\"}"
```

## 🔐 加密流程

### 發送方（Flutter）

```dart
// 1. 取得群組所有成員
final members = await _chatRepository.getRoomMemberProfiles(roomId);
final memberIds = members.map((m) => m.id).toList();

// 2. 為每個成員加密訊息內容
final encryptedContentsFanout = <String, String>{};
for (final memberId in memberIds) {
  final publicKey = await _publicKeyCacheService.getPublicKey(memberId);
  final ciphertext = await _cryptoService.encryptMessage(plaintext, publicKey);
  encryptedContentsFanout[memberId] = ciphertext;
}

// 3. 發送 WebSocket 訊息
await _wsService.send('chat_message', {
  'room_id': roomId,
  'type': 'text',
  'content': '',  // 空字串
  'encrypted_contents_fanout': encryptedContentsFanout,
});
```

### 後端（Go）

```go
// 1. 接收訊息並存入 MongoDB
msg := &domain.Message{
    SenderID:                senderID,
    RoomID:                  roomID,
    Content:                 "",  // 空字串
    EncryptedContentsFanout: encryptedContentsFanout,
    CreatedAt:               time.Now(),
}
messageUsecase.StoreMessage(ctx, msg)

// 2. 廣播給群組成員
members := roomUsecase.GetRoomMembers(ctx, roomID)

// 2.1 發送給發送方（完整 fanout）
senderPayload := map[string]interface{}{
    "event": "chat_message",
    "data":  msg,  // 包含完整 EncryptedContentsFanout
}
hub.SendToUser(senderID, senderPayload)

// 2.2 發送給其他成員（裁切後的版本）
for _, memberID := range members {
    if memberID == senderID {
        continue
    }
    
    personalMsg := *msg  // 複製
    personalMsg.Content = msg.EncryptedContentsFanout[memberID]  // 只保留該成員的密文
    personalMsg.EncryptedContentsFanout = nil  // 移除 fanout map
    
    receiverPayload := map[string]interface{}{
        "event": "chat_message",
        "data":  personalMsg,
    }
    hub.SendToUser(memberID, receiverPayload)
}
```

### 接收方（Flutter）

```dart
// 1. 接收 WebSocket 訊息
final rawMessage = Message.fromJson(payload);

// 2. 解密訊息
String decrypted;
if (rawMessage.encryptedContentsFanout != null) {
  // 新格式：從 fanout map 取出自己的密文
  final myCiphertext = rawMessage.encryptedContentsFanout![currentUserId];
  final senderPublicKey = await _publicKeyCacheService.getPublicKey(senderId);
  decrypted = await _cryptoService.decryptMessage(myCiphertext, senderPublicKey);
} else {
  // 舊格式或接收方收到的裁切版本
  final senderPublicKey = await _publicKeyCacheService.getPublicKey(senderId);
  decrypted = await _cryptoService.decryptMessage(rawMessage.content, senderPublicKey);
}

// 3. 顯示明文
displayMessage(decrypted);
```

## 🔄 向後相容性

### 舊格式訊息處理

前端會自動檢測訊息格式：

```dart
if (m.encryptedContentsFanout != null) {
  // 新格式
  decrypted = await _decryptFromFanout(m);
} else if (m.content.contains('is_fanout')) {
  // 舊格式（JSON 字串）
  decrypted = await _decryptGroupMessage(m.content, m.senderId);
} else {
  // DM 或明文
  decrypted = m.content;
}
```

### 遷移策略

1. **階段 1**：部署後端，支援新舊兩種格式
2. **階段 2**：部署前端，優先使用新格式，但仍能解密舊格式
3. **階段 3**：觀察一段時間（例如 1 個月）
4. **階段 4**：（可選）移除舊格式支援

## 🚨 錯誤處理

### 1. 缺少成員密文

**情況**：`encrypted_contents_fanout` 中沒有某個成員的密文

**原因**：
- 該成員的公鑰不可用
- 加密過程中發生錯誤

**處理**：
- 前端：顯示 "🔒 此訊息無法解密"
- 觸發 E2EE Auto-Resend 機制

### 2. 解密失敗

**情況**：解密操作拋出異常

**原因**：
- 密文損壞
- 公鑰不匹配
- 金鑰已更新

**處理**：
- 前端：顯示 "🔒 此訊息無法解密（金鑰已更新）"
- 觸發 E2EE Auto-Resend 機制

### 3. Fanout Map 過大

**情況**：群組成員數量超過 1000 人

**處理**：
- 前端：分批加密（batch size = 10）
- 後端：考慮使用壓縮或混合加密

## 📊 效能考量

### 加密效能

- 單個成員加密時間：~10ms
- 100 個成員（批次處理）：~1-2 秒
- 1000 個成員：~10-20 秒

### 儲存空間

- 單個密文大小：~200 bytes（base64 編碼）
- 100 個成員的 fanout map：~20 KB
- 1000 個成員：~200 KB

### 網路傳輸

- 發送方 → 後端：完整 fanout map
- 後端 → 接收方：單一密文（~200 bytes）

## 🔒 安全性考量

### 1. 接收方隔離

- 每個接收方只能看到自己的密文
- 無法從 payload 中獲取其他成員的密文

### 2. 中間人攻擊防護

- 使用 HTTPS/WSS 加密傳輸
- 公鑰透過可信渠道分發

### 3. 金鑰輪換

- 支援金鑰更新後的重新加密機制
- E2EE Auto-Resend 自動處理解密失敗

## 📝 變更日誌

### v1.0.0 (2024-01-01)
- 新增 `encrypted_contents_fanout` 欄位
- 實作後端裁切邏輯
- 支援向後相容性

### v0.9.0 (2023-12-01)
- 舊格式：`content` 欄位包含 JSON 字串
