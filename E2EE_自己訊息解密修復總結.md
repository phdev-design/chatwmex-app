# E2EE 自己訊息解密失敗修復總結

## 問題現象

從你的測試截圖可以看到：

### 黑色手機（test2 - 私鑰遺失後生成新密鑰）
- ✅ 能看到對方發來的訊息（連結、網址）
- ✅ 能看到 Link preview（YouTube、Uber）
- ❌ 自己發的訊息顯示「解密失敗」

### 白色手機（test - 正常）
- ✅ 完全正常

## 根本原因

我找到問題了！**接收訊息時儲存了密文，而不是明文。**

### 問題代碼

`app/lib/features/chat/providers/chat_room_provider.dart` line 170：

```dart
} else if (event == 'chat_message') {
  final rawMessage = Message.fromJson(payload);  // 從 server 收到的密文
  _tryDecryptMessage(rawMessage).then((message) {  // 解密成功
    _addMessage(message);  // 添加明文到記憶體 ✅
    Future(
      () => LocalDbService().insertMessages([rawMessage]),  // ❌ 儲存密文！
    );
  });
}
```

### 問題流程

1. **黑色手機發送訊息「Hello」**
   - `sendMessage()` 儲存明文到 LocalDB ✅
   
2. **Server 回傳訊息給黑色手機（作為備份）**
   - 收到 `chat_message` 事件（密文）
   - 解密成功，添加到記憶體（明文）
   - 儲存到 LocalDB（密文）❌
   - **密文覆蓋了之前的明文！**

3. **黑色手機生成新密鑰對**
   - LocalDB 中的訊息是用舊公鑰加密的密文
   - 新私鑰無法解密舊密文 ❌

4. **Re-encrypt flow 失敗**
   - `_handleReEncryptRequest` 從 LocalDB 讀取訊息
   - 讀取到的是密文（不是明文）
   - 用新公鑰加密密文（雙重加密！）
   - 接收方解密後得到舊密文，無法再解密 ❌

## 修復方案

### 修改代碼

只需要修改 2 行代碼！

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
        await LocalDbService().insertMessages([message]);  // ✅ 改為 message
        
        if (message.senderId != arg.currentUserId) {
          // ... 現有邏輯 ...
        }
      }
    });
  } catch (e) {
    debugPrint('Error parsing message: $e');
  }
}
```

### 關鍵變更

1. `.then((message) {` → `.then((message) async {`
2. `Future(() => LocalDbService().insertMessages([rawMessage]))` → `await LocalDbService().insertMessages([message])`

就這麼簡單！

## 為什麼這樣修復有效？

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

## 為什麼對方發來的訊息能解密？

- 白色手機發送訊息給黑色手機
- 白色手機用黑色手機的「新公鑰」加密
- 黑色手機用「新私鑰」解密 ✅

## 為什麼自己發的訊息無法解密？

- 黑色手機發送訊息（用舊密鑰對）
- Server 回傳一份給黑色手機（用舊公鑰加密）
- 黑色手機收到後儲存密文到 LocalDB
- 黑色手機生成新密鑰對
- 黑色手機嘗試用新私鑰解密舊密文 ❌ 失敗

## 安全性說明

### 本地儲存明文是安全的嗎？

是的！這是 E2EE 的標準做法：
- **WhatsApp**：本地儲存明文
- **Signal**：本地儲存明文
- **Telegram Secret Chat**：本地儲存明文

### 為什麼可以接受？

1. **設備安全**：假設用戶的設備是安全的
2. **傳輸加密**：網路傳輸使用 E2EE
3. **系統保護**：iOS Keychain / Android Keystore 保護私鑰
4. **實用性**：本地加密會導致性能問題和複雜度增加

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

## 下一步

1. **測試修復**
   ```bash
   cd app
   flutter test
   ```

2. **驗證功能**
   - 發送新訊息
   - 模擬金鑰遺失
   - 驗證 re-encrypt flow

3. **部署更新**
   - 提交代碼
   - 發布新版本
   - 通知用戶更新

## 相關文件

- [詳細分析文檔](./E2EE_SELF_MESSAGE_DECRYPTION_ISSUE.md)
- [修復文檔](./E2EE_SELF_MESSAGE_FIX.md)
- [快速參考](./E2EE_SELF_MESSAGE_FIX_QUICK_REFERENCE.md)

## 總結

問題的核心是：**接收訊息時儲存了密文，導致 re-encrypt flow 無法正常工作。**

修復非常簡單：**儲存解密後的明文，而不是原始密文。**

這樣 re-encrypt flow 可以讀取明文進行重新加密，用戶在金鑰遺失後仍然可以查看自己發送的訊息。

修改只有 2 行代碼，但影響深遠，確保了 E2EE 系統的完整性和可用性！✅
