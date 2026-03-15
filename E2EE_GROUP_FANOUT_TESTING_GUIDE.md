# 群組 E2EE Fan-out 功能測試指南

## 🚀 快速測試步驟

### 準備工作

1. 啟動後端服務
```bash
cd backend
go run cmd/main.go
```

2. 啟動 Flutter 應用（兩個實例）
```bash
# Terminal 1 - 用戶 A
cd app
flutter run

# Terminal 2 - 用戶 B
cd app
flutter run
```

### 測試場景 1：基本群組訊息加密

**目標**：驗證新的 `encrypted_contents_fanout` 欄位正常運作

**步驟**：
1. 用戶 A 創建一個包含用戶 B 和用戶 C 的群組
2. 用戶 A 發送一條文字訊息："測試 fan-out 加密"
3. 檢查 WebSocket payload（使用瀏覽器開發者工具或後端日誌）

**預期結果**：
```json
{
  "event": "chat_message",
  "data": {
    "content": "",
    "encrypted_contents_fanout": {
      "user_a_id": "base64_encrypted_content_for_a",
      "user_b_id": "base64_encrypted_content_for_b",
      "user_c_id": "base64_encrypted_content_for_c"
    },
    "room_id": "group_room_id",
    "type": "text"
  }
}
```

4. 用戶 B 和 C 應該能看到解密後的明文："測試 fan-out 加密"

### 測試場景 2：後端裁切邏輯

**目標**：驗證每個接收方只收到自己的密文

**步驟**：
1. 在後端 `hub.go` 的 `routeMessage()` 函式中加入日誌：
```go
log.Printf("🔐 Sending to member %s: content=%s, has_fanout=%v", 
    memberID, personalMsg.Content[:20], personalMsg.EncryptedContentsFanout != nil)
```

2. 用戶 A 發送群組訊息
3. 檢查後端日誌

**預期結果**：
```
🔐 Sending to member user_b_id: content=base64_encrypted..., has_fanout=false
🔐 Sending to member user_c_id: content=base64_encrypted..., has_fanout=false
```

### 測試場景 3：發送方收到完整 Fanout

**目標**：驗證發送方能收到完整的 fanout map（用於 LocalDB 存儲）

**步驟**：
1. 用戶 A 發送群組訊息
2. 在前端 `chat_room_provider.dart` 的 WebSocket 事件處理中加入日誌：
```dart
if (event == 'chat_message') {
  final rawMessage = Message.fromJson(payload);
  debugPrint('📥 Received message: has_fanout=${rawMessage.encryptedContentsFanout != null}');
  debugPrint('📥 Fanout keys: ${rawMessage.encryptedContentsFanout?.keys.toList()}');
}
```

3. 檢查用戶 A 的日誌

**預期結果**（用戶 A）：
```
📥 Received message: has_fanout=true
📥 Fanout keys: [user_a_id, user_b_id, user_c_id]
```

**預期結果**（用戶 B）：
```
📥 Received message: has_fanout=false
📥 Fanout keys: null
```

### 測試場景 4：向後相容性

**目標**：驗證舊格式訊息仍能正常顯示

**步驟**：
1. 使用舊版本應用發送一條群組訊息（或手動構造舊格式 payload）
```json
{
  "content": "{\"is_fanout\":true,\"ciphertexts\":{\"user_a_id\":\"...\",\"user_b_id\":\"...\"}}",
  "room_id": "group_room_id",
  "type": "text"
}
```

2. 新版本應用應該能正常解密並顯示

**預期結果**：
- 舊格式訊息正常顯示
- 新格式訊息正常顯示
- 兩種格式可以在同一聊天室中共存

### 測試場景 5：資料庫遷移

**目標**：驗證 SQLite 資料庫正確升級到版本 8

**步驟**：
1. 刪除應用資料（或使用舊版本資料庫）
2. 啟動新版本應用
3. 檢查資料庫版本和欄位

**驗證方法**（使用 SQLite 工具）：
```sql
-- 檢查版本
PRAGMA user_version;
-- 應該回傳 8

-- 檢查欄位
PRAGMA table_info(messages);
-- 應該包含 encrypted_contents_fanout 欄位
```

或檢查 `chat_cache.log` 檔案：
```json
{"time":"2024-...", "event":"db_upgrade", "data":{"action":"add_encrypted_contents_fanout_column"}}
```

### 測試場景 6：安全性驗證

**目標**：驗證非群組成員無法獲取其他成員的密文

**步驟**：
1. 用戶 A 和 B 在群組中
2. 用戶 C 不在群組中
3. 用戶 A 發送訊息
4. 攔截用戶 B 收到的 WebSocket payload

**預期結果**：
- 用戶 B 的 payload 中只有 `content` 欄位（自己的密文）
- 沒有 `encrypted_contents_fanout` 欄位
- 用戶 C 完全收不到訊息

## 🐛 常見問題排查

### 問題 1：接收方看到 "🔒 此訊息無法解密"

**可能原因**：
1. `encryptedContentsFanout` 中沒有該用戶的密文
2. 發送方的公鑰不正確
3. 解密邏輯有誤

**排查步驟**：
```dart
// 在 _tryDecryptMessage() 中加入日誌
debugPrint('🔍 encryptedContentsFanout: ${m.encryptedContentsFanout}');
debugPrint('🔍 currentUserId: ${arg.currentUserId}');
debugPrint('🔍 myCiphertext: ${m.encryptedContentsFanout?[arg.currentUserId]}');
```

### 問題 2：後端編譯錯誤

**錯誤訊息**：`undefined: EncryptedContentsFanout`

**解決方法**：
```bash
cd backend
go mod tidy
go build ./...
```

### 問題 3：Flutter 編譯錯誤

**錯誤訊息**：`The getter 'encryptedContentsFanout' isn't defined`

**解決方法**：
```bash
cd app
flutter clean
flutter pub get
flutter run
```

### 問題 4：資料庫遷移失敗

**錯誤訊息**：`duplicate column name: encrypted_contents_fanout`

**解決方法**：
1. 刪除應用資料
2. 或手動執行 SQL：
```sql
ALTER TABLE messages ADD COLUMN encrypted_contents_fanout TEXT;
```

## 📊 效能測試

### 測試大型群組

**目標**：驗證 100 人群組的加密效能

**步驟**：
1. 創建一個包含 100 個成員的群組
2. 發送一條訊息
3. 測量加密時間

**預期結果**：
- 加密時間 < 5 秒（批次處理，batch size = 10）
- 所有成員都能正常解密

**效能日誌**：
```dart
final startTime = DateTime.now();
final fanoutMap = await _encryptGroupMessageToMap(content, memberIds);
final duration = DateTime.now().difference(startTime);
debugPrint('⏱️ Encryption time for ${memberIds.length} members: ${duration.inMilliseconds}ms');
```

## ✅ 驗收檢查清單

完成以下所有測試後，功能即可上線：

- [ ] 測試場景 1：基本群組訊息加密
- [ ] 測試場景 2：後端裁切邏輯
- [ ] 測試場景 3：發送方收到完整 Fanout
- [ ] 測試場景 4：向後相容性
- [ ] 測試場景 5：資料庫遷移
- [ ] 測試場景 6：安全性驗證
- [ ] 效能測試：100 人群組
- [ ] 離線場景：接收方離線時發送訊息
- [ ] 多裝置場景：同一用戶在多個裝置上登入

## 🎯 下一步

測試通過後，可以考慮：
1. 新增單元測試和整合測試
2. 更新 API 文件
3. 通知前端團隊新的 payload 格式
4. 監控生產環境的加密效能
5. 規劃新成員加入群組的歷史訊息處理方案
