# 實作任務：已連結裝置 (Linked Devices)

## 任務 1：後端 - LinkedDevice Domain 與 Repository

- [x] 1.1 在 `backend/internal/domain/` 新增 `linked_device.go`，定義 `LinkedDevice` 結構體、`LinkedDeviceRepository` 介面、`LinkedDeviceUsecase` 介面
- [x] 1.2 在 `backend/internal/domain/` 新增 `offline_linked_message.go`，定義 `OfflineLinkedMessage` 結構體與 `OfflineLinkedMessageRepository` 介面
- [x] 1.3 擴展 `backend/internal/domain/auth.go`，新增 `QRTokenDetail` 結構體與 `AuthRepository` 新方法（`SaveQRTokenWithPublicKey`、`GetQRTokenDetail`、`MarkQRTokenUsed`、速率限制方法）
- [x] 1.4 在 `backend/internal/repository/mongo_repo/` 新增 `linked_device_repo.go`，實作 `LinkedDeviceRepository`（含 MongoDB TTL 索引設定）
- [x] 1.5 在 `backend/internal/repository/mongo_repo/` 新增 `offline_linked_message_repo.go`，實作 `OfflineLinkedMessageRepository`（含 7 天 TTL 索引）
- [x] 1.6 擴展 `backend/internal/repository/redis_repo/` 的 Auth Repository，實作新增的 QR Token 方法與速率限制方法

## 任務 2：後端 - LinkedDevice Usecase

- [x] 2.1 在 `backend/internal/usecase/` 新增 `linked_device_usecase.go`，實作 `LinkDevice`（含裝置數量上限檢查）、`UnlinkDevice`、`UnlinkAllDevices`、`GetLinkedDevices`、`GetLinkedDeviceCount`、`DeliverSessionKey`
- [x] 2.2 擴展 `backend/internal/usecase/auth_usecase.go`，修改 `ConfirmQRToken` 加入一次性使用驗證、速率限制檢查、LinkedDevice 記錄建立
- [x] 2.3 為 `linked_device_usecase.go` 撰寫屬性測試，驗證 Property 1（裝置數量上限不變量）
  - [x] 2.3.pbt Property 1: 裝置數量上限不變量 — *For any* 使用者，其已連結裝置數量在任何操作後都不應超過 4 台
- [x] 2.4 為 `auth_usecase.go` 撰寫屬性測試，驗證 Property 2（QR Token 一次性使用）與 Property 3（過期 Token 拒絕）
  - [x] 2.4.pbt Property 2: QR Token 一次性使用 — *For any* QR Token，被成功確認使用一次後，後續確認請求都應回傳錯誤
  - [x] 2.4.pbt Property 3: 過期 QR Token 拒絕確認 — *For any* 已過期的 QR Token，確認請求應回傳錯誤
- [x] 2.5 為速率限制邏輯撰寫屬性測試，驗證 Property 10（連結失敗速率限制）
  - [x] 2.5.pbt Property 10: 連結失敗速率限制 — *For any* 使用者在 5 分鐘內連續失敗 5 次後，後續連結請求應被封鎖 15 分鐘

## 任務 3：後端 - API Handler 與 WebSocket 擴展

- [x] 3.1 在 `backend/internal/delivery/http/` 新增 `linked_device_handler.go`，實作 `GET /api/v1/devices/linked`、`DELETE /api/v1/devices/linked/:id`、`POST /api/v1/devices/session-key` 端點
- [x] 3.2 擴展 `backend/internal/delivery/http/auth_handler.go` 的 `ConfirmQRToken`，新增 LinkedDevice 建立、公鑰回傳、速率限制檢查
- [x] 3.3 擴展 `backend/internal/delivery/websocket/hub.go`，新增 `SendSessionKey`、`SendDeviceUnlinked`、`BroadcastReadStatusSync` 方法
- [x] 3.4 擴展 `backend/internal/delivery/websocket/hub.go` 的 `routeMessage`，加入已連結裝置的訊息扇出邏輯
- [x] 3.5 為訊息扇出邏輯撰寫屬性測試，驗證 Property 5（訊息扇出至所有使用者裝置）
  - [x] 3.5.pbt Property 5: 訊息扇出至所有使用者裝置 — *For any* 使用者的任一裝置發送的訊息，應轉發給該使用者的所有其他裝置
- [x] 3.6 實作離線訊息暫存邏輯，當已連結裝置離線時將訊息存入 `offline_messages_linked`
- [x] 3.7 實作裝置重新上線時的離線訊息送達邏輯
- [x] 3.8 為離線訊息邏輯撰寫屬性測試，驗證 Property 6（離線暫存與 TTL）與 Property 7（時間順序送達）
  - [x] 3.8.pbt Property 6: 離線訊息暫存與 7 天 TTL — *For any* 離線期間產生的訊息，應被儲存且 ExpiresAt 設定為建立時間加 7 天
  - [x] 3.8.pbt Property 7: 離線訊息依時間順序送達 — *For any* 裝置重新上線時，離線訊息應按 CreatedAt 嚴格遞增排序
- [x] 3.9 擴展使用者登出邏輯，呼叫 `UnlinkAllDevices` 級聯取消所有連結
- [x] 3.10 為登出級聯邏輯撰寫屬性測試，驗證 Property 11（登出級聯取消所有連結）
  - [x] 3.10.pbt Property 11: 登出級聯取消所有連結 — *For any* 使用者登出後，GetLinkedDevices 應回傳空清單

## 任務 4：Flutter - 設定頁面與裝置管理頁面

- [x] 4.1 擴展 `app/lib/features/settings/` 設定頁面，在「分類名單」之後新增「已連結裝置」入口項目，含數量徽章
- [x] 4.2 在 `app/lib/features/settings/` 新增 `linked_devices_page.dart`，實作裝置管理頁面（裝置清單、空狀態、連結新裝置按鈕、上限提示）
- [x] 4.3 在 `app/lib/features/settings/providers/` 新增 `linked_devices_provider.dart`，使用 Riverpod StateNotifierProvider 管理裝置清單狀態
- [x] 4.4 實作左滑/長按取消連結互動與確認對話框
- [x] 4.5 為數量徽章邏輯撰寫屬性測試，驗證 Property 13（數量徽章條件顯示）
  - [x] 4.5.pbt Property 13: 數量徽章條件顯示 — *For any* 已連結裝置數量 n，n > 0 時顯示徽章，n = 0 時不顯示

## 任務 5：Flutter - QR 掃描與連結流程

- [x] 5.1 新增 `mobile_scanner` 依賴至 `app/pubspec.yaml`
- [x] 5.2 在 `app/lib/features/settings/` 新增 `qr_scanner_page.dart`，實作 QR Code 掃描頁面
- [x] 5.3 實作掃描成功後的連結確認對話框（顯示「確認連結」與「取消」按鈕）
- [x] 5.4 實作確認連結 API 呼叫（POST `/api/v1/auth/qr/confirm`），處理成功與各種錯誤回應
- [x] 5.5 實作連結成功後的推播通知（「新裝置已連結」）

## 任務 6：Flutter - Session Key 產生與分發

- [x] 6.1 擴展 `app/lib/core/crypto/crypto_service.dart`，新增 `generateSessionKey()` 方法（產生 AES-256 對稱金鑰）
- [x] 6.2 擴展 `CryptoService`，新增 `encryptSessionKeyForDevice(sessionKey, devicePublicKey)` 方法
- [x] 6.3 實作 Session Key 分發邏輯：連結成功後呼叫 `POST /api/v1/devices/session-key` 傳送加密金鑰
- [x] 6.4 實作取消連結後的金鑰重新分發邏輯（為剩餘裝置產生新 Session Key）
- [x] 6.5 為 Session Key 加密解密撰寫屬性測試，驗證 Property 4（Session Key 加密解密往返）
  - [x] 6.5.pbt Property 4: Session Key 加密解密往返 — *For any* 隨機 Session Key 與 X25519 金鑰對，加密後解密應得到原始值

## 任務 7：React Web - QR 登入頁面擴展

- [x] 7.1 擴展 `web/src/pages/QrLogin.jsx`，新增 QR Token 過期倒數計時器（3 分鐘）
- [x] 7.2 實作剩餘不足 30 秒時自動重新產生 QR Code 邏輯
- [x] 7.3 新增「QR Code 已過期」提示與「重新產生」按鈕
- [x] 7.4 更新說明文字為「使用 ChatWMEX 手機版掃描 QR Code 登入」
- [x] 7.5 新增等待掃描時的載入動畫狀態

## 任務 8：React Web - CryptoService 與 Session Key 接收

- [x] 8.1 在 `web/src/` 新增 `crypto/webCryptoService.js`，使用 Web Crypto API 實作 X25519 金鑰對產生
- [x] 8.2 實作 Session Key 接收與解密邏輯（監聽 `session_key_delivery` WebSocket 事件）
- [x] 8.3 實作 IndexedDB 安全儲存 Session Key 的邏輯
- [x] 8.4 實作 `decryptMessage(encryptedContent, sessionKey)` 方法供聊天頁面使用
- [x] 8.5 擴展 `web/src/hooks/useWebSocket.js`，新增 `session_key_delivery` 與 `device_unlinked` 事件處理

## 任務 9：React Web - 連結撤銷與 JWT 驗證

- [x] 9.1 實作 `device_unlinked` 事件處理：清除本地會話資料（IndexedDB + localStorage）並導航至登入頁面
- [x] 9.2 實作頁面載入時的 JWT Token 有效性驗證（Auth Guard）
- [x] 9.3 擴展 `web/src/App.jsx` 路由，新增 Auth Guard 保護聊天頁面

## 任務 10：後端 - 已讀狀態同步與裝置活躍更新

- [x] 10.1 擴展 WebSocket Hub 的已讀回執處理，將已讀狀態同步至所有已連結裝置
- [x] 10.2 為已讀狀態同步撰寫屬性測試，驗證 Property 9（已讀狀態同步至所有裝置）
  - [x] 10.2.pbt Property 9: 已讀狀態同步至所有裝置 — *For any* 使用者在任一裝置上標記已讀，所有其他已連結裝置應收到已讀狀態
- [x] 10.3 實作 WebSocket 訊息收發時更新 `LinkedDevice.LastActiveAt` 的邏輯
- [x] 10.4 為裝置記錄完整性撰寫屬性測試，驗證 Property 14（連結成功建立裝置記錄）
  - [x] 10.4.pbt Property 14: 連結成功建立裝置記錄 — *For any* 成功連結，應建立包含所有必要欄位的 LinkedDevice 記錄，ExpiresAt 為連結時間加 30 天
- [x] 10.5 為取消連結後金鑰重新分發撰寫屬性測試，驗證 Property 15
  - [x] 10.5.pbt Property 15: 取消連結後金鑰重新分發 — *For any* 取消連結操作且仍有剩餘裝置，應為每個剩餘裝置產生新 Session Key
- [x] 10.6 為取消連結刪除記錄撰寫屬性測試，驗證 Property 8
  - [x] 10.6.pbt Property 8: 取消連結刪除裝置記錄 — *For any* 已連結裝置執行取消連結後，該裝置記錄應被刪除
- [x] 10.7 為裝置清單顯示完整資訊撰寫屬性測試，驗證 Property 12
  - [x] 10.7.pbt Property 12: 裝置清單顯示完整資訊 — *For any* 已連結裝置清單，每個項目應包含裝置名稱、平台類型和最後活躍時間

## 任務 11：後端 - 依賴注入與路由註冊

- [x] 11.1 在 `backend/cmd/` 的主程式中註冊 LinkedDevice Repository、Usecase 與 Handler
- [x] 11.2 在路由設定中註冊新的 API 端點
- [x] 11.3 設定 MongoDB 集合索引（`linked_devices` 的 TTL 索引、`offline_messages_linked` 的 TTL 索引）
