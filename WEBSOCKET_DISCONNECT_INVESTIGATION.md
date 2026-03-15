# WebSocket 頻繁斷線重連問題調查報告

## 問題症狀
- 前端 log：`Send failed, queuing message: TimeoutException: Message ACK timeout`
- 前端 log：`Reconnecting in 1 seconds...`
- 後端 log：同一個 userId 每隔 6 秒斷線重連，持續約 8 次

## 調查發現

### 1. 前端 ACK Timeout 設定 ⚠️

**檔案：** `app/lib/core/websocket/websocket_service.dart`

**問題點：**
```dart
// Line 237-243: ACK timeout 設定為 5 秒
await completer.future.timeout(
  const Duration(seconds: 5),
  onTimeout: () {
    _pendingAcks.remove(clientMsgId);
    throw TimeoutException('Message ACK timeout');
  },
);
```

**分析：**
- ACK timeout 設定為 **5 秒**
- 如果後端在 5 秒內沒有回傳 `message_ack`，前端會拋出 `TimeoutException`
- 這會觸發 catch block，將訊息加入 queue 並呼叫 `_handleDisconnect()`

### 2. 前端重連邏輯 ✅ 有指數退避

**檔案：** `app/lib/core/websocket/websocket_service.dart`

**實作：**
```dart
// Line 195-202: 有實作指數退避
void _handleDisconnect() {
  _isConnected = false;
  _channel = null;
  _streamController.add({'event': 'ws_disconnected'});

  // Exponential backoff
  final delay = Duration(seconds: (1 << _retryAttempts).clamp(1, 30));
  _retryAttempts++;

  debugPrint('Reconnecting in ${delay.inSeconds} seconds...');
  _reconnectTimer?.cancel();
  _reconnectTimer = Timer(delay, connect);
}
```

**分析：**
- ✅ **有實作指數退避**：`(1 << _retryAttempts).clamp(1, 30)`
- 重連延遲：1秒 → 2秒 → 4秒 → 8秒 → 16秒 → 30秒（最大值）
- **但是**，log 顯示 "Reconnecting in 1 seconds..." 表示 `_retryAttempts` 可能被重置或沒有累積

**潛在問題：**
- 如果每次 ACK timeout 都觸發 `_handleDisconnect()`，但 `_retryAttempts` 沒有正確累積
- 或者在某些情況下 `_retryAttempts` 被重置為 0（例如 Line 75: token refresh 成功後）

### 3. 後端 WebSocket 設定 ✅ 有 Ping/Pong 心跳

**檔案：** `backend/internal/delivery/websocket/client.go`

**設定：**
```go
const (
  // Time allowed to write a message to the peer.
  writeWait = 10 * time.Second

  // Time allowed to read the next pong message from the peer.
  pongWait = 60 * time.Second

  // Send pings to peer with this period. Must be less than pongWait.
  pingPeriod = (pongWait * 9) / 10  // = 54 seconds

  // Maximum message size allowed from peer.
  // Increased to 1MB to accommodate group messages with Fan-out E2EE encryption
  maxMessageSize = 1048576  // 1MB
)
```

**分析：**
- ✅ **有實作 Ping/Pong 心跳**
- Ping 週期：**54 秒**
- Pong 超時：**60 秒**
- Write deadline：**10 秒**
- Read deadline：動態設定，每次收到 pong 後重置為 60 秒

**Ping/Pong 機制：**
```go
// Line 91-95: writePump 定期發送 ping
case <-ticker.C:
  c.conn.SetWriteDeadline(time.Now().Add(writeWait))
  if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
    return
  }
```

```go
// Line 59: readPump 設定 pong handler
c.conn.SetPongHandler(func(string) error { 
  c.conn.SetReadDeadline(time.Now().Add(pongWait)); 
  return nil 
})
```

### 4. 大型 Payload 問題分析 ⚠️

**最大訊息大小：** 1MB (1048576 bytes)

**群組訊息 Payload 結構：**
```dart
// app/lib/features/chat/providers/chat_room_provider.dart
final payload = {
  'receiver_id': arg.isRoom ? null : arg.roomId,
  'room_id': arg.isRoom ? arg.roomId : null,
  'reply_to_message_id': replyToId,
  'content': payloadContent,
  'type': type.toString().split('.').last,
  'client_msg_id': clientMsgId,
  // 🔐 群組訊息：encrypted_contents_fanout 包含所有成員的加密內容
  if (encryptedContentsFanout != null) 
    'encrypted_contents_fanout': encryptedContentsFanout,  // Map<String, String>
  if (linkPreview != null) 'link_preview': { ... },
};
```

**Payload 大小估算（3 個成員的群組）：**
- 假設每個成員的加密內容為 1KB（文字訊息）
- `encrypted_contents_fanout`: 3 × 1KB = 3KB
- 加上其他欄位（metadata, link_preview 等）：~1KB
- **總計：約 4KB**（遠小於 1MB 限制）

**圖片/影片訊息：**
```dart
// app/lib/features/chat/repositories/chat_repository.dart
// Line 717-722
if (fileKeysFanout != null) {
  payload['file_keys_fanout'] = fileKeysFanout;
  payload['encrypted_contents_fanout'] = encryptedContentsFanout;
  payload['content'] = ''; // 空字串
}
```

**分析：**
- 圖片/影片訊息只傳送 **加密的檔案金鑰**（file_keys_fanout），不傳送實際檔案內容
- 檔案金鑰通常很小（~256 bytes per member）
- 3 個成員：3 × 256 bytes = 768 bytes
- **不太可能超過 1MB 限制**

## 根本原因分析

### 最可能的原因：ACK Timeout 導致的連鎖反應

1. **觸發條件：**
   - 前端發送 `chat_message` 事件
   - 等待後端回傳 `message_ack`（5 秒 timeout）
   - 如果後端處理時間 > 5 秒，前端拋出 `TimeoutException`

2. **連鎖反應：**
   ```
   發送訊息 → ACK timeout (5秒) → 拋出異常 → 訊息加入 queue 
   → 呼叫 _handleDisconnect() → 斷開連接 → 重連（1秒後）
   → 處理 queue → 再次發送 → 再次 timeout → 循環
   ```

3. **為什麼是 6 秒間隔？**
   - ACK timeout: 5 秒
   - 重連延遲: 1 秒
   - **總計: 6 秒**

4. **為什麼持續 8 次？**
   - 可能是 queue 中有 8 個待發送的訊息
   - 或者某個訊息重試了 8 次後被放棄

### 次要原因：後端處理延遲

**可能導致 ACK 延遲的原因：**

1. **資料庫操作延遲**
   - 儲存訊息到 PostgreSQL
   - 查詢群組成員列表
   - 查詢離線訊息

2. **RabbitMQ 發布延遲**
   - 跨伺服器廣播訊息

3. **群組訊息 Fanout 處理**
   - 為每個成員裁切 payload（`encrypted_contents_fanout`）
   - 序列化個人化訊息

4. **網路延遲**
   - 前端到後端的網路延遲
   - 後端到資料庫/RabbitMQ 的網路延遲

## 建議修正方案

### 方案 1：增加 ACK Timeout（推薦）⭐

**修改：** `app/lib/core/websocket/websocket_service.dart`

```dart
// 從 5 秒增加到 10 秒或 15 秒
await completer.future.timeout(
  const Duration(seconds: 10),  // 或 15
  onTimeout: () {
    _pendingAcks.remove(clientMsgId);
    throw TimeoutException('Message ACK timeout');
  },
);
```

**優點：**
- 簡單直接
- 給後端更多時間處理複雜操作
- 減少誤判

**缺點：**
- 使用者體驗稍差（需要等更久才知道失敗）

### 方案 2：ACK Timeout 不觸發斷線

**修改：** `app/lib/core/websocket/websocket_service.dart`

```dart
} catch (e) {
  debugPrint('Send failed, queuing message: $e');
  _messageQueue.add(payload);
  // ❌ 移除這行：不要因為 ACK timeout 就斷線
  // if (_isConnected) _handleDisconnect();
  
  // ✅ 改為：只在連接真的斷開時才重連
  // WebSocket 的 onDone/onError 會自動觸發 _handleDisconnect()
}
```

**優點：**
- 避免不必要的重連
- ACK timeout 只是將訊息加入 queue，不影響連接

**缺點：**
- 如果連接真的有問題，可能延遲發現

### 方案 3：優化後端 ACK 回應速度

**目標：** 確保後端在 3 秒內回傳 ACK

**可能的優化：**

1. **提前發送 ACK**
   - 在儲存到資料庫之前就發送 ACK
   - 使用非同步處理（goroutine）處理耗時操作

2. **優化資料庫查詢**
   - 加索引
   - 使用快取（Redis）儲存群組成員列表

3. **批次處理**
   - 合併多個資料庫操作

### 方案 4：改善重連邏輯（補充）

**問題：** Log 顯示 "Reconnecting in 1 seconds..." 表示沒有指數退避

**可能原因：**
- `_retryAttempts` 在某些情況下被重置
- 例如：token refresh 成功後（Line 75）

**建議：**
- 檢查所有重置 `_retryAttempts` 的地方
- 只在真正連接成功後才重置

## 下一步行動

1. **確認問題：**
   - 檢查後端 log，確認 ACK 回應時間
   - 檢查前端 log，確認 timeout 發生的頻率

2. **實施修正：**
   - 優先實施方案 1（增加 timeout）或方案 2（不觸發斷線）
   - 監控效果

3. **長期優化：**
   - 實施方案 3（優化後端效能）
   - 加入監控和告警

## 附錄：相關程式碼位置

### 前端
- WebSocket Service: `app/lib/core/websocket/websocket_service.dart`
  - ACK timeout: Line 237-243
  - 重連邏輯: Line 195-202
  - 發送邏輯: Line 204-250

### 後端
- WebSocket Client: `backend/internal/delivery/websocket/client.go`
  - 常數定義: Line 13-26
  - Ping/Pong: Line 59, 91-95
- WebSocket Hub: `backend/internal/delivery/websocket/hub.go`
  - 訊息路由: Line 155-270
