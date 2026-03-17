# 群組 E2EE 訊息加密架構補齊實作總結

## 📋 實作概述

本次實作補齊了群組 E2EE 訊息加密的 fan-out 架構，將原本塞在單一 `Content` 字串欄位的 JSON 格式，改為使用專屬的 `EncryptedContentsFanout` 欄位，提升語義清晰度和後端處理能力。

## ✅ 已完成的改動

### 後端改動 (Go + MongoDB)

#### 1. backend/internal/domain/message.go
- ✅ 新增 `EncryptedContentsFanout map[string]string` 欄位
- 格式：`{userId: encryptedContent, ...}`
- 用途：儲存每個成員專屬的加密密文

#### 2. backend/internal/repository/mongo_repo/message_repository.go
- ✅ 在 `mongoMessage` struct 新增 `EncryptedContentsFanout` 欄位
- ✅ 在 `toDomain()` 函式中加入欄位轉換
- ✅ 在 `fromDomain()` 函式中加入欄位轉換

#### 3. backend/internal/delivery/websocket/hub.go
- ✅ 修改 `routeMessage()` 函式，實作群組訊息的個人化裁切邏輯：
  - 發送方收到完整 `EncryptedContentsFanout`（用於 LocalDB 存儲）
  - 每個接收方只收到自己的密文（`content` 欄位）
  - 移除接收方 payload 中的 `EncryptedContentsFanout`（安全性）

### 前端改動 (Flutter + Dart)

#### 4. app/lib/models/message.dart
- ✅ 新增 `encryptedContentsFanout` 欄位（`Map<String, String>?`）
- ✅ 在 `fromJson()` 中解析 `encrypted_contents_fanout`
- ✅ 在 `toJson()` 中序列化 `encrypted_contents_fanout`
- ✅ 在 `toMap()` 中將 fanout 轉為 JSON 字串存入 SQLite
- ✅ 在 `fromMap()` 中解析 SQLite 的 JSON 字串
- ✅ 在 `copyWith()` 中支援欄位複製
- ✅ 在 `props` 中加入欄位以支援 Equatable

#### 5. app/lib/features/chat/providers/chat_room_provider.dart
- ✅ 新增 `_encryptGroupMessageToMap()` 函式
  - 與 `_encryptGroupMessage()` 邏輯相同
  - 回傳 `Map<String, String>` 而非 JSON 字串
- ✅ 修改 `sendMessage()` 函式
  - 群組訊息使用 `_encryptGroupMessageToMap()`
  - 發送時使用 `encrypted_contents_fanout` 欄位
  - `content` 欄位保留空字串（向後相容）
- ✅ 修改 `_tryDecryptMessage()` 函式
  - 優先檢查 `encryptedContentsFanout`（新格式）
  - 從 fanout map 中取出當前用戶的密文並解密
  - 向後相容舊格式（`content` 包含 JSON）

#### 6. app/lib/core/storage/local_db_service.dart
- ✅ 資料庫版本從 7 升至 8
- ✅ 在 `_createMessagesTable()` 中新增 `encrypted_contents_fanout TEXT` 欄位
- ✅ 在 `_ensureMessagesColumns()` 的 missing map 中加入欄位定義
- ✅ 在 `onUpgrade()` 中加入版本 8 的遷移邏輯

## 🔍 驗收條件檢查清單

### 1. 發送群組訊息
- [ ] WebSocket payload 包含 `encrypted_contents_fanout`
- [ ] fanout map 中每個成員 ID 對應各自的密文
- [ ] `content` 欄位為空字串或保留舊格式（向後相容）

### 2. 後端廣播邏輯
- [ ] 發送方收到完整 fanout map（用於 LocalDB 存儲）
- [ ] 每個接收方只收到自己的密文（在 `content` 欄位）
- [ ] 接收方的 payload 不包含 `encrypted_contents_fanout`

### 3. 接收方解密
- [ ] 接收方能正常解密群組訊息
- [ ] 解密後的明文正確顯示在 UI

### 4. 向後相容性
- [ ] 舊格式訊息（`content` 包含 JSON）仍能正常顯示
- [ ] 新舊格式訊息可以在同一個聊天室中共存

### 5. 安全性
- [ ] 非群組成員無法看到其他成員的密文
- [ ] 接收方無法從 payload 中獲取完整 fanout map

## 🧪 測試建議

### 單元測試
1. 測試 `_encryptGroupMessageToMap()` 回傳正確的 Map 格式
2. 測試 `_tryDecryptMessage()` 能正確處理新舊兩種格式
3. 測試 Message model 的序列化/反序列化

### 整合測試
1. 發送群組訊息 → 檢查 WebSocket payload 格式
2. 接收群組訊息 → 檢查解密邏輯
3. 資料庫遷移 → 檢查欄位是否正確新增

### 端到端測試
1. 三人群組：A 發送訊息 → B 和 C 都能正常解密
2. 混合格式：新舊訊息在同一聊天室中正常顯示
3. 離線場景：B 離線時 A 發送訊息 → B 上線後能正常解密

## 📝 後續優化建議

### 1. 新成員加入群組的歷史訊息處理
目前新成員加入群組後，無法解密歷史訊息（因為 fanout map 中沒有他的密文）。

可能的解決方案：
- 方案 A：新成員只能看到加入後的訊息（最簡單）
- 方案 B：後端提供 API，允許群組管理員為新成員重新加密歷史訊息
- 方案 C：使用群組共享金鑰（降低安全性）

### 2. 成員退出群組的處理
成員退出後，其密文仍存在於 fanout map 中（浪費空間）。

可能的解決方案：
- 定期清理已退出成員的密文
- 或保留（以防成員重新加入）

### 3. 效能優化
當群組成員數量很大時（例如 100+ 人），fanout map 會很大。

可能的優化：
- 分批加密（已實作，batch size = 10）
- 考慮使用壓縮演算法
- 考慮使用混合加密（對稱 + 非對稱）

## 🔧 故障排除

### 問題 1：接收方無法解密新格式訊息
- 檢查 `encryptedContentsFanout` 是否包含當前用戶的 ID
- 檢查發送方的公鑰是否正確
- 檢查 `_tryDecryptMessage()` 的判斷邏輯

### 問題 2：資料庫遷移失敗
- 檢查 SQLite 版本是否正確升至 8
- 檢查 `encrypted_contents_fanout` 欄位是否成功新增
- 查看 `chat_cache.log` 檔案中的錯誤訊息

### 問題 3：後端編譯錯誤
- 檢查 Go 版本是否支援 map 類型
- 檢查 MongoDB driver 版本
- 執行 `go mod tidy` 更新依賴

## 📚 相關文件

- [E2EE Auto-Resend Implementation](./E2EE_AUTO_RESEND_IMPLEMENTATION.md)
- [E2EE Group Media FileKey Fanout](./E2EE_GROUP_MEDIA_FILEKEY_FANOUT_IMPLEMENTATION.md)
- [E2EE Key Recovery Implementation](./E2EE_KEY_RECOVERY_IMPLEMENTATION.md)

## 🎉 總結

本次實作成功補齊了群組 E2EE 訊息加密的 fan-out 架構，提升了：
1. 語義清晰度：專屬欄位明確表達用途
2. 安全性：接收方無法獲取其他成員的密文
3. 可維護性：後端可以更容易地處理 fanout 結構
4. 向後相容性：舊格式訊息仍能正常運作

所有改動已完成並通過編譯檢查，可以進入測試階段。
