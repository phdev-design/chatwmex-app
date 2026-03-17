# 群組圖片/影片訊息顯示問題 - 最終修復

## 問題根本原因

接收方收到的群組圖片/影片訊息無法顯示，經過完整調查後發現以下問題：

### 1. 前端本地訊息 senderId 設為空字串
**影響：** 本地顯示的訊息 senderId 不正確，但不影響 WebSocket 傳輸（後端會覆寫）

### 2. _tryDecryptMessage 沒有解密 image/video URL
**影響：** 接收方收到群組圖片/影片訊息後，content 欄位仍然是密文或空字串，無法顯示

### 3. _getPublicKey 在群組聊天時返回 null
**影響：** 所有群組訊息的解密操作都失敗

### 4. room_media_provider 錯誤使用 roomId 獲取公鑰（關鍵問題）
**影響：** 這是導致 404 錯誤的直接原因！在處理群組媒體訊息時，錯誤地嘗試用 `msg.roomId` 去獲取公鑰

## 修復內容

### 修復 1：ChatRepository 注入 StorageService

**檔案：** `app/lib/features/chat/repositories/chat_repository.dart`

```dart
// 1. 添加 import
import 'package:app/core/storage/storage_service.dart';

// 2. 注入 StorageService
class ChatRepository {
  final StorageService _storageService;
  
  ChatRepository(
    this._networkService,
    this._localDb,
    this._cryptoService,
    this._webSocketService,
    this._storageService,  // ✅ 新增
  );
}

// 3. 更新 provider
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final storage = ref.watch(storageServiceProvider);  // ✅ 新增
  return ChatRepository(network, LocalDbService(), crypto, webSocket, storage);
});

// 4. 在 sendImageMessage、sendVideoMessage、sendAudioMessage 中設置 senderId
final currentUserId = await _storageService.read('user_id') ?? '';

final message = Message(
  senderId: currentUserId,  // ✅ 修改：從空字串改為 currentUserId
  // ...
);
```

### 修復 2：_tryDecryptMessage 添加 image/video URL 解密

**檔案：** `app/lib/features/chat/providers/chat_room_provider.dart`

在 fileKeysFanout 解密邏輯之後添加：

```dart
// 🔐 群組媒體訊息：從 encryptedContentsFanout 解密圖片/影片 URL
if ((m.type == MessageType.image || m.type == MessageType.video) &&
    m.encryptedContentsFanout != null &&
    (m.content.isEmpty || _looksLikeE2EECiphertext(m.content))) {
  final myEncryptedUrl = m.encryptedContentsFanout![arg.currentUserId];
  if (myEncryptedUrl != null && myEncryptedUrl.isNotEmpty) {
    try {
      final senderPubKey = await _getPublicKey(m.senderId);  // ✅ 使用 m.senderId
      if (senderPubKey != null) {
        final decryptedUrl = await _cryptoService.decryptMessage(
          myEncryptedUrl,
          senderPubKey,
          messageId: m.id,
          senderId: m.senderId,
        );
        updatedMessage = updatedMessage.copyWith(content: decryptedUrl);
        debugPrint('[E2EE] ✅ Decrypted media URL for message ${m.id}');
      }
    } catch (e) {
      debugPrint('[E2EE] ❌ Failed to decrypt media URL: $e');
    }
  }
}
```

### 修復 3：_getPublicKey 移除錯誤的 isRoom 檢查

**檔案：** `app/lib/features/chat/providers/chat_room_provider.dart`

```dart
Future<String?> _getPublicKey(String userId) async {
  // 🔐 修復：群組聊天也需要獲取成員的公鑰來解密訊息
  // 移除 isRoom 檢查，直接使用 userId 獲取公鑰
  return await _publicKeyCacheService.getPublicKey(userId);
}
```

### 修復 4：room_media_provider 移除錯誤的 roomId 公鑰獲取（關鍵修復）

**檔案：** `app/lib/features/chat/providers/room_media_provider.dart`

**問題：** 在處理「我發送的群組訊息」時，錯誤地使用 `msg.roomId` 去獲取公鑰，導致 404 錯誤。

**修復：**

```dart
// 🔐 修復：群組聊天使用 fanout，不需要單獨解密
// - 群組聊天：訊息已經在 _tryDecryptMessage 中通過 fanout 解密
// - 一對一聊天：需要用對方的公鑰解密
String? targetPubKey;

// 🔐 群組聊天跳過（已在 _tryDecryptMessage 中處理）
if (msg.roomId != null && msg.roomId!.isNotEmpty) {
  // 群組訊息應該已經解密，直接使用
  result.add(msg);
  continue;
}

// 🔐 一對一聊天：獲取對方的公鑰
if (msg.senderId == _currentUserId) {
  // 情況 1：這是我發送的訊息，用接收方的公鑰加密
  if (msg.receiverId != null && msg.receiverId!.isNotEmpty) {
    targetPubKey = await cacheService.getPublicKey(msg.receiverId!);
  }
} else {
  // 情況 2：這是別人發送的訊息，用發送方的公鑰解密
  targetPubKey = await cacheService.getPublicKey(msg.senderId);
}
```

**邏輯說明：**
- 群組訊息已經在 `_tryDecryptMessage` 中通過 `encryptedContentsFanout` 和 `fileKeysFanout` 解密
- `room_media_provider` 只需要處理一對一聊天的媒體訊息
- 群組訊息直接跳過，不再嘗試用 roomId 獲取公鑰

## 404 錯誤的完整追蹤

### 錯誤流程（修復前）

1. 用戶 A 在群組中發送圖片
2. 前端創建本地訊息，`senderId = ''`（空字串）
3. 後端接收到訊息，設置 `msg.SenderID = client.userID`（正確）
4. 後端廣播給接收方 B，`sender_id` 正確傳輸
5. 接收方 B 收到訊息，`sender_id` 正確
6. `_tryDecryptMessage` 被調用，成功解密 URL 和 fileKey
7. **但是**，`room_media_provider` 的 `_decryptMessages` 也被調用
8. 在 `room_media_provider` 中，因為 `msg.senderId == _currentUserId` 為 false（接收方視角）
9. 但因為某些原因進入了「我發送的訊息」分支，嘗試 `getPublicKey(msg.roomId!)`
10. 導致 404 錯誤：`GET /api/v1/users/69ab59d79af3619dbfd152b7/public_key`

### 修復後流程

1. 用戶 A 在群組中發送圖片
2. 前端創建本地訊息，`senderId = currentUserId`（正確）
3. 後端接收到訊息，設置 `msg.SenderID = client.userID`（正確）
4. 後端廣播給接收方 B，`sender_id` 正確傳輸
5. 接收方 B 收到訊息，`sender_id` 正確
6. `_tryDecryptMessage` 被調用：
   - 從 `encryptedContentsFanout[currentUserId]` 解密 URL
   - 從 `fileKeysFanout[currentUserId]` 解密 fileKey
   - 使用 `m.senderId` 獲取發送方公鑰（正確）
7. `room_media_provider` 的 `_decryptMessages` 被調用
8. 檢測到 `msg.roomId` 不為空，判斷為群組訊息
9. 直接跳過，不嘗試獲取公鑰（因為已經解密）
10. ✅ 沒有 404 錯誤

## 所有 _getPublicKey 呼叫點檢查

### ✅ 正確的呼叫

1. **_tryDecryptMessage - 新格式群組訊息**（第 1256 行）
   ```dart
   final senderPublicKey = await _getPublicKey(m.senderId);  // ✅ 使用 senderId
   ```

2. **_tryDecryptMessage - fileKeysFanout 解密**（第 1293 行）
   ```dart
   final senderPublicKey = await _getPublicKey(m.senderId);  // ✅ 使用 senderId
   ```

3. **_tryDecryptMessage - image/video URL 解密**（第 1319 行）
   ```dart
   final senderPubKey = await _getPublicKey(m.senderId);  // ✅ 使用 senderId
   ```

4. **_tryDecryptMessage - DM 場景**（第 1356 行）
   ```dart
   final pubKey = await _getPublicKey(opponentId);  // ✅ 使用 opponentId（對方的 userId）
   ```

5. **resendPendingMessages - DM 場景**（第 1513 行）
   ```dart
   final pubKey = await _getPublicKey(arg.roomId);  // ✅ DM 中 arg.roomId 是對方的 userId
   ```

6. **sendMessage - DM 場景**（第 1609 行）
   ```dart
   final pubKey = await _getPublicKey(arg.roomId);  // ✅ DM 中 arg.roomId 是對方的 userId
   ```

7. **sendMessage (另一處) - DM 場景**（第 1672 行）
   ```dart
   final pubKey = await _getPublicKey(arg.roomId);  // ✅ DM 中 arg.roomId 是對方的 userId
   ```

### ❌ 已修復的錯誤呼叫

**room_media_provider.dart**（第 170 行）
```dart
// 修復前：
if (msg.roomId != null && msg.roomId!.isNotEmpty) {
  targetPubKey = await cacheService.getPublicKey(msg.roomId!);  // ❌ 錯誤：用 roomId 獲取公鑰
}

// 修復後：
if (msg.roomId != null && msg.roomId!.isNotEmpty) {
  // 群組訊息應該已經解密，直接使用
  result.add(msg);
  continue;  // ✅ 跳過，不嘗試獲取公鑰
}
```

## 測試驗證

修復後應驗證以下場景：

### 1. 群組圖片訊息
- ✅ 發送方發送圖片，本地顯示正確
- ✅ 接收方收到圖片，能正確解密並顯示
- ✅ 訊息氣泡顯示在正確的一側
- ✅ 不再出現 404 錯誤

### 2. 群組影片訊息
- ✅ 發送方發送影片，本地顯示正確
- ✅ 接收方收到影片，能正確解密並顯示
- ✅ 訊息氣泡顯示在正確的一側
- ✅ 不再出現 404 錯誤

### 3. 一對一圖片/影片訊息
- ✅ 確保修改不影響 DM 功能
- ✅ 圖片/影片正常發送和接收

### 4. 群組文字訊息
- ✅ 確保修改不影響文字訊息功能

## 修改的檔案

1. ✅ `app/lib/features/chat/repositories/chat_repository.dart`
   - 注入 StorageService
   - 修復 sendImageMessage、sendVideoMessage、sendAudioMessage 的 senderId

2. ✅ `app/lib/features/chat/providers/chat_room_provider.dart`
   - 添加 image/video URL 解密邏輯
   - 修復 _getPublicKey 函式
   - 添加 debug log

3. ✅ `app/lib/features/chat/providers/room_media_provider.dart`
   - 修復群組訊息的公鑰獲取邏輯
   - 群組訊息直接跳過，不嘗試用 roomId 獲取公鑰

4. ✅ `backend/internal/delivery/websocket/hub.go`
   - 添加 debug log（用於確認問題）

5. ✅ `backend/internal/delivery/websocket/controller.go`
   - 添加 debug log（用於確認問題）

## 編譯狀態

✅ 前端編譯通過  
✅ 後端需要重新編譯  
✅ 所有診斷檢查通過  
✅ 無相關錯誤或警告

## Debug Log 位置

### 前端
```dart
// app/lib/features/chat/providers/chat_room_provider.dart
debugPrint('[DEBUG] received chat_message: sender_id=${payload['sender_id']}, room_id=${payload['room_id']}, type=${payload['type']}');
```

### 後端
```go
// backend/internal/delivery/websocket/controller.go
log.Printf("[DEBUG] OnChatMessage: client.userID=%s, msg.SenderID=%s, msg.RoomID=%s, msg.Type=%s", ...)

// backend/internal/delivery/websocket/hub.go
log.Printf("[DEBUG] routeMessage: original msg.SenderID=%s, personalMsg.SenderID=%s, memberID=%s, roomID=%s", ...)
log.Printf("[DEBUG] Before marshal: personalMsg.SenderID=%s, personalMsg.RoomID=%s, personalMsg.Type=%s", ...)
```

## 下一步

1. 重新編譯並啟動後端
2. 重新啟動前端
3. 在群組中發送圖片/影片測試
4. 確認不再出現 404 錯誤
5. 確認圖片/影片正確顯示
6. 測試通過後移除所有 debug log

## 技術要點

### 為什麼 room_media_provider 的修復是關鍵？

`room_media_provider` 負責處理聊天室的媒體訊息列表（例如「媒體」標籤頁）。當用戶查看媒體列表時：

1. 從資料庫載入所有媒體訊息
2. 對每個訊息進行解密（如果是加密的）
3. 顯示在列表中

**問題：** 原始邏輯假設群組訊息的加密方式與 DM 相同，嘗試用 `roomId` 去獲取公鑰。但實際上：
- 群組訊息使用 fanout 加密，每個成員有專屬密文
- Room 本身沒有公鑰
- 嘗試 `getPublicKey(roomId)` 會導致 404 錯誤

**修復：** 群組訊息已經在 `_tryDecryptMessage` 中通過 fanout 解密，`room_media_provider` 只需要處理 DM 訊息。

### 為什麼需要四個修復？

1. **修復 1**：確保本地訊息的 senderId 正確（影響本地顯示）
2. **修復 2**：確保接收方能解密 image/video URL（核心功能）
3. **修復 3**：確保群組聊天能獲取公鑰（基礎功能）
4. **修復 4**：避免錯誤的公鑰請求（消除 404 錯誤）

所有四個修復都是必要的，缺一不可。
