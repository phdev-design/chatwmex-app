# RoomMediaPage E2EE 解密修復說明

## 問題根源

你的系統使用了兩種不同的加密方式：

### 1. 一對一聊天 (1-on-1 Chat)
- **加密方式**: ECDH (Elliptic Curve Diffie-Hellman)
- **加密流程**: 
  - 發送者使用接收者的公鑰 + 自己的私鑰 → 生成共享密鑰 → 加密內容
- **解密流程**:
  - 接收者使用發送者的公鑰 + 自己的私鑰 → 生成相同的共享密鑰 → 解密內容
- **解密位置**: `chat_room_provider.dart` 的 `_tryDecryptMessage()` 方法
- **解密時機**: 訊息載入時自動解密

### 2. 群組聊天 (Room/Group Chat)
- **加密方式**: 對稱加密 (Symmetric Encryption)
- **加密流程**:
  - 使用當前用戶的私鑰作為對稱金鑰 → 加密內容
- **解密流程**:
  - 使用當前用戶的私鑰作為對稱金鑰 → 解密內容
- **解密位置**: **之前缺失！** 現在添加到 `crypto_service.dart`
- **解密時機**: **之前未解密！** 導致媒體櫃顯示加密亂碼

## 原始問題

### chat_room_provider.dart (第 529 行)
```dart
Future<Message> _tryDecryptMessage(Message m) async {
  if (arg.isRoom) return m;  // ❌ 群組訊息直接返回，不解密！
  // ... 一對一聊天的解密邏輯
}
```

這導致：
- 一對一聊天的訊息在 `chat_room_provider` 中被解密，`msg.content` 是明文 URL
- 群組聊天的訊息保持加密狀態，`msg.content` 是加密的 base64 字串

### room_media_provider.dart (原始版本)
```dart
Future<List<Message>> _decryptMediaContent(List<Message> messages) async {
  // ❌ 只使用 ECDH 解密（需要發送者公鑰）
  final decrypted = await cryptoService.decryptMessage(
    msg.content,
    senderPubKey,  // 群組訊息沒有發送者公鑰概念！
  );
}
```

結果：
- 一對一聊天的媒體可以顯示（因為已在 chat_room_provider 解密）
- 群組聊天的媒體無法顯示（加密內容無法用 ECDH 解密）

## 修復方案

### 1. 新增對稱金鑰解密方法 (crypto_service.dart)

```dart
/// 使用對稱金鑰解密（用於群組聊天）
/// 直接使用當前用戶的私鑰作為對稱金鑰
Future<String> decryptWithSymmetricKey(String encryptedOrPlainText) async {
  // Step 1: 先用當前私鑰解密
  final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();
  final symmetricKey = SecretKey(privateKeyBytes);
  
  // Step 2: 如果失敗，嘗試歷史私鑰
  final historyKeys = await _loadHistoryPrivateKeys();
  for (final histPrivKeyBase64 in historyKeys.reversed) {
    final histPrivKeyBytes = base64Decode(histPrivKeyBase64);
    final symmetricKey = SecretKey(histPrivKeyBytes);
    // 嘗試解密...
  }
  
  // Step 3: 所有金鑰都失敗，返回原文
  return encryptedOrPlainText;
}
```

### 2. 修改媒體解密邏輯 (room_media_provider.dart)

```dart
Future<List<Message>> _decryptMediaContent(List<Message> messages) async {
  // 判斷是否為群組聊天
  final isRoomChat = messages.isNotEmpty && messages.first.roomId != null;
  
  for (final msg in messages) {
    if (isRoomChat) {
      // ✅ 群組聊天：使用對稱金鑰解密
      decrypted = await cryptoService.decryptWithSymmetricKey(msg.content);
    } else {
      // ✅ 一對一聊天：使用 ECDH 解密
      decrypted = await cryptoService.decryptMessage(
        msg.content,
        senderPubKey,
      );
    }
  }
}
```

## 修復後的工作流程

### 一對一聊天媒體顯示
1. 後端返回加密的圖片 URL
2. `chat_room_provider` 使用 ECDH 解密 → `msg.content` = 明文 URL
3. `room_media_provider` 檢測到已是 URL，直接使用
4. UI 顯示圖片 ✅

### 群組聊天媒體顯示
1. 後端返回加密的圖片 URL
2. `chat_room_provider` 跳過解密 → `msg.content` = 加密字串
3. `room_media_provider` 檢測到是群組聊天，使用對稱金鑰解密 → 明文 URL
4. UI 顯示圖片 ✅

## 日誌輸出

修復後，你會看到以下日誌：

### 群組聊天
```
🔐 [RoomMedia] 使用對稱金鑰解密群組訊息: msg_123
✅ 對稱金鑰解密成功（當前金鑰）
✅ [RoomMedia] 成功解密 image: msg_123
📊 [RoomMedia] 解密完成: 10 則訊息 (原始: 10)
```

### 一對一聊天
```
🔐 [RoomMedia] 使用 ECDH 解密一對一訊息: msg_456
✅ [RoomMedia] 成功解密 image: msg_456
📊 [RoomMedia] 解密完成: 5 則訊息 (原始: 5)
```

## 測試建議

1. **測試群組聊天媒體**:
   - 在群組中發送圖片
   - 打開 RoomMediaPage
   - 確認圖片能正確顯示

2. **測試一對一聊天媒體**:
   - 在一對一聊天中發送圖片
   - 打開 RoomMediaPage
   - 確認圖片能正確顯示

3. **測試歷史訊息**:
   - 確認舊的加密訊息仍能解密
   - 確認金鑰更新後的訊息也能解密

4. **測試所有媒體類型**:
   - 圖片 (image)
   - 影片 (video)
   - 文件 (document)
   - 連結 (link)

## 潛在問題排查

如果修復後仍有問題：

1. **檢查 roomId 判斷邏輯**:
   ```dart
   final isRoomChat = messages.isNotEmpty && messages.first.roomId != null;
   ```
   確認群組訊息的 `roomId` 字段不為 null

2. **檢查加密格式**:
   - 確認群組訊息使用的是對稱加密（AES-GCM）
   - 確認加密格式為: nonce(12) + mac(16) + cipherText

3. **檢查金鑰存儲**:
   - 確認 `e2ee_private_key_history` 包含正確的歷史金鑰
   - 確認當前用戶的私鑰已初始化

4. **檢查後端 API**:
   - 確認 `/api/rooms/{roomId}/resources` 返回的訊息包含 `roomId` 字段
   - 確認群組訊息的 `content` 是加密的

## 相關文件

- `app/lib/core/crypto/crypto_service.dart` - 加密服務（新增對稱解密）
- `app/lib/features/chat/providers/room_media_provider.dart` - 媒體提供者（修改解密邏輯）
- `app/lib/features/chat/providers/chat_room_provider.dart` - 聊天室提供者（一對一解密）
- `app/lib/features/chat/ui/widgets/message_bubble.dart` - 訊息氣泡（顯示邏輯）
