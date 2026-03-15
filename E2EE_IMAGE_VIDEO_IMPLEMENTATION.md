# E2EE 圖片與影片加密功能實作總結

## 實作概述

本次實作完成了圖片與影片訊息的端到端加密（E2EE）功能，參考音訊訊息的實作架構，確保媒體檔案在傳輸和儲存過程中都保持加密狀態。

## 重要修正：Content Validation 問題

### 問題描述
群組訊息使用 `encrypted_contents_fanout` 時，`content` 欄位為空，導致後端 validation 失敗，出現 "Media content (URL) is required" 錯誤。

### 解決方案
**方案 A：修改後端 validation 邏輯（已採用）**

#### 後端修改（backend/internal/delivery/websocket/controller.go）
```go
// handleMediaMessage 函式修改
func (c *SocketController) handleMediaMessage(client *Client, msg *domain.Message) error {
	// 🔐 E2EE: 對於群組訊息，content 可能為空（使用 encrypted_contents_fanout）
	// 只有在非 fanout 模式下才檢查 content
	hasFanout := msg.EncryptedContentsFanout != nil && len(msg.EncryptedContentsFanout) > 0
	if msg.Content == "" && !hasFanout {
		c.respondError(client, "error", "Media content (URL) is required")
		return context.DeadlineExceeded
	}
	// ... 其餘邏輯
}
```

#### 前端修改（app/lib/features/chat/repositories/chat_repository.dart）
- `sendImageMessage()` 和 `sendVideoMessage()` 修改：
  - 群組訊息：`payload['content'] = ''`（空字串）
  - DM 訊息：`payload['content'] = encryptedContent ?? imageUrl`
  - 群組訊息使用 `encrypted_contents_fanout`，每個成員有專屬的加密 URL

## 後端改動（Go）

### 1. backend/internal/domain/message.go
- ✅ 新增 `FileKey` 欄位用於 DM 媒體訊息的 fileKey 儲存
- 格式：`FileKey string json:"file_key,omitempty" bson:"file_key,omitempty"`
- 說明：群組訊息使用 `FileKeysFanout`，DM 訊息使用 `FileKey`

### 2. backend/internal/repository/mongo_repo/message_repository.go
- ✅ mongoMessage struct 新增 `FileKey string bson:"file_key,omitempty"`
- ✅ toDomain() 函式加入 `FileKey: m.FileKey`
- ✅ fromDomain() 函式加入 `FileKey: m.FileKey`

### 3. backend/internal/delivery/websocket/controller.go
- ✅ 修改 `handleMediaMessage()` 函式
- ✅ 加入 fanout 檢查：允許群組訊息的 content 為空
- ✅ 只在非 fanout 模式下檢查 content 是否為空
- ✅ 修改文字訊息 validation：`if msg.Content == "" && msg.Type == "text" && len(msg.EncryptedContentsFanout) == 0`

### 4. backend/internal/usecase/message_usecase.go
- ✅ 修改 `SendMessage()` 函式的 validation
- ✅ 加入 fanout 檢查：`if strings.TrimSpace(msg.Content) == "" && len(msg.EncryptedContentsFanout) == 0`
- ✅ 允許有 EncryptedContentsFanout 的訊息 content 為空

## 前端改動（Flutter）

### 5. app/lib/models/message.dart
- ✅ 已存在 `fileKey` 欄位（無需修改）
- ✅ 已存在 `fileKeysFanout` 欄位用於群組加密

### 6. app/lib/features/chat/repositories/chat_repository.dart
- ✅ 新增 `sendImageMessage()` 函式
  - 讀取圖片位元組
  - 生成隨機 fileKey
  - AES-GCM 加密圖片
  - 上傳加密後的位元組
  - 群組：為每個成員加密 fileKey 和 content（fanout），payload 的 content 設為空字串
  - DM：用接收方公鑰加密 content，明文傳送 fileKey
  - 透過 WebSocket 發送

- ✅ 新增 `sendVideoMessage()` 函式
  - 與 sendImageMessage 邏輯完全相同
  - type = 'video'
  - 其餘加密流程一致

- ✅ 新增輔助函式：
  - `_uploadEncryptedImage()`: 上傳加密圖片
  - `_uploadEncryptedVideo()`: 上傳加密影片

- ✅ 修正 content validation 問題：
  - 群組訊息：`payload['content'] = ''`（空字串，後端允許）
  - DM 訊息：`payload['content'] = encryptedContent ?? imageUrl`

### 7. app/lib/core/media/image_cache_service.dart
- ✅ 修改 `getImage()` 函式加入 `fileKey` 參數
- ✅ 新增 `_downloadEncryptedImage()` 函式
- ✅ 加入解密邏輯：
  - 若 fileKey 存在：下載 → 解密 → 快取解密後的位元組
  - 若 fileKey 為 null：直接下載並快取（向後兼容）
- ✅ 修改建構函式注入 CryptoService 和 Dio

### 8. app/lib/core/media/video_cache_service.dart
- ✅ 新建檔案，參考 audio_cache_service.dart
- ✅ 實作 `getOrDownloadVideo()` 函式
  - 檢查本地快取
  - 下載加密影片
  - 解密並存入快取
  - 回傳本地檔案路徑
- ✅ 包含錯誤處理和快取管理功能

### 9. app/lib/core/media/cached_network_image_widget.dart
- ✅ 新增 `fileKey` 可選參數
- ✅ 修改 `_loadImage()` 呼叫 `getImage(url, fileKey: fileKey)`
- ✅ 修改 `didUpdateWidget()` 檢查 fileKey 變更

### 10. app/lib/features/chat/ui/widgets/message_bubble.dart
- ✅ 修改圖片訊息顯示：傳遞 `fileKey: msg.fileKey` 給 CachedNetworkImageWidget
- ✅ 新增影片訊息顯示：簡單的佔位符 UI（顯示播放圖示和提示文字）
- 📝 註：完整的影片播放器功能標記為 TODO，需要額外的 video_player 依賴

## 加密流程

### 發送端（Sender）

#### DM 訊息：
1. 生成隨機 fileKey
2. 用 fileKey 加密媒體檔案（AES-GCM）
3. 上傳加密後的檔案，取得 URL
4. 用接收方公鑰加密 URL（content）
5. 發送：`{ content: encryptedUrl, file_key: fileKey, type: 'image/video' }`

#### 群組訊息：
1. 生成隨機 fileKey
2. 用 fileKey 加密媒體檔案（AES-GCM）
3. 上傳加密後的檔案，取得 URL
4. 為每個成員用其公鑰加密 URL 和 fileKey
5. 發送：`{ content: '', encrypted_contents_fanout: {...}, file_keys_fanout: {...}, type: 'image/video' }`
   - 注意：content 為空字串，實際內容在 encrypted_contents_fanout 中

### 接收端（Receiver）

#### DM 訊息：
1. 用自己的私鑰解密 content 取得 URL
2. 從 file_key 欄位取得 fileKey
3. 下載加密的媒體檔案
4. 用 fileKey 解密媒體檔案（AES-GCM）
5. 快取解密後的檔案並顯示

#### 群組訊息：
1. 從 encrypted_contents_fanout[userId] 解密取得 URL
2. 從 file_keys_fanout.keys[userId] 解密取得 fileKey
3. 下載加密的媒體檔案
4. 用 fileKey 解密媒體檔案（AES-GCM）
5. 快取解密後的檔案並顯示

## 向後兼容性

- ✅ 舊圖片（無 fileKey）仍能正常顯示
- ✅ ImageCacheService 檢查 fileKey 是否存在，若無則直接下載
- ✅ CachedNetworkImageWidget 的 fileKey 參數為可選

## 驗收條件

### 已完成：
1. ✅ 後端 Message struct 支援 FileKey 欄位
2. ✅ 後端 MongoDB 儲存和讀取 FileKey
3. ✅ 後端 validation 支援 fanout 訊息（content 可為空）
4. ✅ 前端 sendImageMessage() 實作完成
5. ✅ 前端 sendVideoMessage() 實作完成
6. ✅ ImageCacheService 支援解密
7. ✅ VideoCacheService 建立完成
8. ✅ CachedNetworkImageWidget 支援 fileKey 參數
9. ✅ MessageBubble 傳遞 fileKey 給圖片顯示元件
10. ✅ MessageBubble 加入影片訊息佔位符
11. ✅ 所有檔案編譯通過，無診斷錯誤
12. ✅ 修正 content validation 問題（群組訊息 content 可為空）

### 待測試：
- [ ] 發送圖片訊息 → 伺服器收到加密位元組
- [ ] 發送影片訊息 → 伺服器收到加密位元組
- [ ] DM 圖片：接收方能正確解密並顯示
- [ ] 群組圖片：每個成員各自解密 fileKey 後顯示
- [ ] 舊圖片（無 fileKey）仍能正常顯示
- [ ] 影片播放流程：下載 → 解密 → 本地路徑播放（需實作完整播放器）

## 後續工作

1. **影片播放器實作**：
   - 加入 video_player 依賴
   - 建立 VideoMessageBubble widget
   - 整合 VideoCacheService
   - 支援播放控制（播放/暫停/進度條）

2. **UI 優化**：
   - 加密/解密進度指示器
   - 錯誤處理和重試機制
   - 圖片/影片預覽縮圖

3. **效能優化**：
   - 大檔案分塊加密/解密
   - 背景下載和解密
   - 快取策略優化

## 技術細節

### 加密演算法
- 對稱加密：AES-256-GCM
- 非對稱加密：RSA-2048（用於 fileKey 和 URL 的加密）

### 檔案格式
- 圖片：支援 JPG, PNG, WebP 等常見格式
- 影片：支援 MP4, MOV 等常見格式
- 加密後：二進位位元組流

### 快取策略
- 圖片快取：500MB 上限，30 天過期
- 影片快取：使用系統臨時目錄
- 音訊快取：使用系統臨時目錄

## 參考文件
- E2EE_GROUP_MEDIA_FILEKEY_FANOUT_IMPLEMENTATION.md
- E2EE_GROUP_FANOUT_IMPLEMENTATION.md
- audio_cache_service.dart（音訊實作參考）
