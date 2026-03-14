# E2EE 自己發送訊息解密失敗問題分析

## 問題現象

從測試截圖觀察到：

### 黑色手機（test2 - 私鑰遺失）
- ✅ 能看到對方發來的訊息（連結、網址）
- ✅ 能看到 Link preview（YouTube、Uber）
- ❌ 自己發的訊息顯示「解密失敗」

### 白色手機（test）
- ✅ 能看到對方發的圖片、文件
- ✅ 能看到自己發的連結
- ✅ 完全正常

## 根本原因分析

### E2EE 加密邏輯

在端到端加密系統中：

1. **對方發給你的訊息**
   - 用「你的公鑰」加密
   - 你用「你的私鑰」解密
   - ✅ 黑色手機能解密（說明新私鑰可用）

2. **你自己發的訊息備份**
   - 用「你的公鑰」加密一份備份給自己
   - 你用「你的私鑰」解密
   - ❌ 黑色手機無法解密（說明備份用的是舊公鑰加密）

### 問題核心

黑色手機生成了新的密鑰對（新私鑰 + 新公鑰），但：
- 新私鑰可以解密「對方用新公鑰加密的訊息」✅
- 新私鑰無法解密「自己用舊公鑰加密的訊息備份」❌

這說明：**自己發送的訊息備份仍然使用舊公鑰加密，而新私鑰無法解密舊公鑰加密的內容。**

## 當前 Re-encrypt Flow 的問題

### 現有流程

查看 `_handleReEncryptRequest` 方法（line 762-820）：

```dart
Future<void> _handleReEncryptRequest(Map<String, dynamic> payload) async {
  // 1. 獲取原始訊息
  final originalMessage = await LocalDbService().getMessageById(messageId);
  
  // 2. 驗證是自己發送的訊息
  if (originalMessage.senderId != arg.currentUserId) return;
  
  // 3. 獲取接收方的公鑰
  final receiverPublicKey = await _publicKeyCacheService.getPublicKey(receiverId);
  
  // 4. 重新加密
  reEncryptedContent = await _cryptoService.encryptMessage(
    originalMessage.content,  // ⚠️ 這裡的 content 是什麼？
    receiverPublicKey,
  );
  
  // 5. 發送 re_encrypt_response
  await _wsService.send('re_encrypt_response', {
    'message_id': messageId,
    'receiver_id': receiverId,
    're_encrypted_content': reEncryptedContent,
  });
}
```

### 關鍵問題

**`originalMessage.content` 的狀態是什麼？**

有兩種可能：

#### 情況 A：content 是明文（已解密）
- 發送方（黑色手機）能讀取到明文
- 重新加密成功
- 接收方（也是黑色手機）收到後用新私鑰解密
- ✅ 應該能成功

#### 情況 B：content 是密文（未解密）
- 發送方（黑色手機）讀取到的是舊密文
- 用新公鑰重新加密舊密文（加密了兩次！）
- 接收方（黑色手機）用新私鑰解密，得到舊密文
- 再用新私鑰嘗試解密舊密文 → ❌ 失敗（因為舊密文是用舊公鑰加密的）

## 診斷結果 ✅

### 發送訊息的實際邏輯

查看 `chat_room_provider.dart` 的 `sendMessage` 方法（line 1224-1310）：

```dart
Future<void> sendMessage(String content, ...) async {
  // 1. 創建臨時訊息（明文）
  final tempMessage = Message(
    id: clientMsgId,
    content: content,  // ✅ 明文
    senderId: arg.currentUserId,
    // ...
  );

  // 2. 儲存到 LocalDB（明文）
  await LocalDbService().insertMessages([tempMessage]);  // ✅ 儲存明文
  
  // 3. 加密內容用於網路傳輸
  String payloadContent = content;
  if (isE2EEEnabled) {
    if (arg.isRoom) {
      payloadContent = await _encryptGroupMessage(content, memberIds);
    } else {
      payloadContent = await _cryptoService.encryptMessage(content, pubKey);
    }
  }
  
  // 4. 通過 WebSocket 發送（密文）
  await _wsService.send('chat_message', {
    'content': payloadContent,  // ✅ 發送密文
    // ...
  });
}
```

### 關鍵發現

✅ **LocalDB 儲存的是明文**
- `tempMessage.content = content`（明文）
- `insertMessages([tempMessage])`（儲存明文）

✅ **網路傳輸的是密文**
- `payloadContent = await _cryptoService.encryptMessage(content, pubKey)`
- WebSocket 發送的是 `payloadContent`（密文）

### 結論

發送方的 LocalDB 確實儲存明文，這是正確的設計。那麼問題出在哪裡？

## 真正的問題：接收自己發送的訊息時儲存了密文 ❌

### 接收訊息的處理邏輯

查看 `chat_room_provider.dart` 的 `chat_message` 事件處理（line 158-180）：

```dart
} else if (event == 'chat_message') {
  try {
    final rawMessage = Message.fromJson(payload);  // ❌ 從 JSON 解析（密文）
    
    _tryDecryptMessage(rawMessage).then((message) {  // ✅ 解密
      if (...) {
        _addMessage(message);  // ✅ 添加到記憶體（明文）
        
        Future(
          () => LocalDbService().insertMessages([rawMessage]),  // ❌❌❌ 儲存密文！
        );
        // ...
      }
    });
  } catch (e) {
    debugPrint('Error parsing message: $e');
  }
}
```

### 關鍵問題

**儲存到 LocalDB 的是 `rawMessage`（密文），而不是 `message`（明文）！**

這導致：
1. 發送方發送訊息時，LocalDB 儲存明文 ✅
2. 但接收方（包括自己）收到訊息時，LocalDB 儲存密文 ❌
3. 當黑色手機發送訊息後，server 會回傳一份給自己（作為備份）
4. 黑色手機收到自己的訊息時，儲存的是密文（用舊公鑰加密）
5. 當黑色手機生成新密鑰對後，無法解密這些密文

### 為什麼對方發來的訊息能解密？

- 白色手機發送訊息給黑色手機
- 白色手機用黑色手機的「新公鑰」加密
- 黑色手機用「新私鑰」解密 ✅

### 為什麼自己發的訊息無法解密？

- 黑色手機發送訊息（用舊密鑰對）
- Server 回傳一份給黑色手機（用舊公鑰加密）
- 黑色手機收到後儲存密文到 LocalDB
- 黑色手機生成新密鑰對
- 黑色手機嘗試用新私鑰解密舊密文 ❌ 失敗

### Re-encrypt Flow 為什麼失敗？

查看 `_handleReEncryptRequest` 方法（line 762-820）：

```dart
Future<void> _handleReEncryptRequest(Map<String, dynamic> payload) async {
  // 1. 從 LocalDB 讀取原始訊息
  final originalMessage = await LocalDbService().getMessageById(messageId);
  
  // 2. 讀取 content
  // ❌ 如果這是「接收到的自己發送的訊息」，content 是密文！
  // ✅ 如果這是「發送時儲存的訊息」，content 是明文
  
  // 3. 重新加密
  reEncryptedContent = await _cryptoService.encryptMessage(
    originalMessage.content,  // ❌ 可能是密文
    receiverPublicKey,
  );
  // 結果：加密了密文（雙重加密）
}
```

### 為什麼會有兩份訊息？

當用戶發送訊息時：
1. **發送時儲存**：`sendMessage()` → `insertMessages([tempMessage])` → 儲存明文 ✅
2. **接收時儲存**：Server 回傳 → `chat_message` 事件 → `insertMessages([rawMessage])` → 儲存密文 ❌

第二次儲存會覆蓋第一次的明文！

## 解決方案

### 方案 1：接收訊息時儲存明文（推薦）✅

**原理**：修改 `chat_message` 事件處理邏輯，儲存解密後的訊息而不是原始密文。

**實施步驟**：

修改 `app/lib/features/chat/providers/chat_room_provider.dart` line 158-180：

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
        
        // 🔐 修復：儲存解密後的訊息，而不是原始密文
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

**優點**：
- 簡單直接，只需修改一行代碼
- 所有訊息（包括自己發送的）都儲存明文
- Re-encrypt flow 可以正常工作
- 符合「本地儲存明文，傳輸加密」的 E2EE 標準做法

**缺點**：
- 本地資料庫如果被攻擊，明文會洩露
- 但這是 E2EE 的標準做法（WhatsApp、Signal 都是這樣）

### 方案 2：避免重複儲存（補充優化）

**原理**：檢查訊息是否已存在，避免用密文覆蓋明文。

**實施步驟**：

```dart
} else if (event == 'chat_message') {
  try {
    final rawMessage = Message.fromJson(payload);
    _tryDecryptMessage(rawMessage).then((message) async {
      if (...) {
        _addMessage(message);
        
        // 🔐 檢查訊息是否已存在（避免覆蓋發送時儲存的明文）
        final existing = await LocalDbService().getMessageById(message.id);
        if (existing == null) {
          // 只有不存在時才儲存
          await LocalDbService().insertMessages([message]);
        } else if (!existing.isDecrypted && message.isDecrypted) {
          // 如果舊訊息未解密，新訊息已解密，則更新
          await LocalDbService().updateMessageContentAndStatus(
            messageId: message.id,
            newContent: message.content,
            newStatus: message.status,
          );
          await LocalDbService().markMessageAsDecrypted(message.id);
        }
        
        // ...
      }
    });
  } catch (e) {
    debugPrint('Error parsing message: $e');
  }
}
```

**優點**：
- 避免重複儲存
- 保留發送時儲存的明文
- 更精確的控制

**缺點**：
- 複雜度增加
- 需要額外的資料庫查詢

### 方案 3：標記自己發送的訊息（不推薦）

**原理**：檢查 `senderId == currentUserId`，如果是自己發送的訊息，不儲存。

**缺點**：
- 多設備同步時會有問題
- 換設備後看不到自己發送的訊息
- 不推薦

## 推薦實施方案

### 立即修復（方案 1）

修改 `app/lib/features/chat/providers/chat_room_provider.dart`：

```dart
} else if (event == 'chat_message') {
  try {
    final rawMessage = Message.fromJson(payload);
    _tryDecryptMessage(rawMessage).then((message) async {  // 改為 async
      if ((arg.isRoom && message.roomId == arg.roomId) ||
          (!arg.isRoom &&
              (message.senderId == arg.roomId ||
                  message.receiverId == arg.roomId))) {
        _addMessage(message);
        
        // 🔐 修復：儲存解密後的訊息
        await LocalDbService().insertMessages([message]);  // 改為 message
        
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

### 後續優化（方案 2）

添加重複檢查邏輯，避免覆蓋已存在的明文。

### 測試驗證

1. **測試新訊息**
   - 黑色手機發送新訊息
   - 驗證 LocalDB 儲存明文
   - 模擬金鑰遺失，觸發 re-encrypt
   - 驗證能成功解密

2. **測試舊訊息**
   - 對於已經儲存密文的舊訊息
   - 標記為「🔐 訊息無法復原」
   - 或實施方案 2（先解密再加密）

3. **測試對方訊息**
   - 白色手機發送訊息給黑色手機
   - 驗證黑色手機能正常解密和儲存

## 相關文件

- [E2EE Key Recovery Implementation](./E2EE_KEY_RECOVERY_IMPLEMENTATION.md)
- [E2EE Auto-Resend Implementation](./E2EE_AUTO_RESEND_IMPLEMENTATION.md)
- [Chat Room Provider](./app/lib/features/chat/providers/chat_room_provider.dart)

## 結論

問題的核心在於：**黑色手機生成新密鑰對後，無法解密自己用舊公鑰加密的訊息備份。**

Re-encrypt flow 沒有成功的原因可能是：
1. LocalDB 儲存的是密文（用舊公鑰加密）
2. Re-encrypt 時直接用密文重新加密（雙重加密）
3. 接收方解密後得到的還是舊密文，無法用新私鑰解密

推薦的解決方案是：
1. 確保 LocalDB 儲存明文（發送方）
2. 標記舊訊息為不可恢復
3. 未來考慮支援本地加密選項
