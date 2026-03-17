# Requirements Document

## Introduction

本功能為 Web 前端（`/web/src`）補全 Phase 1 至 Phase 6 的所有缺失功能，使其成為與 Flutter App 對等的完整 E2EE 即時通訊用戶端。

現有 Web 前端已具備 QR 登入、基本 WebSocket 連線、Session Key 解密（IndexedDB）與歷史訊息載入。本 Spec 涵蓋：
- **Phase 1**：E2EE 加密發送（`encryptMessage` + Chat 整合）
- **Phase 2**：Re-encrypt 機制（`re_encrypt_request` / `re_encrypt_response` 事件處理）
- **Phase 3**：好友系統（API + Friends 頁面）
- **Phase 4**：群組功能（建立群組 + fanout 加密）
- **Phase 5**：在線狀態（`presence_update` 事件 + UI 顯示）
- **Phase 6**：個人設定（Profile 頁面、登出、Linked Devices）

---

## Glossary

- **Web_Client**：本 Spec 所描述的 Web 前端應用程式（`/web/src`）
- **CryptoService**：`web/src/crypto/webCryptoService.js` 中的加解密模組
- **SessionKeyStore**：`web/src/crypto/sessionKeyStore.js`，負責 IndexedDB 的 Session Key 存取
- **WebSocketHook**：`web/src/hooks/useWebSocket.js`，管理 WebSocket 連線與事件分派
- **API**：`web/src/api/index.js`，封裝後端 REST API 呼叫
- **Session_Key**：AES-256 對稱金鑰，以 base64 字串表示，儲存於 IndexedDB
- **Encrypted_Content**：格式為 `base64(nonce[12] + mac[16] + ciphertext)` 的加密訊息
- **Re_Encrypt_Request**：伺服器發送的 WebSocket 事件，要求 Web_Client 重新加密指定訊息
- **Re_Encrypt_Response**：Web_Client 回傳給伺服器的 WebSocket 事件，包含重新加密後的密文
- **Presence_Update**：伺服器發送的 WebSocket 事件，通知用戶在線狀態變更
- **Fanout_Map**：群組訊息加密結構，格式為 `{ userId: Encrypted_Content }` 的 JSON 物件
- **Linked_Device**：已與帳號配對的裝置（App 或 Web）

---

## Requirements

### Requirement 1：E2EE 訊息加密（Phase 1）

**User Story:** As a Web 用戶，I want 發送的訊息在傳輸前自動加密，so that 訊息內容不會以明文形式傳送至伺服器。

#### Acceptance Criteria

1. THE CryptoService SHALL 提供 `encryptMessage(plaintext, sessionKeyBase64)` 函式，接受 UTF-8 明文字串與 base64 Session Key，回傳 `Promise<string>`（Encrypted_Content）
2. WHEN `encryptMessage` 被呼叫，THE CryptoService SHALL 產生隨機 12-byte nonce，使用 AES-256-GCM 加密明文，並將結果以 `base64(nonce[12] + mac[16] + ciphertext)` 格式回傳
3. FOR ALL 有效的明文字串與 Session Key，`decryptMessage(encryptMessage(plaintext, key), key)` SHALL 回傳與原始明文相同的字串（round-trip 屬性）
4. WHEN `encryptMessage` 收到空字串明文，THE CryptoService SHALL 成功加密並回傳有效的 Encrypted_Content
5. IF Session Key 格式無效（非合法 base64 或長度不符 AES-256），THEN THE CryptoService SHALL 拋出描述性錯誤

### Requirement 2：Chat 頁面 E2EE 整合（Phase 1）

**User Story:** As a Web 用戶，I want 聊天介面自動處理加解密，so that 我能透明地收發加密訊息而無需手動操作。

#### Acceptance Criteria

1. WHEN 用戶在 Chat 頁面送出訊息，THE Web_Client SHALL 先從 SessionKeyStore 取得 Session_Key，再呼叫 `encryptMessage` 加密後透過 WebSocket 發送 Encrypted_Content
2. WHEN WebSocket 收到 `chat_message` 事件，THE Web_Client SHALL 呼叫 `decryptMessage` 解密 `content` 欄位，並將解密後的明文顯示於訊息泡泡
3. WHEN 載入歷史訊息，THE Web_Client SHALL 對每則訊息的 `content` 欄位呼叫 `decryptMessage` 解密後顯示
4. IF `decryptMessage` 拋出錯誤，THEN THE Web_Client SHALL 在訊息泡泡顯示「🔒 無法解密」提示文字，並記錄錯誤至 console
5. WHILE Session_Key 尚未載入，THE Web_Client SHALL 停用訊息輸入框並顯示「等待金鑰...」提示

### Requirement 3：Re-encrypt 機制（Phase 2）

**User Story:** As a Web 用戶，I want 系統自動處理金鑰輪換後的重新加密，so that 訊息在金鑰更新後仍可被正確解密。

#### Acceptance Criteria

1. WHEN WebSocket 收到 `re_encrypt_request` 事件，THE WebSocketHook SHALL 取出事件中的 `message_id` 與 `encrypted_content`，使用當前 Session_Key 解密後再以新 Session_Key 重新加密，並透過 WebSocket 發送 `re_encrypt_response` 事件
2. WHEN WebSocket 收到 `re_encrypt_response` 事件，THE WebSocketHook SHALL 以新密文更新對應 `message_id` 的訊息，並觸發 UI 重新渲染
3. IF `re_encrypt_request` 中的解密步驟失敗，THEN THE WebSocketHook SHALL 在 Chat 頁面對應訊息顯示「🔒 解密失敗」狀態，並自動向伺服器發送 `re_encrypt_request` 以請求重新加密
4. THE WebSocketHook SHALL 透過 callback（`onReEncryptRequest`、`onReEncryptResponse`）將 re-encrypt 事件暴露給消費者元件，以維持 hook 的可測試性
5. IF `re_encrypt_request` 事件中缺少 `message_id` 或 `encrypted_content` 欄位，THEN THE WebSocketHook SHALL 記錄錯誤至 console 並忽略該事件

### Requirement 4：好友系統 API（Phase 3）

**User Story:** As a Web 用戶，I want 管理好友關係，so that 我能控制誰可以與我通訊。

#### Acceptance Criteria

1. THE API SHALL 提供 `getFriends()` 函式，呼叫 `GET /api/v1/friends` 並回傳好友列表
2. THE API SHALL 提供 `sendFriendRequest(userId)` 函式，呼叫 `POST /api/v1/friends/request` 並回傳操作結果
3. THE API SHALL 提供 `acceptFriendRequest(requestId)` 函式，呼叫 `POST /api/v1/friends/accept` 並回傳操作結果
4. THE API SHALL 提供 `rejectFriendRequest(requestId)` 函式，呼叫 `POST /api/v1/friends/reject` 並回傳操作結果
5. THE API SHALL 提供 `blockUser(userId)` 函式，呼叫 `POST /api/v1/friends/block` 並回傳操作結果
6. THE API SHALL 提供 `unblockUser(userId)` 函式，呼叫 `POST /api/v1/friends/unblock` 並回傳操作結果
7. IF 任何好友 API 呼叫收到非 2xx HTTP 回應，THEN THE API SHALL 拋出包含 HTTP 狀態碼與伺服器錯誤訊息的 Error 物件

### Requirement 5：好友系統 UI（Phase 3）

**User Story:** As a Web 用戶，I want 在 Chat 側邊欄管理好友與好友請求，so that 我能在同一介面完成所有社交操作。

#### Acceptance Criteria

1. THE Web_Client SHALL 在 Chat 側邊欄提供三個 Tab：「Rooms」、「Friends」、「Requests」
2. WHEN 用戶切換至「Friends」Tab，THE Web_Client SHALL 呼叫 `getFriends()` 並顯示好友列表，每位好友旁提供「封鎖」按鈕
3. WHEN 用戶切換至「Requests」Tab，THE Web_Client SHALL 顯示待處理的好友請求列表，每筆請求提供「接受」與「拒絕」按鈕
4. WHEN 用戶在搜尋結果中點擊「加好友」，THE Web_Client SHALL 呼叫 `sendFriendRequest(userId)` 並在按鈕旁顯示「已送出」狀態
5. IF 好友 API 呼叫失敗，THEN THE Web_Client SHALL 以 toast 通知或行內錯誤訊息告知用戶操作失敗

### Requirement 6：群組建立（Phase 4）

**User Story:** As a Web 用戶，I want 建立群組聊天室，so that 我能與多位好友同時通訊。

#### Acceptance Criteria

1. THE API SHALL 提供 `createRoom(name, memberIds)` 函式，呼叫 `POST /api/v1/rooms` 並回傳新建立的 Room 物件
2. THE Web_Client SHALL 在 Chat 側邊欄「Rooms」Tab 提供「建立群組」入口（按鈕或圖示）
3. WHEN 用戶點擊「建立群組」，THE Web_Client SHALL 顯示對話框，允許輸入群組名稱並從好友列表勾選成員
4. WHEN 用戶確認建立，THE Web_Client SHALL 呼叫 `createRoom` 並在成功後將新群組加入側邊欄 Rooms 列表
5. IF `createRoom` 呼叫失敗，THEN THE Web_Client SHALL 顯示錯誤訊息並保持對話框開啟

### Requirement 7：群組訊息 Fanout 加密（Phase 4）

**User Story:** As a Web 用戶，I want 群組訊息對每位成員分別加密，so that 只有群組成員能解密各自的訊息副本。

#### Acceptance Criteria

1. THE API SHALL 提供 `getRoomMembers(roomId)` 函式，呼叫 `GET /api/v1/rooms/{roomId}/members` 並回傳成員列表（含各成員的 `public_key`）
2. WHEN 用戶在群組聊天室發送訊息，THE Web_Client SHALL 取得所有成員的公鑰，對每位成員分別以 ECDH + AES-256-GCM 加密明文，組成 `ciphertexts: { userId: Encrypted_Content }` Fanout_Map 後發送
3. WHEN Web_Client 收到群組訊息，THE Web_Client SHALL 從 `ciphertexts[myUserId]` 取出自己的密文，使用 Session_Key 解密後顯示
4. IF `ciphertexts[myUserId]` 不存在，THEN THE Web_Client SHALL 顯示「🔒 無法解密（未包含本裝置）」提示
5. THE CryptoService SHALL 提供 `encryptForRecipient(plaintext, recipientPublicKeyBase64, senderPrivateKey)` 函式，使用 X25519 ECDH 衍生共享金鑰後以 AES-256-GCM 加密，回傳 Encrypted_Content

### Requirement 8：在線狀態（Phase 5）

**User Story:** As a Web 用戶，I want 即時看到好友的在線狀態，so that 我知道對方是否能立即回覆。

#### Acceptance Criteria

1. WHEN WebSocket 收到 `presence_update` 事件，THE WebSocketHook SHALL 解析 `{ user_id, status }` payload 並透過 `onPresenceUpdate` callback 通知消費者元件
2. THE Web_Client SHALL 在 Chat 頁面維護 `onlineUsers` state（`Map<userId, status>`），並在收到 `presence_update` 時更新
3. WHEN 好友列表或聊天標題顯示用戶名稱，THE Web_Client SHALL 在名稱旁以綠色圓點（在線）或灰色圓點（離線）顯示在線狀態
4. WHILE WebSocket 未連線，THE Web_Client SHALL 將所有用戶狀態視為離線並顯示灰色圓點

### Requirement 9：個人設定頁面（Phase 6）

**User Story:** As a Web 用戶，I want 管理個人資料與帳號設定，so that 我能更新個人資訊並管理已連結的裝置。

#### Acceptance Criteria

1. THE Web_Client SHALL 提供 `Profile.jsx` 頁面，路由為 `/profile`，並在 Chat 頁面提供導航入口
2. THE API SHALL 提供 `getProfile()` 函式，呼叫 `GET /api/v1/users/me` 並回傳當前用戶資料
3. THE API SHALL 提供 `updateProfile(username, avatarUrl)` 函式，呼叫 `PUT /api/v1/users/me` 並回傳更新後的用戶資料
4. WHEN 用戶在 Profile 頁面點擊「儲存」，THE Web_Client SHALL 呼叫 `updateProfile` 並在成功後顯示「已儲存」確認訊息
5. THE Web_Client SHALL 在 Profile 頁面提供「登出」按鈕，點擊後清除 `localStorage`（`token`、`user_id`、`device_private_key`）、清除 IndexedDB Session Key，並導航至 `/qr-login`
6. IF `updateProfile` 呼叫失敗，THEN THE Web_Client SHALL 顯示錯誤訊息並保留用戶輸入

### Requirement 10：Linked Devices 管理（Phase 6）

**User Story:** As a Web 用戶，I want 查看並移除已連結的裝置，so that 我能控制哪些裝置可以存取我的帳號。

#### Acceptance Criteria

1. THE API SHALL 提供 `getLinkedDevices()` 函式，呼叫 `GET /api/v1/devices` 並回傳已連結裝置列表
2. THE API SHALL 提供 `removeDevice(deviceId)` 函式，呼叫 `DELETE /api/v1/devices/{deviceId}` 並回傳操作結果
3. THE Web_Client SHALL 在 Profile 頁面顯示已連結裝置列表，每個裝置顯示裝置名稱、類型與最後活躍時間
4. WHEN 用戶點擊裝置旁的「移除」按鈕，THE Web_Client SHALL 呼叫 `removeDevice` 並在成功後從列表移除該裝置
5. IF `removeDevice` 呼叫失敗，THEN THE Web_Client SHALL 顯示錯誤訊息並保留裝置於列表中
