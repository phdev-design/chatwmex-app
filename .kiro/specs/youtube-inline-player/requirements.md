# 需求文件

## 簡介

本功能為 Flutter chat app 的 chat bubble 新增 YouTube 影片連結預覽與內嵌播放能力。當訊息內容包含 YouTube 連結時，系統自動偵測並在 bubble 內顯示影片縮圖預覽卡片；用戶點擊後可直接在 bubble 內展開播放器播放影片，無需離開 app，體驗類似 WhatsApp 的 inline video player。

## 詞彙表

- **YouTube_Detector**：負責從訊息文字中偵測並解析 YouTube 連結的元件
- **YouTube_Preview_Card**：在 chat bubble 內顯示影片縮圖、標題的預覽卡片 Widget
- **YouTube_Inline_Player**：在 chat bubble 內嵌入的 YouTube 播放器 Widget
- **Video_ID**：YouTube 影片的唯一識別碼（11 個字元），從 URL 中提取
- **Thumbnail_URL**：YouTube 影片縮圖的標準圖片 URL，格式為 `https://img.youtube.com/vi/{videoId}/hqdefault.jpg`
- **MessageBubble**：現有的 chat bubble Widget，位於 `app/lib/features/chat/ui/widgets/message_bubble.dart`
- **LinkPreview**：現有的連結預覽資料模型，位於 `app/lib/models/message.dart`

---

## 需求

### 需求 1：YouTube 連結偵測

**User Story：** 身為聊天用戶，我希望系統能自動識別訊息中的 YouTube 連結，以便觸發影片預覽功能。

#### 驗收標準

1. THE **YouTube_Detector** SHALL 支援以下 YouTube URL 格式的解析：
   - `https://www.youtube.com/watch?v={videoId}`
   - `https://youtu.be/{videoId}`
   - `https://youtube.com/watch?v={videoId}`
   - `https://m.youtube.com/watch?v={videoId}`
   - `https://www.youtube.com/shorts/{videoId}`

2. WHEN 訊息內容包含有效的 YouTube URL，THE **YouTube_Detector** SHALL 從 URL 中提取長度為 11 個字元的 Video_ID。

3. IF 訊息內容不包含任何 YouTube URL，THEN THE **YouTube_Detector** SHALL 返回 null，不觸發任何預覽邏輯。

4. IF YouTube URL 格式無效或 Video_ID 無法提取，THEN THE **YouTube_Detector** SHALL 返回 null。

5. THE **YouTube_Detector** SHALL 僅處理訊息類型為 `MessageType.text` 的訊息，忽略其他類型（image、voice、video、file 等）。

6. WHILE 訊息處於解密失敗（`isDecryptionFailure`）或解密重試（`isDecryptingRetry`）狀態，THE **YouTube_Detector** SHALL 不執行任何偵測邏輯。

---

### 需求 2：影片縮圖預覽卡片

**User Story：** 身為聊天用戶，我希望在訊息 bubble 內看到 YouTube 影片的縮圖預覽，以便在播放前了解影片內容。

#### 驗收標準

1. WHEN **YouTube_Detector** 成功提取 Video_ID，THE **YouTube_Preview_Card** SHALL 在訊息文字下方顯示影片縮圖預覽卡片。

2. THE **YouTube_Preview_Card** SHALL 使用 `https://img.youtube.com/vi/{videoId}/hqdefault.jpg` 作為縮圖來源，無需呼叫任何外部 API。

3. THE **YouTube_Preview_Card** SHALL 在縮圖中央顯示播放按鈕圖示（`Icons.play_circle_filled`），以提示用戶可點擊播放。

4. THE **YouTube_Preview_Card** SHALL 將縮圖寬度限制為 `MediaQuery.of(context).size.width * 0.65`，並以 16:9 比例顯示。

5. IF 縮圖圖片載入失敗，THEN THE **YouTube_Preview_Card** SHALL 顯示一個帶有 YouTube 圖示的佔位容器，而非空白或錯誤畫面。

6. THE **YouTube_Preview_Card** SHALL 套用與現有 `linkPreviewCard` 相同的圓角樣式（`BorderRadius.circular(8)`）以保持視覺一致性。

7. WHILE 訊息為已收回狀態（`msg.isUnsent == true`），THE **YouTube_Preview_Card** SHALL 不顯示。

---

### 需求 3：內嵌影片播放

**User Story：** 身為聊天用戶，我希望點擊縮圖後能直接在 chat bubble 內播放 YouTube 影片，不需要跳轉到外部瀏覽器或 YouTube app。

#### 驗收標準

1. WHEN 用戶點擊 **YouTube_Preview_Card**，THE **YouTube_Inline_Player** SHALL 在原縮圖位置展開並取代縮圖顯示。

2. THE **YouTube_Inline_Player** SHALL 使用 `youtube_player_flutter` 套件（`^9.1.1`）實作 WebView 內嵌播放器。

3. THE **YouTube_Inline_Player** SHALL 在展開後自動開始播放影片。

4. THE **YouTube_Inline_Player** SHALL 保持 16:9 的顯示比例。

5. THE **YouTube_Inline_Player** SHALL 顯示原生播放控制列（播放/暫停、進度條、全螢幕按鈕）。

6. WHEN 用戶點擊全螢幕按鈕，THE **YouTube_Inline_Player** SHALL 切換至全螢幕播放模式。

7. WHEN **YouTube_Inline_Player** 初始化失敗（例如網路錯誤或影片不可用），THE **YouTube_Inline_Player** SHALL 顯示錯誤提示文字並保留縮圖預覽狀態，不崩潰。

8. WHEN 用戶離開聊天頁面，THE **YouTube_Inline_Player** SHALL 自動暫停播放並釋放播放器資源。

---

### 需求 4：與現有 MessageBubble 整合

**User Story：** 身為開發者，我希望 YouTube 預覽功能能無縫整合到現有的 MessageBubble 架構中，不破壞現有功能。

#### 驗收標準

1. THE **MessageBubble** SHALL 在渲染 `MessageType.text` 訊息時，優先檢查是否包含 YouTube 連結，若有則顯示 **YouTube_Preview_Card**，否則沿用現有的 `linkPreviewCard` 邏輯。

2. WHEN 訊息同時包含 YouTube 連結與後端回傳的 `LinkPreview` 資料，THE **MessageBubble** SHALL 優先顯示 **YouTube_Preview_Card**，忽略 `LinkPreview`。

3. THE **MessageBubble** SHALL 確保 YouTube 預覽卡片的最大寬度不超過 `MediaQuery.of(context).size.width * 0.75`（與現有 bubble 約束一致）。

4. THE **MessageBubble** SHALL 在 YouTube 預覽卡片與訊息時間戳之間保留 `SizedBox(height: 2)` 的間距，與現有佈局一致。

5. IF 訊息處於解密失敗、解密重試或已收回狀態，THEN THE **MessageBubble** SHALL 不顯示任何 YouTube 預覽或播放器。

---

### 需求 5：YouTube URL 解析的 Round-Trip 正確性

**User Story：** 身為開發者，我希望 YouTube URL 解析邏輯具備可驗證的正確性，以確保各種 URL 格式都能被正確處理。

#### 驗收標準

1. THE **YouTube_Detector** SHALL 對所有支援的 YouTube URL 格式，解析出的 Video_ID 長度恆為 11 個字元。

2. FOR ALL 有效的 Video_ID，THE **YouTube_Detector** SHALL 能從 `https://www.youtube.com/watch?v={videoId}` 格式的 URL 中重新提取出相同的 Video_ID（round-trip 屬性）。

3. THE **YouTube_Detector** SHALL 對任意非 YouTube URL 輸入，返回 null 而非拋出例外。

4. THE **YouTube_Detector** SHALL 對空字串輸入，返回 null 而非拋出例外。
