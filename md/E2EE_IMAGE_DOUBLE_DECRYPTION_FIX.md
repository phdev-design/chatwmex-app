# E2EE 圖片雙層解密修復

## 問題診斷

### 症狀
- 文字訊息解密成功並正常顯示
- 圖片訊息解密後仍顯示「解密失敗」的綠色泡泡
- 網址（link 類型）訊息解密成功

### 根本原因
從日誌分析發現，圖片訊息使用了**雙層加密架構**：

```
原始圖片 URL (明文)
  ↓ 第一層：AES-GCM 對稱加密（使用 fileKey）
密文 B (Base64)
  ↓ 第二層：ECDH + AES-GCM 非對稱加密（使用接收方公鑰）
密文 A (Base64) - 存入資料庫
```

**問題所在**：`_handleReEncryptResponse` 只執行了第二層解密（ECDH），得到的是第一層的 AES 密文，而不是最終的 URL。

### 日誌證據

```
flutter: [E2EE Re-Encrypt Response] 📸 Message type: image
flutter: [E2EE Re-Encrypt Response] 📸 Full decrypted content: iA7PLzVvRYmI37rStcUO1zoilyZdWe9gYQx/SYAxOBK/dAztCsa8MC/LZRPraFJg+IVXFq0q6WMZEyh4AFpYezObCS4Ti0APCkXqO26b3w4=
flutter: [E2EE Re-Encrypt Response] 🖼️ Content looks like URL: false
flutter: [E2EE Re-Encrypt Response] 🖼️ Content looks like JSON: false
```

解密後的內容是 108 字元的 Base64 字串，不是 URL，也不是 JSON。

## 解決方案

### 修改檔案
`app/lib/features/chat/providers/chat_room_provider.dart`

### 實作邏輯

在 `_handleReEncryptResponse` 函式中，解密成功後加入媒體訊息的二次解密處理：

```dart
// 🖼️ 圖片/檔案訊息特殊處理：可能需要二次解密（AES 對稱加密）
String finalContent = decryptedContent;
if (originalMessage.type == MessageType.image || 
    originalMessage.type == MessageType.file ||
    originalMessage.type == MessageType.voice ||
    originalMessage.type == MessageType.video) {
  
  // 如果解密後的內容看起來還是 base64（不是 URL），可能需要二次解密
  if (!decryptedContent.startsWith('http') && 
      !decryptedContent.contains(' ') && 
      decryptedContent.length > 40 &&
      originalMessage.fileKey != null) {
    try {
      // 使用 fileKey 進行 AES 解密
      final encryptedBytes = base64Decode(decryptedContent);
      final decryptedBytes = await _cryptoService.decryptBytes(
        encryptedBytes,
        originalMessage.fileKey!,
      );
      finalContent = utf8.decode(decryptedBytes);
    } catch (e) {
      // 二次解密失敗，使用第一層解密結果
    }
  }
}

// 使用 finalContent 而非 decryptedContent 更新資料庫
await LocalDbService().updateMessageContentAndStatus(
  messageId: messageId,
  newContent: finalContent,
  newStatus: MessageStatus.delivered,
);
```

### 關鍵改進

1. **自動偵測媒體類型**：檢查 `MessageType.image/file/voice/video`
2. **智能判斷是否需要二次解密**：
   - 內容不是 URL（不以 `http` 開頭）
   - 內容看起來像 Base64（無空格、長度 > 40）
   - 訊息有 `fileKey` 欄位
3. **使用 CryptoService.decryptBytes**：利用現有的 AES-GCM 解密方法
4. **錯誤處理**：二次解密失敗時，保留第一層解密結果，避免完全失敗
5. **詳細日誌**：記錄每一步的解密過程，方便除錯

### 更新記憶體狀態

修復了一個 bug：記憶體中的訊息內容也需要使用 `finalContent`：

```dart
final updated = originalMessage.copyWith(
  content: finalContent,  // ✅ 修正：使用二次解密後的內容
  status: MessageStatus.delivered,
  isDecrypted: true,
);
```

## 測試驗證

### 預期行為

1. **圖片訊息**：
   - 第一層解密：得到 Base64 密文
   - 第二層解密：得到圖片 URL
   - UI 顯示：圖片正常載入並顯示

2. **文字訊息**：
   - 只需一層解密
   - 不受影響，繼續正常運作

3. **檔案/語音/影片**：
   - 與圖片相同的雙層解密邏輯
   - 解密後得到檔案 URL

### 驗證步驟

1. 重新執行 App
2. 查看之前顯示「解密失敗」的圖片訊息
3. 檢查日誌中的二次解密過程：
   ```
   [E2EE Re-Encrypt Response] 🖼️ Detected media message (image)
   [E2EE Re-Encrypt Response] 🔓 Attempting secondary AES decryption with fileKey...
   [E2EE Re-Encrypt Response] ✅ Secondary decryption succeeded!
   [E2EE Re-Encrypt Response] 📸 Final content: https://...
   ```
4. 確認圖片正常顯示

## 架構說明

### 為什麼需要雙層加密？

1. **第一層（AES 對稱加密）**：
   - 用途：加密圖片 URL 本身
   - 金鑰：隨機生成的 `fileKey`（存在訊息的 `file_key` 欄位）
   - 優點：快速、適合加密任意長度的資料

2. **第二層（ECDH 非對稱加密）**：
   - 用途：保護整個訊息內容（包含第一層密文）
   - 金鑰：接收方的公鑰 + 發送方的私鑰（ECDH 協商）
   - 優點：端到端加密，只有接收方能解密

### 完整流程

**發送方（加密）**：
```
1. 上傳圖片到伺服器 → 得到 URL
2. 生成隨機 fileKey
3. 用 fileKey 加密 URL → 密文 B
4. 用接收方公鑰加密密文 B → 密文 A
5. 將密文 A 和 fileKey 存入訊息
```

**接收方（解密）**：
```
1. 收到訊息（密文 A + fileKey）
2. 用自己的私鑰解密密文 A → 密文 B
3. 用 fileKey 解密密文 B → URL
4. 下載並顯示圖片
```

## 相關檔案

- `app/lib/features/chat/providers/chat_room_provider.dart` - 主要修改
- `app/lib/core/crypto/crypto_service.dart` - 提供 `decryptBytes` 方法
- `app/lib/models/message.dart` - 訊息模型（包含 `fileKey` 欄位）

## 注意事項

1. **fileKey 必須存在**：如果訊息沒有 `fileKey` 欄位，二次解密會被跳過
2. **向後兼容**：舊版本可能沒有使用雙層加密，程式碼會自動判斷並處理
3. **錯誤容忍**：二次解密失敗不會導致整個訊息失敗，會保留第一層解密結果

## 下一步

執行 App 並觀察日誌，確認：
1. 圖片訊息是否成功進行二次解密
2. 解密後的內容是否為有效的 URL
3. 圖片是否正常顯示在聊天室中
