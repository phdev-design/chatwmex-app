# Tasks: Web E2EE Full Feature

## Task List

- [x] 1. CryptoService 擴充
  - [x] 1.1 實作 `encryptMessage(plaintext, sessionKeyBase64)` — AES-256-GCM 對稱加密，輸出 `base64(nonce[12] + mac[16] + ciphertext)`
  - [x] 1.2 實作 `encryptForRecipient(plaintext, recipientPublicKeyBase64, senderPrivateKey)` — X25519 ECDH 衍生共享金鑰後 AES-256-GCM 加密
  - [x] 1.3 撰寫 `webCryptoService.test.js`：Property 1（round-trip）、Property 2（無效金鑰拋錯）、Property 4（encryptForRecipient round-trip）及邊界條件（空字串、格式驗證）

- [x] 2. useWebSocket Hook 擴充
  - [x] 2.1 新增 `onReEncryptRequest`、`onReEncryptResponse`、`onPresenceUpdate` callback 至 `UseWebSocketOptions`
  - [x] 2.2 在 `onmessage` 處理器中新增 `re_encrypt_request`、`re_encrypt_response`、`presence_update` 事件分支（含缺少欄位的防禦性檢查）
  - [x] 2.3 新增 `sendRawEvent(event, data)` 方法並加入回傳值
  - [x] 2.4 撰寫 `useWebSocket.test.js`：Property 5（re-encrypt 保留明文）、Property 6（presence_update 狀態一致性）及邊界條件

- [x] 3. API Layer 擴充
  - [x] 3.1 新增 Friends API：`getFriends`、`sendFriendRequest`、`acceptFriendRequest`、`rejectFriendRequest`、`blockUser`、`unblockUser`、`getFriendRequests`
  - [x] 3.2 新增 Rooms API：`createRoom(name, memberIds)`、`getRoomMembers(roomId)`
  - [x] 3.3 新增 Devices API：`getLinkedDevices()`、`removeDevice(deviceId)`
  - [x] 3.4 新增 Profile API：`getProfile()`、`updateProfile(username, avatarUrl)`
  - [x] 3.5 撰寫 `api/index.test.js`：Property 7（非 2xx 拋出錯誤）及各函式端點驗證

- [x] 4. Chat.jsx 重構
  - [x] 4.1 新增 Session Key 載入狀態（`sessionKeyLoading`）：mount 時從 IndexedDB 讀取，未載入時停用輸入框並顯示「等待金鑰...」
  - [x] 4.2 整合加密發送：`handleSendMessage` 呼叫 `encryptMessage` 後再透過 WebSocket 發送
  - [x] 4.3 整合解密顯示：WebSocket `chat_message` 與歷史訊息均呼叫 `decryptMessage`，失敗時顯示「🔒 無法解密」
  - [x] 4.4 整合 Re-encrypt：傳入 `onReEncryptRequest` callback，處理解密→重新加密→發送 `re_encrypt_response` 流程
  - [x] 4.5 整合在線狀態：維護 `onlineUsers` Map，傳入 `onPresenceUpdate` callback，在聊天標題顯示狀態圓點
  - [x] 4.6 新增側邊欄三個 Tab（Rooms / Friends / Requests）及對應狀態（`activeTab`、`friends`、`friendRequests`）
  - [x] 4.7 實作 Friends Tab：呼叫 `getFriends()`，顯示好友列表與在線狀態圓點，提供「封鎖」按鈕
  - [x] 4.8 實作 Requests Tab：呼叫 `getFriendRequests()`，顯示待處理請求，提供「接受」與「拒絕」按鈕
  - [x] 4.9 在搜尋結果中新增「加好友」按鈕，呼叫 `sendFriendRequest` 並顯示「已送出」狀態
  - [x] 4.10 實作群組 Fanout 加密發送：群組訊息呼叫 `getRoomMembers` 取得公鑰，對每位成員呼叫 `encryptForRecipient`，組成 `ciphertexts` map 發送
  - [x] 4.11 實作群組訊息解密：從 `ciphertexts[myUserId]` 取出密文解密，不存在時顯示「🔒 無法解密（未包含本裝置）」
  - [x] 4.12 新增「建立群組」按鈕與對話框（輸入名稱 + 勾選好友），呼叫 `createRoom` 並更新側邊欄
  - [x] 4.13 新增導航至 `/profile` 的入口（頭像或按鈕）
  - [x] 4.14 撰寫 `Chat.test.jsx`：Property 3（Fanout Map 覆蓋所有成員）、Property 8（歷史訊息全部解密）及 UI 邊界條件

- [x] 5. Profile.jsx 新頁面
  - [x] 5.1 建立 `Profile.jsx`，顯示當前用戶資料（呼叫 `getProfile()`）
  - [x] 5.2 實作編輯用戶名稱並呼叫 `updateProfile`，成功顯示「已儲存」，失敗顯示錯誤並保留輸入
  - [x] 5.3 實作 Linked Devices 列表（呼叫 `getLinkedDevices()`），每個裝置顯示名稱、類型、最後活躍時間與「移除」按鈕
  - [x] 5.4 實作「移除裝置」：呼叫 `removeDevice`，成功後從列表移除，失敗顯示錯誤
  - [x] 5.5 實作「登出」按鈕：清除 `localStorage`（token、user_id、device_private_key）、呼叫 `clearSessionKey()`，導航至 `/qr-login`
  - [x] 5.6 撰寫 `Profile.test.jsx`：登出流程、updateProfile 失敗保留輸入、removeDevice 失敗保留裝置

- [x] 6. App.jsx 路由更新
  - [x] 6.1 import `Profile` 元件並新增 `/profile` 路由（包裹 `AuthGuard`）
