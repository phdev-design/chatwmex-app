# E2EE 自己發送訊息解密失敗修復

## 問題總結

黑色手機（test2）在私鑰遺失後生成新密鑰對，出現：
- ✅ 能解密對方發來的訊息
- ❌ 無法解密自己發送的訊息

## 根本原因

### 問題代碼

`app/lib/features/chat/providers/chat_room_provider.dart` line 158-180：

```dart
} else if (event == 'chat_message') {
  final rawMessage = Message.fromJson(payload);  // 密文
  _tryDecryptMessage(rawMessage).then((message) {  // 解密
    _addMessage(message);  // 添加明文到記憶體
    Future(
      () => LocalDbService().insertMessages([rawMessage]),  // ❌ 儲存密文！
    );
  });
}
```

### 問題流程

1. 黑色手機發送訊息
   - `sendMessage()` 儲存明文到 LocalDB ✅
   
2. Server 回傳訊息給黑色手機（作為備份）
   - 收到 `chat_message` 事件（密文）
   - 解密成功，添加到記憶體（明文）
   - 儲存到 LocalDB（密文）❌
   - **密文覆蓋了之前的明文！**

3. 黑色手機生成新密鑰對
   - LocalDB 中的訊息是用舊公鑰加密的密文
   - 新私鑰無法解密舊密文 ❌

4. Re-encrypt flow 失敗
   - `_handleReEncryptRequest` 從 LocalDB 讀取訊息
   - 讀取到的是密文（不是明文）
   - 用新公鑰加密密文（雙重加密）
   - 接收方解密後得到舊密文，無法再解密 ❌

## 修復方案

### 修改代碼

`app/lib/features/chat/providers/chat_room_provider.dart` line 158-180：

```dart
} else if (event == 'chat_message') {
  try {
    final rawMessage = Message.fromJson(payload);
    _tryDecryptMessage(rawMessage).then((message) async {  // 🔐 改為 async
      if ((arg.isRoom && message.roomId == arg.roomId) ||
          (!arg.isRoom &&
              (message.senderId == arg.roomId ||
                  message.receiverId == arg.roomId))) {
        _addMessage(message);
        
        // 🔐 修復：儲存解密後的訊息（明文），而不是原始密文
        // 這確保 re-encrypt flow 可以讀取明文進行重新加密
        await LocalDbService().insertMessages([message]);  // ✅ 儲存明文
        
        if (message.senderId != arg.currentUserId) {
          _wsService.send('message_delivered', {
            'message_id': message.id,
            'room_id': (arg.isRoom ? arg.roomId : null),
            'sender_id': message.senderId,
          });
          if (arg.isRoom) {
            markAsRead(message.id);
          } else {
            markConversationAsRead();
          }
        }
      }
    });
  } catch (e) {
    debugPrint('Error parsing message: $e');
  }
}
```

### 修改內容

1. 將 `.then((message) {` 改為 `.then((message) async {`
2. 將 `Future(() => LocalDbService().insertMessages([rawMessage]))` 改為 `await LocalDbService().insertMessages([message])`
3. 添加註解說明修復原因

## 修復效果

### 修復前

```
發送訊息流程：
1. sendMessage() → LocalDB 儲存明文 ✅
2. Server 回傳 → LocalDB 儲存密文 ❌（覆蓋明文）
3. 生成新密鑰對 → 無法解密密文 ❌
4. Re-encrypt → 加密密文（雙重加密）❌
```

### 修復後

```
發送訊息流程：
1. sendMessage() → LocalDB 儲存明文 ✅
2. Server 回傳 → LocalDB 儲存明文 ✅（覆蓋明文，但仍是明文）
3. 生成新密鑰對 → 可以讀取明文 ✅
4. Re-encrypt → 用明文重新加密 ✅
```

## 測試驗證

### 測試場景 1：新訊息正常流程

1. 黑色手機發送訊息「Hello」
2. 驗證 LocalDB 儲存明文「Hello」
3. Server 回傳訊息
4. 驗證 LocalDB 仍然是明文「Hello」
5. 白色手機能正常解密

### 測試場景 2：金鑰遺失後的 Re-encrypt

1. 黑色手機發送訊息「Test」
2. 黑色手機生成新密鑰對
3. 模擬解密失敗，觸發 re-encrypt
4. 驗證 `_handleReEncryptRequest` 讀取到明文「Test」
5. 驗證重新加密成功
6. 驗證黑色手機能解密「Test」

### 測試場景 3：對方發來的訊息

1. 白色手機發送訊息給黑色手機
2. 黑色手機接收並解密
3. 驗證 LocalDB 儲存明文
4. 驗證顯示正確

## 安全性考量

### 本地儲存明文的安全性

這是 E2EE 的標準做法：
- **WhatsApp**：本地儲存明文
- **Signal**：本地儲存明文
- **Telegram Secret Chat**：本地儲存明文

### 為什麼可以接受？

1. **設備安全**：假設用戶的設備是安全的
2. **傳輸加密**：網路傳輸使用 E2EE
3. **系統保護**：iOS Keychain / Android Keystore 保護私鑰
4. **實用性**：本地加密會導致性能問題和複雜度增加

### 如果需要更高安全性

未來可以實施：
1. 本地資料庫加密（SQLCipher）
2. 用戶設定選項（選擇是否本地加密）
3. Re-encrypt 時先解密再加密（支援本地加密）

## 相關文件

- [問題分析文檔](./E2EE_SELF_MESSAGE_DECRYPTION_ISSUE.md)
- [E2EE Key Recovery Implementation](./E2EE_KEY_RECOVERY_IMPLEMENTATION.md)
- [E2EE Auto-Resend Implementation](./E2EE_AUTO_RESEND_IMPLEMENTATION.md)

## 總結

這個修復解決了「自己發送的訊息無法解密」的問題，核心是確保 LocalDB 始終儲存明文，而不是密文。這樣 re-encrypt flow 可以正常工作，用戶在金鑰遺失後仍然可以查看自己發送的訊息。

修改非常簡單（只有 2 行代碼），但影響深遠，確保了 E2EE 系統的完整性和可用性。
