# 實作計畫：YouTube Player Screen & PiP

## 概覽

依序建立 `PipController`、`YouTubePlayerScreen`、`PipOverlay`，最後修改 `YouTubePreviewCard`，確保每個步驟都能獨立驗證，並在最後將所有元件串接起來。

## 任務

- [x] 1. 建立 PipState 資料模型與 PipController 骨架
  - 在 `app/lib/features/chat/providers/pip_controller.dart` 建立 `PipState` 類別（`isActive`、`videoId`、`position`、`isPlaying`、`overlayPosition` 欄位）
  - 建立 `PipController extends StateNotifier<PipState> with WidgetsBindingObserver`，宣告所有公開方法簽名（`startPip`、`expandPip`、`closePip`、`updatePosition`、`snapToCorner`、`togglePlayPause`）
  - 宣告 `pipControllerProvider`（`StateNotifierProvider`）
  - _需求：4.1, 4.4, 6.2_

  - [x] 1.1 為 `snapToCorner` 撰寫屬性測試
    - **Property 6：吸附角落冪等性**
    - **驗證：需求 3.5**

- [x] 2. 實作 PipController 核心邏輯
  - 實作 `startPip`：若已有 Session 先呼叫 `closePip()`，再插入 `OverlayEntry`（`PipOverlay`），更新狀態
  - 實作 `closePip`：移除 `OverlayEntry`，呼叫 `_playerController?.dispose()`，重置 `PipState`
  - 實作 `updatePosition` 與 `snapToCorner`（含邊界夾緊邏輯）
  - 實作 `togglePlayPause`
  - 實作 `WidgetsBindingObserver.didChangeAppLifecycleState`（paused 暫停、resumed 恢復）
  - _需求：2.2, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4_

  - [x] 2.1 為 PipController 撰寫屬性測試：單一 Session 不變式
    - **Property 4：單一 PiP Session 不變式**
    - **驗證：需求 4.1, 2.2**

  - [x] 2.2 為 PipController 撰寫屬性測試：App 生命週期播放狀態 Round-Trip
    - **Property 2：App 生命週期播放狀態 Round-Trip**
    - **驗證：需求 4.2, 4.3**

  - [x] 2.3 為 PipController 撰寫屬性測試：PiP 關閉後資源釋放
    - **Property 3：PiP 關閉後資源釋放**
    - **驗證：需求 3.4, 4.4, 1.4**

  - [x] 2.4 為 PipController 撰寫屬性測試：PiP 視窗位置邊界不變式
    - **Property 5：PiP 視窗位置邊界不變式**
    - **驗證：需求 3.1**

  - [x] 2.5 為 PipController 撰寫單元測試
    - 測試 `startPip` 設定 `isActive = true`
    - 測試 `closePip` 設定 `isActive = false` 並釋放資源
    - 測試 `startPip` 時若已有 Session 先關閉舊 Session
    - 測試 app 進入背景時暫停播放、返回前景時恢復播放
    - _需求：4.1, 4.2, 4.3, 4.4_

- [x] 3. 建立 YouTubePlayerScreen
  - 在 `app/lib/features/chat/ui/youtube_player_screen.dart` 建立 `YouTubePlayerScreen extends ConsumerStatefulWidget`
  - 接收 `videoId`（必要）與 `fromPip`（預設 `false`）參數
  - `initState`：若 `fromPip == false` 建立新的 `YoutubePlayerController`（`autoPlay: true`）；若 `fromPip == true` 從 `PipController` 取回 controller
  - 以 16:9 比例顯示 `YoutubePlayer`，並顯示標題區域與控制列
  - 顯示「畫中畫」按鈕（`Icons.picture_in_picture_alt`），點擊後呼叫 `PipController.startPip` 並 `Navigator.pop`
  - `dispose`：若無進行中的 PiP Session，呼叫 `controller.dispose()`
  - 監聽 `controller.value.hasError`，發生錯誤時顯示錯誤提示與返回按鈕
  - _需求：1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 5.2, 6.1, 6.3_

  - [x] 3.1 為 YouTubePlayerScreen 撰寫屬性測試：縮圖點擊導航與播放器初始化
    - **Property 8：縮圖點擊導航與播放器初始化**
    - **驗證：需求 1.1, 1.2**

  - [x] 3.2 為 YouTubePlayerScreen 撰寫 Widget 測試
    - 測試顯示 PiP 按鈕
    - 測試點擊 PiP 按鈕啟動 PiP Session
    - 測試 `fromPip=true` 時從 `PipController` 取回 controller
    - 測試返回時若無 PiP Session 釋放 controller
    - _需求：1.4, 2.1, 2.2, 6.1_

- [x] 4. 建立 PipOverlay Widget
  - 在 `app/lib/features/chat/ui/widgets/pip_overlay.dart` 建立 `PipOverlay extends ConsumerStatefulWidget`
  - 尺寸：寬 200dp × 高 112.5dp（16:9），圓角 12，`BoxShadow` elevation 8
  - 以 `YoutubePlayer` 顯示影片（使用 `PipController` 持有的 controller）
  - 顯示三個控制按鈕：關閉（左上角）、播放/暫停（中央）、展開（右上角）
  - 以 `GestureDetector.onPanUpdate` 呼叫 `updatePosition`，`onPanEnd` 呼叫 `snapToCorner`
  - 以 `AnimatedPositioned` 實作吸附動畫（duration: 200ms）
  - 點擊展開按鈕呼叫 `PipController.expandPip`；點擊關閉按鈕呼叫 `PipController.closePip`
  - PiP 模式下發生播放錯誤時顯示錯誤圖示並自動呼叫 `closePip`
  - _需求：2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5_

  - [x] 4.1 為 PipOverlay 撰寫 Widget 測試
    - 測試顯示播放/暫停、展開、關閉按鈕
    - 測試點擊關閉按鈕呼叫 `closePip`
    - 測試點擊展開按鈕呼叫 `expandPip`
    - 測試拖曳後觸發 `snapToCorner`
    - _需求：3.2, 3.3, 3.4, 3.5_

- [x] 5. 修改 YouTubePreviewCard
  - 將 `YouTubePreviewCard` 從 `StatefulWidget` 改為 `ConsumerStatefulWidget`
  - 移除 `_isPlayerExpanded` 狀態與 `YouTubeInlinePlayer` 的展開邏輯
  - 修改 `onTap`：若有進行中的 PiP Session 先呼叫 `closePip()`，再 `Navigator.push` 至 `YouTubePlayerScreen`
  - 保留縮圖顯示邏輯（縮圖 URL、播放按鈕疊加層、圓角樣式）完全不變
  - _需求：1.1, 4.1, 5.1, 5.4_

  - [x] 5.1 為 YouTubePreviewCard 撰寫屬性測試：MessageBubble 狀態保護不變式
    - **Property 9：MessageBubble 狀態保護不變式**
    - **驗證：需求 5.3**

  - [x] 5.2 為 YouTubePreviewCard 撰寫 Widget 測試
    - 測試點擊縮圖導航至 `YouTubePlayerScreen`
    - 測試點擊縮圖時若有 PiP Session 先關閉
    - 測試縮圖顯示邏輯與修改前一致
    - _需求：1.1, 4.1, 5.1_

- [x] 6. 串接：在 MaterialApp 根 Overlay 掛載 PipController
  - 確認 `pipControllerProvider` 在 app 根層級（`ProviderScope`）可存取
  - 確認 `PipController.startPip` 使用根 `Overlay` 的 `BuildContext` 插入 `OverlayEntry`（可透過 `navigatorKey` 或在 `MaterialApp` 的 `builder` 中取得）
  - 確認 `PipOverlay` 在所有路由頁面之上正確顯示
  - _需求：2.4, 2.5_

  - [x] 6.1 為 PiP 播放位置 Round-Trip 撰寫屬性測試
    - **Property 1：PiP 播放位置 Round-Trip**
    - **驗證：需求 6.1, 6.4, 3.3**

  - [x] 6.2 為 PiP 暫停狀態保持撰寫屬性測試
    - **Property 7：PiP 暫停狀態保持**
    - **驗證：需求 6.3**

- [x] 7. 最終檢查點 — 確認所有測試通過
  - 確認所有測試通過，如有疑問請向用戶確認。

## 備註

- 標有 `*` 的子任務為選填，可跳過以加速 MVP 開發
- 每個任務均標注對應需求編號以利追蹤
- 屬性測試使用現有 `glados` 套件（`dev_dependencies`），每個屬性最少執行 100 次迭代
- 測試標籤格式：`// Feature: youtube-player-screen-pip, Property {N}: {property_text}`
- `YoutubePlayerController` 所有權在 `YouTubePlayerScreen` 與 `PipController` 之間移交，不重建，確保播放位置連續
