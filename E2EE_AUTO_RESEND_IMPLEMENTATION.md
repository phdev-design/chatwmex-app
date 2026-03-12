# E2EE Auto-Resend 機制實作文檔

## 概述

本文檔描述了 E2EE（端到端加密）自動重新加密機制的完整實作，該機制用於處理因金鑰輪換導致的訊息解密失敗。

## 功能特性

### 核心功能
1. **自動檢測解密失敗**：當訊息無法使用當前金鑰或歷史金鑰解密時，自動觸發重新加密流程
2. **重試機制**：每條訊息最多重試 2 次（總共 3 次嘗試）
3. **超時保護**：每次重試設定 10 秒超時，防止無限等待
4. **控制訊息**：使用 WebSocket 控制訊息（`re_encrypt_request` 和 `re_encrypt_response`），不持久化到資料庫
5. **UI 反饋**：顯示「正在同步金鑰...」載入指示器，提供良好的用戶體驗

### 支援場景
- ✅ 一對一聊天訊息解密失敗
- ✅ 群組聊天訊息解密失敗（fan-out 加密）
- ✅ 網路斷線後重連自動重試
- ✅ 發送方離線時的超時處理
- ✅ 並發解密失敗的獨立處理

## 架構設計

### 三階段實作

#### Phase 1: 基礎模型、本地資料庫與後端路由 ✅
- `app/lib/models/message.dart`: 新增 `MessageType.reEncryptRequest/Response`、`MessageStatus.decryptingRetry`、`decryptRetryCount` 欄位
- `app/lib/core/storage/local_db_service.dart`: 新增 `decrypt_retry_count` 欄位、相關查詢和更新方法
- `backend/internal/domain/message.go`: 新增控制訊息類型常數
- `backend/internal/delivery/websocket/controller.go`: 新增控制訊息處理器（不持久化）

#### Phase 2: 解密失敗攔截、重新加密邏輯、UI 更新 ✅
- `app/lib/core/crypto/crypto_service.dart`: 
  - 新增 `DecryptionFailureException` 異常類別
  - 修改 `decryptMessage()` 和 `decryptWithSymmetricKey()` 支援拋出異常
- `app/lib/features/chat/providers/chat_room_provider.dart`:
  - 修改 `_tryDecryptMessage()` 捕獲異常並觸發重試
  - 新增 `_handleDecryptionFailure()` 處理解密失敗
  - 新增 `_handleReEncryptRequest()` 處理重新加密請求（發送方）
  - 新增 `_handleReEncryptResponse()` 處理重新加密回應（接收方）
- `app/lib/features/chat/ui/widgets/message_bubble.dart`:
  - 新增 `MessageStatus.decryptingRetry` 狀態的 UI 顯示

#### Phase 3: 測試、邊緣情況處理和優化 ✅
- 創建完整的單元測試套件
- 改進錯誤處理和邊緣情況處理
- 添加安全性驗證和日誌優化

## 工作流程

### 接收方（解密失敗）
```
1. 收到加密訊息
2. 嘗試用當前金鑰解密 → 失敗
3. 嘗試用所有歷史金鑰解密 → 全部失敗
4. 拋出 DecryptionFailureException
5. 檢查重試次數（< 2）
6. 更新訊息狀態為 decryptingRetry
7. 發送 re_encrypt_request 控制訊息
8. 設定 10 秒超時計時器
9. 等待 re_encrypt_response 或超時
```

### 發送方（收到重新加密請求）
```
1. 收到 re_encrypt_request 控制訊息
2. 從 LocalDB 讀取原始明文訊息
3. 驗證訊息發送者是當前用戶（安全性檢查）
4. 獲取接收方的最新公鑰
5. 重新加密訊息
6. 發送 re_encrypt_response 控制訊息
```

### 接收方（收到重新加密回應）
```
1. 收到 re_encrypt_response 控制訊息
2. 驗證接收者是當前用戶（安全性檢查）
3. 檢查訊息是否仍處於 decryptingRetry 狀態
4. 使用當前金鑰解密
5. 解密成功 → 更新訊息內容和狀態為 delivered
6. 解密失敗 → 檢查重試次數，決定重試或標記為失敗
```

## 邊緣情況處理

### 1. 網路斷線
- **情況**：發送 `re_encrypt_request` 時網路斷線
- **處理**：訊息保持 `decryptingRetry` 狀態，重連後會自動處理

### 2. 發送方離線
- **情況**：發送方收不到 `re_encrypt_request`
- **處理**：10 秒超時後自動重試，最多 2 次

### 3. 原始訊息已刪除
- **情況**：發送方的 LocalDB 中找不到原始訊息
- **處理**：記錄日誌，不發送 `re_encrypt_response`，接收方超時後重試

### 4. 公鑰不可用
- **情況**：無法獲取接收方的公鑰
- **處理**：記錄日誌，不發送 `re_encrypt_response`，接收方超時後重試

### 5. 重新加密失敗
- **情況**：加密操作拋出異常
- **處理**：記錄日誌，不發送 `re_encrypt_response`，接收方超時後重試

### 6. 重新解密仍然失敗
- **情況**：收到 `re_encrypt_response` 後解密仍然失敗
- **處理**：檢查重試次數，未達上限則保持 `decryptingRetry` 狀態等待超時重試

### 7. 並發解密失敗
- **情況**：多條訊息同時解密失敗
- **處理**：每條訊息獨立處理，各自維護重試次數和超時計時器

### 8. 超過最大重試次數
- **情況**：重試 2 次後仍然失敗
- **處理**：標記為永久失敗（`MessageStatus.failed`），顯示「🔒 此訊息無法解密（金鑰已更新）」

## 安全性考量

### 1. 身份驗證
- **發送方**：驗證 `re_encrypt_request` 中的訊息確實由當前用戶發送
- **接收方**：驗證 `re_encrypt_response` 中的接收者是當前用戶

### 2. 日誌安全
- 不在日誌中輸出明文內容
- 只記錄訊息 ID、用戶 ID 和錯誤類型

### 3. 控制訊息不持久化
- `re_encrypt_request` 和 `re_encrypt_response` 僅通過 WebSocket 傳輸
- 不寫入資料庫，避免敏感資訊洩露

## 向後兼容性

### 1. 舊版客戶端
- 忽略未知的控制訊息類型（`re_encrypt_request`、`re_encrypt_response`）
- 不影響現有功能

### 2. 可選參數
- `decryptMessage()` 和 `decryptWithSymmetricKey()` 的 `messageId` 和 `senderId` 參數為可選
- 未提供時使用舊行為（返回原文而不拋出異常）

## 測試

### 單元測試
位置：`app/test/features/chat/e2ee_auto_resend_test.dart`

測試範圍：
- ✅ DecryptionFailureException 的創建和屬性
- ✅ 重試次數邏輯（最多 2 次）
- ✅ 控制訊息格式驗證
- ✅ 超時機制（10 秒）
- ✅ 邊緣情況處理
- ✅ 向後兼容性
- ✅ 狀態轉換
- ✅ 性能考量
- ✅ 安全性驗證

### 執行測試
```bash
cd app
flutter test test/features/chat/e2ee_auto_resend_test.dart
```

## 性能優化

### 1. 非阻塞操作
- 所有重試操作都是異步的，不阻塞 UI 線程

### 2. 批次處理
- 並發解密失敗時，每條訊息獨立處理，避免相互影響

### 3. 超時控制
- 10 秒超時防止無限等待，及時釋放資源

### 4. 重試次數限制
- 最多 2 次重試，防止無限循環和資源浪費

## 監控和日誌

### 日誌級別
- **INFO**：正常流程（發送請求、收到回應、解密成功）
- **WARNING**：可恢復的錯誤（超時、公鑰不可用）
- **ERROR**：不可恢復的錯誤（超過最大重試次數、安全性驗證失敗）

### 關鍵日誌點
1. 解密失敗觸發重試
2. 發送 `re_encrypt_request`
3. 收到 `re_encrypt_request` 並處理
4. 發送 `re_encrypt_response`
5. 收到 `re_encrypt_response` 並解密
6. 超時觸發重試
7. 達到最大重試次數

### 日誌格式
```
[E2EE Auto-Resend] <操作描述>: <詳細資訊>
```

範例：
```
[E2EE Auto-Resend] Sending re_encrypt_request for message: msg-123 (attempt 1/2)
[E2EE Auto-Resend] Received re_encrypt_request for message: msg-123 from receiver: user-456
[E2EE Auto-Resend] Successfully re-decrypted message: msg-123
[E2EE Auto-Resend] Max retry attempts reached for message: msg-123
```

## 故障排除

### 問題 1：訊息一直顯示「正在同步金鑰...」
**可能原因**：
- 發送方離線
- 網路連接不穩定
- 發送方的 LocalDB 中找不到原始訊息

**解決方法**：
1. 檢查網路連接
2. 等待 10 秒超時後自動重試
3. 如果重試 2 次後仍然失敗，會顯示「此訊息無法解密」

### 問題 2：訊息顯示「此訊息無法解密（金鑰已更新）」
**可能原因**：
- 已達最大重試次數（2 次）
- 發送方的原始訊息已被刪除
- 金鑰確實不匹配且無法恢復

**解決方法**：
- 這是永久失敗狀態，無法自動恢復
- 建議聯繫發送方重新發送訊息

### 問題 3：重新加密請求沒有回應
**可能原因**：
- 發送方離線
- WebSocket 連接斷開
- 發送方的應用版本過舊（不支援此功能）

**解決方法**：
1. 確認發送方在線
2. 檢查 WebSocket 連接狀態
3. 建議發送方更新應用到最新版本

## 未來改進

### 短期（已規劃）
- [ ] 添加重試統計和監控指標
- [ ] 優化超時時間（根據網路狀況動態調整）
- [ ] 添加用戶手動重試按鈕

### 長期（待評估）
- [ ] 支援批次重新加密（多條訊息一次處理）
- [ ] 智能重試策略（根據失敗原因調整重試間隔）
- [ ] 離線訊息佇列（發送方離線時暫存請求）

## 相關文件

- [Phase 1 實作文檔](./PHASE1_IMPLEMENTATION.md)
- [Phase 2 實作文檔](./PHASE2_IMPLEMENTATION.md)
- [測試文檔](./app/test/features/chat/e2ee_auto_resend_test.dart)
- [API 文檔](./API_DOCUMENTATION.md)

## 版本歷史

- **v1.0.0** (2024-03-12): 初始版本，完成三階段實作
  - Phase 1: 基礎模型和資料庫
  - Phase 2: 核心邏輯和 UI
  - Phase 3: 測試和優化

## 貢獻者

- 開發團隊
- 測試團隊
- 安全審查團隊

## 授權

本專案採用 MIT 授權條款。
