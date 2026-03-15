# 群組圖片/影片訊息顯示問題修復

## 問題描述

群組圖片/影片訊息在接收方無法顯示，根本原因：

1. **senderId 設為空字串**：發送方創建本地訊息時，senderId 被設為空字串，導致後端可能錯誤地將其設置為 room_id
2. **URL 未解密**：接收方在 `_tryDecryptMessage()` 中，對 image/video 類型的訊息沒有從 `encrypted_contents_fanout` 取出並解密圖片/影片 URL
3. **_getPublicKey 邏輯錯誤**：群組聊天時直接返回 null，導致無法獲取發送方的公鑰進行解密

## 修復內容

### 修復 1：ChatRepository 注入 StorageService 並正確設置 senderId

**檔案：** `app/lib/features/chat/repositories/chat_repository.dart`

**變更：**

1. 在 imports 中添加 `StorageService`：
```dart
import 'package:app/core/storage/storage_service.dart';
```

2. 在 `ChatRepository` 類別中注入 `StorageService`：
```dart
class ChatRepository {
  final NetworkService _networkService;
  final LocalDbService _localDb;
  final CryptoService _cryptoService;
  final WebSocketService _webSocketService;
  final StorageService _storageService;  // ✅ 新增

  ChatRepository(
    this._networkService,
    this._localDb,
    this._cryptoService,
    this._webSocketService,
    this._storageService,  // ✅ 新增
  );
```

3. 更新 `chatRepositoryProvider`：
```dart
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  final crypto = ref.watch(cryptoServiceProvider);
  final webSocket = ref.watch(webSocketServiceProvider);
  final storage = ref.watch(storageServiceProvider);  // ✅ 新增
  return ChatRepository(network, LocalDbService(), crypto, webSocket, storage);  // ✅ 新增 storage
});
```

4. 在 `sendImageMessage()` 中正確設置 senderId：
```dart
// 6. Create message object for local optimistic update
final clientMsgId = const Uuid().v4();
final now = DateTime.now();

// 🔐 獲取當前用戶 ID
final currentUserId = await _storageService.read('user_id') ?? '';  // ✅ 新增

// ... content 處理邏輯 ...

final message = Message(
  id: clientMsgId,
  clientMsgId: clientMsgId,
  content: contentForLocal,
  senderId: currentUserId,  // ✅ 修改：從空字串改為 currentUserId
  receiverId: receiverId,
  roomId: roomId,
  type: MessageType.image,
  // ...
);
```

5. 在 `sendVideoMessage()` 中正確設置 senderId（同上）

6. 在 `sendAudioMessage()` 中正確設置 senderId（同上）

### 修復 2：_tryDecryptMessage 添加 image/video URL 解密邏輯

**檔案：** `app/lib/features/chat/providers/chat_room_provider.dart`

**變更：**

在 `_tryDecryptMessage()` 函式中，fileKeysFanout 解密邏輯之後，添加 image/video URL 解密：

```dart
// 🔐 群組媒體：從 fileKeysFanout 中提取並解密 fileKey
Message updatedMessage = m;
if (m.fileKeysFanout != null && m.fileKey == null) {
  // ... 現有的 fileKey 解密邏輯 ...
}

// 🔐 群組媒體訊息：從 encryptedContentsFanout 解密圖片/影片 URL  ✅ 新增
if ((m.type == MessageType.image || m.type == MessageType.video) &&
    m.encryptedContentsFanout != null &&
    (m.content.isEmpty || _looksLikeE2EECiphertext(m.content))) {
  final myEncryptedUrl = m.encryptedContentsFanout![arg.currentUserId];
  if (myEncryptedUrl != null && myEncryptedUrl.isNotEmpty) {
    try {
      final senderPubKey = await _getPublicKey(m.senderId);
      if (senderPubKey != null) {
        final decryptedUrl = await _cryptoService.decryptMessage(
          myEncryptedUrl,
          senderPubKey,
          messageId: m.id,
          senderId: m.senderId,
        );
        updatedMessage = updatedMessage.copyWith(content: decryptedUrl);
        debugPrint('[E2EE] ✅ Decrypted media URL for message ${m.id}');
      } else {
        debugPrint('[E2EE] ⚠️ Sender public key unavailable for media URL decryption: ${m.senderId}');
      }
    } catch (e) {
      debugPrint('[E2EE] ❌ Failed to decrypt media URL: $e');
    }
  }
}
```

**邏輯說明：**
- 檢查訊息類型是否為 image 或 video
- 檢查是否有 `encryptedContentsFanout` 資料
- 檢查 content 是否為空或看起來像密文
- 從 `encryptedContentsFanout[currentUserId]` 取出加密的 URL
- 使用發送方的公鑰解密 URL
- 將解密後的 URL 設置到 content 欄位

### 修復 3：_getPublicKey 移除錯誤的 isRoom 檢查

**檔案：** `app/lib/features/chat/providers/chat_room_provider.dart`

**變更：**

```dart
Future<String?> _getPublicKey(String userId) async {
  // 🔐 修復：群組聊天也需要獲取成員的公鑰來解密訊息
  // 移除 isRoom 檢查，直接使用 userId 獲取公鑰
  return await _publicKeyCacheService.getPublicKey(userId);
}
```

**原始錯誤邏輯：**
```dart
Future<String?> _getPublicKey(String userId) async {
  if (arg.isRoom) return null;  // ❌ 這會導致群組訊息無法解密
  return await _publicKeyCacheService.getPublicKey(userId);
}
```

**問題說明：**
- 原始邏輯在群組聊天時直接返回 null
- 這導致所有需要發送方公鑰的解密操作都失敗
- 群組訊息的解密同樣需要發送方的公鑰（用於 ECDH 密鑰交換）

## 測試驗證

修復後應驗證以下場景：

1. **群組圖片訊息**：
   - 發送方發送圖片後，本地訊息顯示正確（senderId 為發送方 user_id）
   - 接收方收到訊息後，能正確解密並顯示圖片
   - 訊息氣泡顯示在正確的一側（發送方右側，接收方左側）

2. **群組影片訊息**：
   - 發送方發送影片後，本地訊息顯示正確
   - 接收方收到訊息後，能正確解密並顯示影片
   - 訊息氣泡顯示在正確的一側

3. **後端日誌檢查**：
   - 不應再出現 `GET /api/v1/users/{room_id}/public_key` 的 404 錯誤
   - 所有公鑰請求都應使用正確的 user_id

4. **一對一聊天**：
   - 確保修改不影響一對一聊天的圖片/影片訊息功能

## 技術細節

### senderId 的重要性

1. **訊息歸屬**：正確的 senderId 用於判斷訊息是誰發送的
2. **氣泡位置**：前端根據 `senderId == currentUserId` 判斷訊息顯示在左側還是右側
3. **公鑰獲取**：解密時需要使用發送方的公鑰，senderId 必須是正確的 user_id

### encryptedContentsFanout 的作用

對於群組圖片/影片訊息：
- `fileKeysFanout`：存儲每個成員的加密 fileKey（用於解密圖片/影片檔案本身）
- `encryptedContentsFanout`：存儲每個成員的加密 URL（用於知道圖片/影片的位置）
- 兩者都是 Map<String, String>，key 為 userId，value 為該成員專屬的密文

### 解密流程

1. 接收方收到群組圖片/影片訊息
2. 從 `encryptedContentsFanout[currentUserId]` 取出加密的 URL
3. 使用發送方的公鑰（通過 senderId 獲取）解密 URL
4. 從 `fileKeysFanout[currentUserId]` 取出加密的 fileKey
5. 使用發送方的公鑰解密 fileKey
6. 使用解密後的 URL 下載加密的圖片/影片檔案
7. 使用解密後的 fileKey 解密檔案內容
8. 顯示圖片/影片

## 相關檔案

- `app/lib/features/chat/repositories/chat_repository.dart`
- `app/lib/features/chat/providers/chat_room_provider.dart`
- `app/lib/models/message.dart`
- `app/lib/core/storage/storage_service.dart`

## 編譯狀態

✅ 所有修改已通過編譯檢查
✅ 無診斷錯誤或警告
