# 需求文件

## 簡介

本功能改良現有的 YouTube inline player 體驗。目前點擊縮圖會在 message bubble 內展開播放器（inline），新功能改為彈出一個獨立的播放 Screen，並支援畫中畫（Picture-in-Picture，PiP）模式。用戶可在觀看影片的同時繼續使用 app（回到聊天列表、切換對話等），體驗類似 WhatsApp 的浮動影片播放器。

現有的 `YouTubePreviewCard` 縮圖預覽卡片保持不變，僅改變點擊後的行為：從 inline 展開改為導航至獨立播放 Screen，並在該 Screen 支援 PiP 模式。

## 詞彙表

- **YouTube_Player_Screen**：新增的獨立全版播放 Screen，透過 `Navigator.push` 開啟，顯示 YouTube 播放器及相關控制項
- **PiP_Controller**：負責管理畫中畫（Picture-in-Picture）模式的元件，控制 PiP 視窗的啟動、關閉與位置
- **PiP_Overlay**：在 app 內以浮動視窗形式顯示的迷你播放器，覆蓋在其他頁面之上
- **YouTube_Preview_Card**：現有的縮圖預覽卡片 Widget（`youtube_preview_card.dart`），點擊後觸發導航至 YouTube_Player_Screen
- **YouTube_Inline_Player**：現有的內嵌播放器 Widget（`youtube_inline_player.dart`），將被 YouTube_Player_Screen 取代作為主要播放介面
- **Video_ID**：YouTube 影片的唯一識別碼（11 個字元）
- **PiP_Session**：從開啟 PiP 模式到關閉的完整生命週期
- **MessageBubble**：現有的 chat bubble Widget，整合 YouTube_Preview_Card 的入口點

---

## 需求

### 需求 1：從縮圖導航至獨立播放 Screen

**User Story：** 身為聊天用戶，我希望點擊 YouTube 縮圖後能開啟一個獨立的播放頁面，以便獲得更好的觀看體驗。

#### 驗收標準

1. WHEN 用戶點擊 **YouTube_Preview_Card** 的縮圖，THE **YouTube_Preview_Card** SHALL 透過 `Navigator.push` 導航至 **YouTube_Player_Screen**，而非在 bubble 內展開播放器。

2. THE **YouTube_Player_Screen** SHALL 接收 Video_ID 作為必要參數，並在開啟後自動開始播放對應影片。

3. THE **YouTube_Player_Screen** SHALL 顯示影片標題區域、播放器本體及控制列（播放/暫停、進度條、全螢幕按鈕）。

4. WHEN 用戶點擊 **YouTube_Player_Screen** 的返回按鈕，THE **YouTube_Player_Screen** SHALL 關閉並返回原聊天頁面，同時停止播放並釋放播放器資源。

5. THE **YouTube_Player_Screen** SHALL 以 16:9 比例顯示播放器，並支援橫向全螢幕切換。

---

### 需求 2：畫中畫（PiP）模式啟動

**User Story：** 身為聊天用戶，我希望在觀看影片時能切換至畫中畫模式，以便同時繼續使用 app 的其他功能。

#### 驗收標準

1. THE **YouTube_Player_Screen** SHALL 在播放器控制區域顯示一個「畫中畫」按鈕（`Icons.picture_in_picture_alt` 或同等圖示）。

2. WHEN 用戶點擊畫中畫按鈕，THE **PiP_Controller** SHALL 啟動 PiP_Session，將播放器縮小為浮動的 **PiP_Overlay** 視窗，並關閉 **YouTube_Player_Screen**。

3. THE **PiP_Overlay** SHALL 以固定的最小尺寸（寬度不小於 160dp、高度不小於 90dp）顯示，維持 16:9 比例。

4. THE **PiP_Overlay** SHALL 顯示於 app 所有頁面的最上層，不被其他 Widget 遮擋。

5. WHILE **PiP_Session** 進行中，THE **PiP_Overlay** SHALL 持續播放影片，不因頁面切換而中斷。

6. IF 裝置不支援系統層級 PiP（如部分 Android 版本），THEN THE **PiP_Controller** SHALL 以 app 內浮動視窗（in-app overlay）方式實作 PiP_Overlay，提供相同的使用體驗。

---

### 需求 3：PiP 視窗互動

**User Story：** 身為聊天用戶，我希望能拖曳 PiP 視窗並控制播放，以便在使用 app 時靈活調整影片位置。

#### 驗收標準

1. WHILE **PiP_Session** 進行中，THE **PiP_Overlay** SHALL 支援用戶以拖曳手勢移動視窗位置，移動範圍限制在螢幕可見區域內。

2. WHILE **PiP_Session** 進行中，THE **PiP_Overlay** SHALL 在視窗上顯示播放/暫停切換按鈕，讓用戶無需展開即可控制播放狀態。

3. WHEN 用戶點擊 **PiP_Overlay** 的展開按鈕（或雙擊視窗），THE **PiP_Controller** SHALL 結束 PiP_Session 並重新導航至 **YouTube_Player_Screen**，從當前播放位置繼續播放。

4. WHEN 用戶點擊 **PiP_Overlay** 的關閉按鈕，THE **PiP_Controller** SHALL 結束 PiP_Session，停止播放並釋放所有播放器資源。

5. WHEN **PiP_Overlay** 被拖曳至螢幕邊緣並釋放，THE **PiP_Overlay** SHALL 自動吸附至最近的螢幕角落（snap-to-corner 行為）。

---

### 需求 4：PiP 生命週期與狀態管理

**User Story：** 身為開發者，我希望 PiP 功能具備清晰的生命週期管理，以避免資源洩漏與狀態不一致。

#### 驗收標準

1. THE **PiP_Controller** SHALL 確保同一時間最多只有一個 PiP_Session 存在；WHEN 用戶在 PiP_Session 進行中點擊另一個 YouTube 縮圖，THE **PiP_Controller** SHALL 先結束現有 PiP_Session，再開啟新的 **YouTube_Player_Screen**。

2. WHEN app 進入背景（`AppLifecycleState.paused`），THE **PiP_Controller** SHALL 暫停 **PiP_Overlay** 的影片播放。

3. WHEN app 從背景返回前景（`AppLifecycleState.resumed`），THE **PiP_Controller** SHALL 恢復 **PiP_Overlay** 的影片播放（若 PiP_Session 仍在進行中）。

4. WHEN **PiP_Session** 結束（無論透過關閉按鈕或展開），THE **PiP_Controller** SHALL 釋放 `YoutubePlayerController` 資源，避免記憶體洩漏。

5. IF **YouTube_Player_Screen** 在 PiP_Session 進行中被系統回收（如記憶體不足），THEN THE **PiP_Controller** SHALL 安全地結束 PiP_Session 並釋放資源，不崩潰。

---

### 需求 5：與現有架構的相容性

**User Story：** 身為開發者，我希望新的播放 Screen 與 PiP 功能能無縫整合到現有架構，不破壞現有的 YouTube 縮圖預覽功能。

#### 驗收標準

1. THE **YouTube_Preview_Card** SHALL 保留現有的縮圖顯示邏輯（縮圖 URL、播放按鈕疊加層、圓角樣式），僅將點擊行為從 inline 展開改為導航至 **YouTube_Player_Screen**。

2. THE **YouTube_Player_Screen** SHALL 沿用現有 `youtube_player_flutter` 套件（`^9.1.1`）作為播放器核心，不引入額外的 YouTube 播放套件。

3. THE **MessageBubble** SHALL 在 YouTube 縮圖預覽的顯示條件（解密失敗、解密重試、已收回等狀態保護）上保持與現有邏輯完全一致。

4. WHEN **YouTube_Player_Screen** 開啟時，THE **MessageBubble** 中的 **YouTube_Preview_Card** SHALL 保持縮圖狀態（不展開 inline 播放器），確保返回聊天頁面時視覺狀態正確。

5. THE **YouTube_Player_Screen** SHALL 支援 iOS 與 Android 兩個平台，並在兩個平台上提供一致的 PiP 使用體驗。

---

### 需求 6：PiP 視窗的 Round-Trip 狀態一致性

**User Story：** 身為聊天用戶，我希望在 PiP 模式與全螢幕播放之間切換時，播放進度能保持連續，不發生跳轉或重置。

#### 驗收標準

1. WHEN 用戶從 **YouTube_Player_Screen** 切換至 PiP_Overlay，再從 PiP_Overlay 展開回 **YouTube_Player_Screen**，THE **YouTube_Player_Screen** SHALL 從切換前的播放位置繼續播放（round-trip 播放位置保持）。

2. THE **PiP_Controller** SHALL 在 PiP_Session 期間持續追蹤當前播放位置（`position`），精確度為 1 秒以內。

3. WHEN 用戶在 PiP_Overlay 中暫停影片後展開至 **YouTube_Player_Screen**，THE **YouTube_Player_Screen** SHALL 保持暫停狀態，不自動重新播放。

4. FOR ALL 有效的 Video_ID，從 **YouTube_Player_Screen** 進入 PiP 模式再返回，播放位置的誤差 SHALL 不超過 2 秒。
