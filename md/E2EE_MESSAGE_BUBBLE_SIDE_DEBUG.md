# 訊息顯示位置錯誤診斷報告

## 問題描述

某台裝置上，原本應該顯示在右側（自己發的）的訊息跑到左側（對方發的）。

## 程式碼分析

### 1. 判斷邏輯位置

**檔案：** `app/lib/features/chat/ui/chat_detail_page.dart` (第 476 行)

```dart
final isMe = msg.senderId == widget.currentUserId;
```

### 2. currentUserId 的來源

**檔案：** `app/lib/features/chat/ui/room_list_page.dart`

```dart
// 第 40 行：從 storage 讀取
final userId = await storage.read('user_id');

// 第 51 行：設置到 state
_currentUserId = userId;

// 第 425 行：傳遞給 _openChat
onTap: () => _openChat(
  context,
  room.id,
  room.name,
  room.type == 'group',
  userId,  // ← 這裡傳遞 _currentUserId
  room.avatarUrl,
),

// 第 120 行：傳遞給路由
context.push(
  '/chat',
  extra: {
    'roomId': roomId,
    'title': title,
    'isRoom': isRoom,
    'currentUserId': userId,  // ← 這裡傳遞給 ChatDetailPage
    'token': token,
    'avatarUrl': avatarUrl,
  },
);
```

### 3. 後端設置 senderId

**檔案：** `backend/internal/delivery/websocket/controller.go` (第 107 行)

```go
msg.SenderID = client.userID
```

後端會自動將 `SenderID` 設置為當前 WebSocket 連接的 `client.userID`。

### 4. 解密邏輯

**檔案：** `app/lib/features/chat/providers/chat_room_provider.dart`

解密邏輯 `_tryDecryptMessage()` 不會修改 `senderId`，只會解密 `content` 和提取 `fileKey`。

## 可能的問題原因

### 原因 1：Storage 中的 user_id 被錯誤覆蓋

**症狀：**
- 用戶 A 登入後，`user_id` 儲存為 A
- 某個操作（如查看其他用戶資料）錯誤地將 `user_id` 覆蓋為 B
- 導致判斷邏輯錯誤：A 發的訊息被認為是 B 發的

**檢查方法：**
```dart
// 在 chat_detail_page.dart 的 build 方法中加入 debug log
@override
Widget build(BuildContext context) {
  debugPrint('🔍 [ChatDetailPage] currentUserId: ${widget.currentUserId}');
  // ...
}

// 在訊息列表中加入 debug log
final isMe = msg.senderId == widget.currentUserId;
debugPrint('🔍 [Message] id: ${msg.id}, senderId: ${msg.senderId}, currentUserId: ${widget.currentUserId}, isMe: $isMe');
```

### 原因 2：多裝置登入導致 WebSocket 連接混亂

**症狀：**
- 同一帳號在多個裝置登入
- WebSocket 連接的 `client.userID` 可能不一致
- 導致後端設置的 `senderId` 錯誤

**檢查方法：**
- 確認是否有多個裝置同時登入同一帳號
- 檢查後端日誌，確認 WebSocket 連接的 `userID`

### 原因 3：群組訊息 fanout 解密後 senderId 被修改

**症狀：**
- 群組訊息使用 `encrypted_contents_fanout`
- 解密邏輯可能錯誤地修改了 `senderId`

**檢查方法：**
```dart
// 在 _tryDecryptMessage 函式中加入 debug log
Future<Message> _tryDecryptMessage(Message m) async {
  debugPrint('🔍 [Decrypt] BEFORE - id: ${m.id}, senderId: ${m.senderId}');
  
  // ... 解密邏輯 ...
  
  debugPrint('🔍 [Decrypt] AFTER - id: ${result.id}, senderId: ${result.senderId}');
  return result;
}
```

**分析結果：** 已確認解密邏輯不會修改 `senderId`。

### 原因 4：本地資料庫中的訊息 senderId 錯誤

**症狀：**
- 訊息儲存到本地資料庫時，`senderId` 被錯誤設置
- 從本地資料庫讀取時，`senderId` 已經是錯誤的

**檢查方法：**
```dart
// 在 LocalDbService 的 insertMessages 中加入 debug log
Future<void> insertMessages(List<Message> messages) async {
  for (final msg in messages) {
    debugPrint('🔍 [LocalDB] Inserting - id: ${msg.id}, senderId: ${msg.senderId}');
  }
  // ...
}
```

## 建議的診斷步驟

### 步驟 1：加入 Debug Log

在以下位置加入 debug log：

1. **ChatDetailPage.build()**
   ```dart
   debugPrint('🔍 [ChatDetailPage] currentUserId: ${widget.currentUserId}');
   ```

2. **訊息列表渲染**
   ```dart
   final isMe = msg.senderId == widget.currentUserId;
   debugPrint('🔍 [Message] id: ${msg.id}, senderId: ${msg.senderId}, currentUserId: ${widget.currentUserId}, isMe: $isMe, content: ${msg.content.substring(0, min(20, msg.content.length))}');
   ```

3. **WebSocket 接收訊息**
   ```dart
   } else if (event == 'chat_message') {
     try {
       final rawMessage = Message.fromJson(payload);
       debugPrint('🔍 [WebSocket] Received - id: ${rawMessage.id}, senderId: ${rawMessage.senderId}');
       // ...
     }
   }
   ```

4. **本地資料庫操作**
   ```dart
   Future<void> insertMessages(List<Message> messages) async {
     for (final msg in messages) {
       debugPrint('🔍 [LocalDB] Insert - id: ${msg.id}, senderId: ${msg.senderId}');
     }
     // ...
   }
   ```

### 步驟 2：檢查 Storage

在問題裝置上執行：

```dart
final storage = ref.read(storageServiceProvider);
final userId = await storage.read('user_id');
debugPrint('🔍 [Storage] user_id: $userId');
```

確認 `user_id` 是否正確。

### 步驟 3：檢查後端日誌

查看後端日誌，確認：
1. WebSocket 連接時的 `userID`
2. 發送訊息時設置的 `msg.SenderID`
3. 是否有多個連接使用同一個 `userID`

### 步驟 4：清除本地資料

如果懷疑本地資料庫損壞，可以嘗試：

```dart
// 清除本地訊息資料庫
await LocalDbService().clearAllMessages();

// 清除 storage（需要重新登入）
await storage.delete('user_id');
await storage.delete('jwt_token');
```

## 修復建議

### 修復 1：加強 currentUserId 驗證

在 `ChatDetailPage` 的 `initState` 中加入驗證：

```dart
@override
void initState() {
  super.initState();
  
  // 驗證 currentUserId
  if (widget.currentUserId.isEmpty) {
    debugPrint('❌ [ChatDetailPage] currentUserId is empty!');
    // 重新從 storage 讀取
    _reloadCurrentUserId();
  }
  
  // ...
}

Future<void> _reloadCurrentUserId() async {
  final storage = ref.read(storageServiceProvider);
  final userId = await storage.read('user_id');
  if (userId != null && userId != widget.currentUserId) {
    debugPrint('⚠️ [ChatDetailPage] currentUserId mismatch! widget: ${widget.currentUserId}, storage: $userId');
    // 可以選擇重新導航或更新 state
  }
}
```

### 修復 2：在訊息顯示前再次驗證

```dart
final isMe = msg.senderId == widget.currentUserId;

// 加入額外驗證
if (msg.senderId.isEmpty) {
  debugPrint('⚠️ [Message] senderId is empty for message: ${msg.id}');
}
if (widget.currentUserId.isEmpty) {
  debugPrint('⚠️ [Message] currentUserId is empty');
}
```

### 修復 3：防止 Storage 被錯誤覆蓋

檢查所有寫入 `user_id` 的地方，確保只在登入時寫入：

```bash
# 搜尋所有寫入 user_id 的地方
grep -r "save.*'user_id'" app/lib/
```

確認只有以下地方應該寫入：
1. `auth_repository.dart` - 登入時
2. `profile_provider.dart` - 更新個人資料時（應該是同一個 ID）

## 相關檔案

### 前端
- `app/lib/features/chat/ui/chat_detail_page.dart` - 訊息顯示邏輯
- `app/lib/features/chat/ui/room_list_page.dart` - currentUserId 來源
- `app/lib/features/chat/providers/chat_room_provider.dart` - WebSocket 訊息處理
- `app/lib/core/storage/local_db_service.dart` - 本地資料庫

### 後端
- `backend/internal/delivery/websocket/controller.go` - 設置 senderId
- `backend/internal/delivery/websocket/hub.go` - 訊息廣播

## 測試建議

1. 在問題裝置上加入 debug log
2. 發送一條測試訊息
3. 觀察 log 輸出：
   - `currentUserId` 的值
   - `msg.senderId` 的值
   - `isMe` 的計算結果
4. 比對後端日誌中的 `SenderID`

## 結論

最可能的原因是 **Storage 中的 `user_id` 被錯誤覆蓋** 或 **本地資料庫中的 `senderId` 錯誤**。

建議先加入 debug log 確認問題根源，然後根據實際情況採取對應的修復措施。
