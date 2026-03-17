# Design Document: Web E2EE Full Feature

## Overview

本設計文件描述 Web 前端（`/web/src`）補全 Phase 1–6 所有缺失功能的技術方案，使其成為與 Flutter App 對等的完整 E2EE 即時通訊用戶端。

現有程式碼已具備：
- X25519 金鑰對產生（`generateX25519KeyPair`）
- Session Key 解密（`decryptSessionKey`）與訊息解密（`decryptMessage`）
- IndexedDB Session Key 儲存（`sessionKeyStore.js`）
- WebSocket 連線管理（`useWebSocket.js`）含 `session_key_delivery`、`device_unlinked` 事件
- 基本 REST API（login、register、getMyRooms、searchUsers、getHistory、markAsRead）
- Chat 頁面（明文發送，無解密顯示）

本 Spec 補全的功能：
- **Phase 1**：`encryptMessage` + Chat 加密整合
- **Phase 2**：Re-encrypt 機制（`re_encrypt_request` / `re_encrypt_response`）
- **Phase 3**：好友系統 API + 側邊欄 UI
- **Phase 4**：群組建立 + Fanout 加密（`encryptForRecipient`）
- **Phase 5**：在線狀態（`presence_update`）
- **Phase 6**：Profile 頁面、登出、Linked Devices

---

## Architecture

系統採用單頁應用（SPA）架構，以 React + Vite 為基礎，各層職責如下：

```
┌─────────────────────────────────────────────────────────┐
│                     React Pages / Components             │
│  Chat.jsx  │  Profile.jsx  │  Login.jsx  │  QrLogin.jsx │
└────────────────────────┬────────────────────────────────┘
                         │ hooks / API calls
┌────────────────────────▼────────────────────────────────┐
│                    Custom Hooks Layer                    │
│              useWebSocket.js (擴充)                      │
└──────────┬─────────────────────────────┬────────────────┘
           │ WebSocket events             │ REST calls
┌──────────▼──────────┐       ┌──────────▼──────────────┐
│   CryptoService      │       │      API Layer           │
│  webCryptoService.js │       │    api/index.js (擴充)   │
│  + encryptMessage    │       │  + friends / devices /   │
│  + encryptForRecip.  │       │    profile / rooms API   │
└──────────┬──────────┘       └─────────────────────────┘
           │
┌──────────▼──────────┐
│   SessionKeyStore    │
│  sessionKeyStore.js  │
│  (IndexedDB)         │
└─────────────────────┘
```

### 資料流：加密發送

```
用戶輸入明文
    │
    ▼
getSessionKey() ──► IndexedDB
    │
    ▼
encryptMessage(plaintext, sessionKey)
    │  AES-256-GCM, random nonce
    ▼
base64(nonce[12] + mac[16] + ciphertext)
    │
    ▼
WebSocket send { event: "chat_message", data: { content: encrypted } }
```

### 資料流：群組 Fanout 加密

```
用戶輸入明文
    │
    ▼
getRoomMembers(roomId) ──► REST API
    │  [{ user_id, public_key }]
    ▼
for each member:
  encryptForRecipient(plaintext, memberPublicKey, myPrivateKey)
    │  X25519 ECDH → shared secret → AES-256-GCM
    ▼
ciphertexts: { userId: Encrypted_Content, ... }
    │
    ▼
WebSocket send { event: "chat_message", data: { ciphertexts: {...} } }
```

---

## Components and Interfaces

### 1. CryptoService（`web/src/crypto/webCryptoService.js`）

新增兩個函式：

#### `encryptMessage(plaintext, sessionKeyBase64): Promise<string>`

```
Input:  plaintext (UTF-8 string), sessionKeyBase64 (base64 AES-256 key)
Output: Promise<string> — base64(nonce[12] + mac[16] + ciphertext)
Throws: Error if sessionKeyBase64 is invalid base64 or wrong length
```

實作步驟：
1. `base64ToUint8Array(sessionKeyBase64)` → 驗證長度為 32 bytes
2. `crypto.getRandomValues(new Uint8Array(12))` → nonce
3. `crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['encrypt'])`
4. `crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce, tagLength: 128 }, key, encoded)`
5. Web Crypto 回傳 `ciphertext + tag`（tag 在尾端），拆分後重組為 `nonce + tag + ciphertext`
6. `uint8ArrayToBase64(combined)` 回傳

> 注意：Web Crypto API 的 AES-GCM 輸出格式為 `ciphertext || tag`，需手動拆分 tag（最後 16 bytes）並重組為 `nonce + tag + ciphertext` 以符合後端格式。

#### `encryptForRecipient(plaintext, recipientPublicKeyBase64, senderPrivateKey): Promise<string>`

```
Input:  plaintext (UTF-8 string),
        recipientPublicKeyBase64 (base64 X25519 public key),
        senderPrivateKey (Uint8Array, 32 bytes)
Output: Promise<string> — base64(nonce[12] + mac[16] + ciphertext)
```

實作步驟：
1. `x25519.getSharedSecret(senderPrivateKey, recipientPublicKeyBytes)` → 32-byte shared secret
2. `crypto.subtle.importKey('raw', sharedSecret, 'AES-GCM', false, ['encrypt'])`
3. 產生隨機 nonce，執行 AES-256-GCM 加密
4. 重組格式同 `encryptMessage`

---

### 2. useWebSocket Hook（`web/src/hooks/useWebSocket.js`）

擴充 `UseWebSocketOptions` 介面，新增三個 callback：

```typescript
interface UseWebSocketOptions {
  onSessionKeyDelivery?: (data: object) => void;   // 已有
  onDeviceUnlinked?: (data: object) => void;        // 已有
  onReEncryptRequest?: (data: ReEncryptRequestData) => void;  // 新增
  onReEncryptResponse?: (data: ReEncryptResponseData) => void; // 新增
  onPresenceUpdate?: (data: PresenceUpdateData) => void;       // 新增
}

interface ReEncryptRequestData {
  message_id: string;
  encrypted_content: string;
  new_session_key?: string;
}

interface ReEncryptResponseData {
  message_id: string;
  new_encrypted_content: string;
}

interface PresenceUpdateData {
  user_id: string;
  status: 'online' | 'offline';
}
```

新增 `sendRawEvent(event, data)` 方法，供 re-encrypt response 使用：

```javascript
const sendRawEvent = useCallback((event, data) => {
  const payload = { event, data };
  if (ws.current?.readyState === WebSocket.OPEN) {
    ws.current.send(JSON.stringify(payload));
  }
}, []);
```

onmessage 處理器新增三個事件分支：

```javascript
if (message.event === 're_encrypt_request') {
  const { message_id, encrypted_content } = message.data || {};
  if (!message_id || !encrypted_content) {
    console.error('re_encrypt_request: missing fields'); return;
  }
  optionsRef.current.onReEncryptRequest?.(message.data);
}

if (message.event === 're_encrypt_response') {
  optionsRef.current.onReEncryptResponse?.(message.data);
}

if (message.event === 'presence_update') {
  optionsRef.current.onPresenceUpdate?.(message.data);
}
```

回傳值新增 `sendRawEvent`：

```javascript
return { messages, sendMessage, sendRawEvent, isConnected };
```

---

### 3. API Layer（`web/src/api/index.js`）

新增以下函式：

#### Friends API
```javascript
getFriends()                          // GET  /api/v1/friends
sendFriendRequest(userId)             // POST /api/v1/friends/request
acceptFriendRequest(requestId)        // POST /api/v1/friends/accept
rejectFriendRequest(requestId)        // POST /api/v1/friends/reject
blockUser(userId)                     // POST /api/v1/friends/block
unblockUser(userId)                   // POST /api/v1/friends/unblock
getFriendRequests()                   // GET  /api/v1/friends/requests (待處理請求)
```

#### Rooms API
```javascript
createRoom(name, memberIds)           // POST /api/v1/rooms
getRoomMembers(roomId)                // GET  /api/v1/rooms/{roomId}/members
```

#### Devices API
```javascript
getLinkedDevices()                    // GET  /api/v1/devices
removeDevice(deviceId)                // DELETE /api/v1/devices/{deviceId}
```

#### Profile API
```javascript
getProfile()                          // GET /api/v1/users/me
updateProfile(username, avatarUrl)    // PUT /api/v1/users/me
```

所有 API 函式在收到非 2xx 回應時，拋出包含 HTTP 狀態碼與伺服器錯誤訊息的 Error 物件。axios interceptor 已處理此邏輯，各函式直接 `throw` 即可。

---

### 4. Chat.jsx（重構）

Chat 頁面需要以下狀態擴充：

```javascript
const [sessionKey, setSessionKey] = useState(null);       // 從 IndexedDB 載入
const [sessionKeyLoading, setSessionKeyLoading] = useState(true);
const [onlineUsers, setOnlineUsers] = useState(new Map()); // userId -> status
const [activeTab, setActiveTab] = useState('rooms');       // 'rooms' | 'friends' | 'requests'
const [friends, setFriends] = useState([]);
const [friendRequests, setFriendRequests] = useState([]);
const [showCreateGroup, setShowCreateGroup] = useState(false);
```

#### Session Key 載入流程

```javascript
useEffect(() => {
  getSessionKey().then(key => {
    setSessionKey(key);
    setSessionKeyLoading(false);
  });
}, []);
```

#### 加密發送

```javascript
const handleSendMessage = async (e) => {
  e.preventDefault();
  if (!newMessage.trim() || !selectedChat || !sessionKey) return;
  const encrypted = await encryptMessage(newMessage, sessionKey);
  // 群組：fanout 加密（見 Requirement 7）
  sendMessage(receiverId, roomId, encrypted);
  setNewMessage('');
};
```

#### 解密顯示

```javascript
const decryptedContent = async (msg) => {
  try {
    return await decryptMessage(msg.content, sessionKey);
  } catch {
    return '🔒 無法解密';
  }
};
```

實作上使用 `useEffect` 批次解密歷史訊息，並在 state 中儲存解密後的明文。

#### Re-encrypt 處理

```javascript
onReEncryptRequest: async ({ message_id, encrypted_content, new_session_key }) => {
  try {
    const plaintext = await decryptMessage(encrypted_content, sessionKey);
    const reEncrypted = await encryptMessage(plaintext, new_session_key || sessionKey);
    sendRawEvent('re_encrypt_response', { message_id, new_encrypted_content: reEncrypted });
  } catch {
    setMessages(prev => prev.map(m =>
      m.id === message_id ? { ...m, decryptError: true } : m
    ));
  }
}
```

---

### 5. Profile.jsx（新頁面）

路由：`/profile`

```
┌─────────────────────────────────┐
│  Profile                    [←] │
├─────────────────────────────────┤
│  Avatar  Username               │
│  [Edit Username]  [Save]        │
├─────────────────────────────────┤
│  Linked Devices                 │
│  ┌─────────────────────────┐    │
│  │ iPhone 15  mobile  2d   │[X] │
│  │ Chrome Web  web    now  │[X] │
│  └─────────────────────────┘    │
├─────────────────────────────────┤
│  [Logout]                       │
└─────────────────────────────────┘
```

登出流程：
1. `clearSessionKey()` — 清除 IndexedDB
2. `localStorage.removeItem('token', 'user_id', 'device_private_key')`
3. `navigate('/qr-login')`

---

### 6. 側邊欄 Tab 結構

```
┌──────────────────────┐
│  ChatWmex  [Profile] │
├──────────────────────┤
│ [Rooms][Friends][Req]│  ← 三個 Tab
├──────────────────────┤
│  Rooms Tab:          │
│  [+ 建立群組]        │
│  # room1             │
│  # room2             │
├──────────────────────┤
│  Friends Tab:        │
│  ● user1  [封鎖]     │
│  ○ user2  [封鎖]     │
├──────────────────────┤
│  Requests Tab:       │
│  user3 [接受][拒絕]  │
└──────────────────────┘
```

---

### 7. App.jsx 路由更新

新增 `/profile` 路由：

```jsx
<Route path="/profile" element={<AuthGuard><Profile /></AuthGuard>} />
```

---

## Data Models

### Message（WebSocket `chat_message` payload）

```typescript
// 一對一訊息
interface DirectMessage {
  event: 'chat_message';
  data: {
    receiver_id: string;
    room_id: null;
    content: string;          // Encrypted_Content (base64)
    type: 'text';
    client_msg_id: string;
  }
}

// 群組訊息（Fanout）
interface GroupMessage {
  event: 'chat_message';
  data: {
    receiver_id: null;
    room_id: string;
    ciphertexts: Record<string, string>;  // { userId: Encrypted_Content }
    type: 'text';
    client_msg_id: string;
  }
}
```

### Encrypted_Content 格式

```
base64( nonce[12 bytes] + mac/tag[16 bytes] + ciphertext[variable] )
```

### Friend

```typescript
interface Friend {
  id: string;
  username: string;
  avatar_url?: string;
  status?: 'online' | 'offline';
}
```

### FriendRequest

```typescript
interface FriendRequest {
  id: string;
  from_user: { id: string; username: string };
  created_at: string;
}
```

### Room

```typescript
interface Room {
  id: string;
  name: string;
  is_group: boolean;
  members?: RoomMember[];
}

interface RoomMember {
  user_id: string;
  username: string;
  public_key: string;  // base64 X25519 public key
}
```

### Device

```typescript
interface Device {
  id: string;
  name: string;
  type: 'mobile' | 'web';
  last_active_at: string;
}
```

### PresenceUpdate（WebSocket payload）

```typescript
interface PresenceUpdate {
  event: 'presence_update';
  data: {
    user_id: string;
    status: 'online' | 'offline';
  }
}
```

### ReEncryptRequest（WebSocket payload）

```typescript
interface ReEncryptRequest {
  event: 're_encrypt_request';
  data: {
    message_id: string;
    encrypted_content: string;  // Encrypted_Content with old key
    new_session_key?: string;   // base64 new AES-256 key
  }
}
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: encryptMessage / decryptMessage Round-Trip

*For any* valid UTF-8 plaintext string and valid 32-byte AES-256 session key (base64 encoded), calling `decryptMessage(await encryptMessage(plaintext, key), key)` should return a string equal to the original plaintext.

**Validates: Requirements 1.3**

---

### Property 2: Invalid Session Key Throws Error

*For any* string that is not valid base64 or decodes to a byte array that is not 32 bytes, calling `encryptMessage(plaintext, invalidKey)` should throw an Error.

**Validates: Requirements 1.5**

---

### Property 3: Fanout Map Covers All Members

*For any* group room with N members (each having a valid X25519 public key), when a message is sent, the resulting `ciphertexts` map should contain exactly N entries — one per member `user_id`.

**Validates: Requirements 7.2**

---

### Property 4: encryptForRecipient Round-Trip

*For any* plaintext, recipient X25519 key pair, and sender X25519 key pair, calling `encryptForRecipient(plaintext, recipientPublicKey, senderPrivateKey)` and then decrypting the result using the recipient's private key and sender's public key (via `decryptSessionKey`-equivalent ECDH path) should return the original plaintext.

**Validates: Requirements 7.5**

---

### Property 5: Re-Encrypt Preserves Plaintext

*For any* valid encrypted message and session key pair, when a `re_encrypt_request` is processed, the resulting `re_encrypt_response` should contain a new encrypted content that decrypts (with the new session key) to the same plaintext as the original encrypted content decrypted with the old session key.

**Validates: Requirements 3.1**

---

### Property 6: Presence Update State Consistency

*For any* sequence of `presence_update` WebSocket events with arbitrary `user_id` and `status` values, after processing all events the `onlineUsers` Map should reflect the last known status for each `user_id` seen in the sequence.

**Validates: Requirements 8.1, 8.2**

---

### Property 7: API Non-2xx Throws Error

*For any* friend/device/profile API function and any HTTP response with status code in the range 400–599, the function should throw an Error object containing the HTTP status code.

**Validates: Requirements 4.7**

---

### Property 8: History Messages All Decrypted

*For any* list of history messages (each with a valid `content` field encrypted with the current session key), after loading history all messages should have their `content` replaced with the decrypted plaintext (or the fallback string `'🔒 無法解密'` if decryption fails).

**Validates: Requirements 2.3**

---

## Error Handling

| 情境 | 處理方式 |
|------|---------|
| `encryptMessage` 收到無效 Session Key | 拋出 `Error('Invalid session key: ...')` |
| `decryptMessage` 解密失敗 | 拋出 `Error('Decryption failed: ...')`，UI 顯示 `🔒 無法解密` |
| `re_encrypt_request` 缺少欄位 | `console.error` 並忽略事件 |
| `re_encrypt_request` 解密失敗 | 訊息標記 `decryptError: true`，UI 顯示 `🔒 解密失敗` |
| `ciphertexts[myUserId]` 不存在 | UI 顯示 `🔒 無法解密（未包含本裝置）` |
| 好友 API 失敗 | toast 通知或行內錯誤訊息 |
| `createRoom` 失敗 | 顯示錯誤訊息，保持對話框開啟 |
| `updateProfile` 失敗 | 顯示錯誤訊息，保留用戶輸入 |
| `removeDevice` 失敗 | 顯示錯誤訊息，保留裝置於列表 |
| Session Key 未載入 | 停用輸入框，顯示「等待金鑰...」 |
| WebSocket 斷線 | 所有用戶顯示離線（灰色圓點） |

---

## Testing Strategy

### 雙軌測試方法

本功能採用單元測試與屬性測試並行的策略：

- **單元測試**：驗證具體範例、邊界條件與錯誤情境
- **屬性測試**：驗證適用於所有輸入的通用屬性

兩者互補，共同提供完整的正確性保證。

### 屬性測試工具

- **框架**：[fast-check](https://github.com/dubzzz/fast-check)（JavaScript/TypeScript 屬性測試庫）
- **測試執行器**：Vitest（與 Vite 整合）
- **最低迭代次數**：每個屬性測試至少執行 **100 次**

安裝：
```bash
npm install --save-dev fast-check vitest
```

### 屬性測試規格

每個屬性測試必須以 tag 標記對應的設計屬性：

```javascript
// Feature: web-e2ee-full-feature, Property 1: encryptMessage/decryptMessage round-trip
test('encrypt then decrypt returns original plaintext', async () => {
  await fc.assert(
    fc.asyncProperty(fc.string(), fc.uint8Array({ minLength: 32, maxLength: 32 }), async (plaintext, keyBytes) => {
      const keyBase64 = uint8ArrayToBase64(keyBytes);
      const encrypted = await encryptMessage(plaintext, keyBase64);
      const decrypted = await decryptMessage(encrypted, keyBase64);
      expect(decrypted).toBe(plaintext);
    }),
    { numRuns: 100 }
  );
});
```

### 屬性測試對應表

| 屬性 | 測試描述 | fast-check 生成器 |
|------|---------|-----------------|
| Property 1 | encrypt/decrypt round-trip | `fc.string()` × `fc.uint8Array({minLength:32,maxLength:32})` |
| Property 2 | 無效金鑰拋出錯誤 | `fc.string()` 過濾非合法 32-byte base64 |
| Property 3 | Fanout Map 覆蓋所有成員 | `fc.array(fc.record({user_id: fc.uuid(), public_key: fc.string()}))` |
| Property 4 | encryptForRecipient round-trip | 生成隨機 X25519 金鑰對 × `fc.string()` |
| Property 5 | re-encrypt 保留明文 | `fc.string()` × 兩組 `fc.uint8Array({minLength:32,maxLength:32})` |
| Property 6 | presence_update 狀態一致性 | `fc.array(fc.record({user_id: fc.uuid(), status: fc.constantFrom('online','offline')}))` |
| Property 7 | 非 2xx 拋出錯誤 | `fc.integer({min:400,max:599})` |
| Property 8 | 歷史訊息全部解密 | `fc.array(fc.record({content: fc.string()}))` |

### 單元測試重點

單元測試聚焦於以下具體情境（避免與屬性測試重複）：

- **CryptoService**：空字串加密（edge case 1.4）、輸出格式驗證（nonce 長度、tag 長度）
- **useWebSocket**：`re_encrypt_request` 缺少欄位時忽略（edge case 3.5）、`presence_update` callback 觸發
- **Chat.jsx**：Session Key 未載入時輸入框停用（2.5）、解密失敗顯示 fallback（2.4）、`ciphertexts[myUserId]` 不存在（7.4）
- **API**：各 friends/devices/profile 函式呼叫正確端點（4.1–4.6、6.1、7.1、9.2–9.3、10.1–10.2）
- **Profile.jsx**：登出清除 localStorage 與 IndexedDB（9.5）、updateProfile 失敗保留輸入（9.6）
- **側邊欄**：三個 Tab 存在（5.1）、切換 Tab 觸發正確 API（5.2–5.3）

### 測試檔案結構

```
web/src/
├── crypto/
│   └── webCryptoService.test.js   ← Property 1, 2, 4 + edge cases
├── hooks/
│   └── useWebSocket.test.js       ← Property 5, 6 + edge cases
├── api/
│   └── index.test.js              ← Property 7 + API unit tests
└── pages/
    ├── Chat.test.jsx              ← Property 3, 8 + UI unit tests
    └── Profile.test.jsx           ← Profile unit tests
```
