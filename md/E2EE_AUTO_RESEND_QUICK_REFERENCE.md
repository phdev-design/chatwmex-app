# E2EE Auto-Resend 快速參考指南

## 🚀 快速開始

### 功能概述
當訊息因金鑰輪換無法解密時，系統會自動請求發送方使用接收方的最新公鑰重新加密訊息。

### 核心流程
```
解密失敗 → 發送 re_encrypt_request → 發送方重新加密 → 
發送 re_encrypt_response → 接收方解密 → 成功 ✅
```

---

## 📋 關鍵參數

| 參數 | 值 | 說明 |
|-----|---|------|
| 最大重試次數 | 2 | 總共 3 次嘗試（初始 + 2 次重試） |
| 超時時間 | 10 秒 | 每次重試的等待時間 |
| 控制訊息 | `re_encrypt_request`, `re_encrypt_response` | WebSocket 控制訊息 |
| 重試狀態 | `MessageStatus.decryptingRetry` | 訊息正在重試解密 |
| 失敗狀態 | `MessageStatus.failed` | 超過最大重試次數 |

---

## 🔧 主要 API

### CryptoService

```dart
// 解密訊息（支援拋出異常）
Future<String> decryptMessage(
  String encryptedOrPlainText,
  String senderPublicKeyBase64, {
  String? messageId,      // 可選：用於拋出異常
  String? senderId,       // 可選：用於拋出異常
})

// 對稱金鑰解密（群組訊息）
Future<String> decryptWithSymmetricKey(
  String encryptedOrPlainText, {
  String? messageId,      // 可選：用於拋出異常
  String? senderId,       // 可選：用於拋出異常
})
```

### LocalDbService

```dart
// 獲取訊息（包含重試次數）
Future<Message?> getMessageById(String messageId)

// 更新重試次數
Future<void> updateDecryptRetryCount(String messageId, int count)

// 更新訊息內容和狀態
Future<void> updateMessageContentAndStatus(
  String messageId,
  String content,
  MessageStatus status,
)
```

### ChatRoomViewModel

```dart
// 處理解密失敗（私有方法）
Future<void> _handleDecryptionFailure(
  Message message,
  DecryptionFailureException exception,
)

// 處理重新加密請求（私有方法）
Future<void> _handleReEncryptRequest(Map<String, dynamic> payload)

// 處理重新加密回應（私有方法）
Future<void> _handleReEncryptResponse(Map<String, dynamic> payload)
```

---

## 🎨 UI 狀態

### MessageStatus.decryptingRetry
```dart
// 顯示載入指示器
Row(
  children: [
    CircularProgressIndicator(strokeWidth: 2),
    SizedBox(width: 8),
    Text('正在同步金鑰...'),
  ],
)
```

### MessageStatus.failed
```dart
// 顯示失敗訊息
Text('🔒 此訊息無法解密（金鑰已更新）')
```

---

## 🔍 除錯技巧

### 查看日誌
所有相關日誌都以 `[E2EE Auto-Resend]` 開頭：

```bash
# 過濾 E2EE Auto-Resend 日誌
flutter logs | grep "E2EE Auto-Resend"
```

### 關鍵日誌訊息

```
✅ 正常流程:
[E2EE Auto-Resend] Sending re_encrypt_request for message: msg-123 (attempt 1/2)
[E2EE Auto-Resend] Received re_encrypt_request for message: msg-123 from receiver: user-456
[E2EE Auto-Resend] Sending re_encrypt_response for message: msg-123 to receiver: user-456
[E2EE Auto-Resend] Received re_encrypt_response for message: msg-123
[E2EE Auto-Resend] Successfully re-decrypted message: msg-123

⚠️ 超時重試:
[E2EE Auto-Resend] Timeout for message: msg-123, retrying...

❌ 達到最大重試次數:
[E2EE Auto-Resend] Max retry attempts reached for message: msg-123

🔒 安全性警告:
[E2EE Auto-Resend] Security warning: re_encrypt_request for message not sent by current user
[E2EE Auto-Resend] Security warning: re_encrypt_response not for current user
```

---

## 🐛 常見問題

### Q1: 訊息一直顯示「正在同步金鑰...」
**A**: 可能原因：
- 發送方離線
- 網路連接不穩定
- 發送方的原始訊息已刪除

**解決方法**: 等待 10 秒超時後自動重試，最多 2 次

### Q2: 訊息顯示「此訊息無法解密」
**A**: 已達最大重試次數（2 次），這是永久失敗狀態

**解決方法**: 聯繫發送方重新發送訊息

### Q3: 重新加密請求沒有回應
**A**: 可能原因：
- 發送方離線
- WebSocket 連接斷開
- 發送方應用版本過舊

**解決方法**: 確認發送方在線並使用最新版本

---

## 📊 監控指標

### 建議監控的指標

```dart
// 解密失敗率
decryptionFailureRate = failedDecryptions / totalDecryptions

// 重試成功率
retrySuccessRate = successfulRetries / totalRetries

// 平均重試次數
averageRetryCount = totalRetryAttempts / totalRetries

// 永久失敗率
permanentFailureRate = permanentFailures / totalDecryptions
```

### 告警閾值

| 指標 | 警告 | 嚴重 |
|-----|------|------|
| 解密失敗率 | > 5% | > 10% |
| 永久失敗率 | > 1% | > 5% |
| 平均重試次數 | > 1.5 | > 1.8 |

---

## 🧪 測試

### 執行測試
```bash
cd app
flutter test test/features/chat/e2ee_auto_resend_test.dart
```

### 測試覆蓋率
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## 🔐 安全性檢查清單

- [x] 驗證訊息發送者身份
- [x] 驗證訊息接收者身份
- [x] 不在日誌中輸出明文
- [x] 控制訊息不持久化
- [x] 使用最新公鑰重新加密
- [x] 限制重試次數防止 DoS

---

## 📱 用戶體驗

### 正常情況
1. 訊息解密失敗（用戶不可見）
2. 顯示「正在同步金鑰...」（< 1 秒）
3. 自動解密成功，顯示訊息內容

### 異常情況
1. 訊息解密失敗
2. 顯示「正在同步金鑰...」（10 秒）
3. 超時後重試（最多 2 次）
4. 失敗後顯示「🔒 此訊息無法解密（金鑰已更新）」

---

## 🔄 狀態轉換圖

```
delivered/sent
    ↓ (解密失敗)
decryptingRetry
    ↓ (成功)
delivered
    ↓ (失敗 + 重試次數 < 2)
decryptingRetry (重試)
    ↓ (失敗 + 重試次數 >= 2)
failed (永久失敗)
```

---

## 📞 支援

### 問題回報
如遇到問題，請提供以下資訊：
1. 訊息 ID
2. 相關日誌（`[E2EE Auto-Resend]` 開頭）
3. 重現步驟
4. 預期行為 vs 實際行為

### 聯繫方式
- GitHub Issues: [專案 Issues 頁面]
- Email: [支援信箱]
- Slack: [團隊頻道]

---

## 📚 延伸閱讀

- [完整實作文檔](./E2EE_AUTO_RESEND_IMPLEMENTATION.md)
- [實作總結](./E2EE_AUTO_RESEND_SUMMARY.md)
- [測試文件](./app/test/features/chat/e2ee_auto_resend_test.dart)

---

**最後更新**: 2024-03-12  
**版本**: v1.0.0
