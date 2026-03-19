# 實作計畫：YouTube Inline Player

## 概覽

依序實作 YouTube URL 偵測工具、縮圖預覽卡片、內嵌播放器，最後整合至現有 `MessageBubble`。每個步驟都建立在前一步驟的基礎上，確保無孤立程式碼。

## 任務

- [x] 1. 新增 `youtube_player_flutter` 套件依賴
  - 在 `app/pubspec.yaml` 的 `dependencies` 區塊新增 `youtube_player_flutter: ^9.1.1`
  - 執行 `flutter pub get` 確認套件安裝成功
  - _需求：3.2_

- [x] 2. 實作 `YouTubeDetector` 工具類
  - 建立 `app/lib/features/chat/utils/youtube_detector.dart`
  - 實作靜態方法 `extractVideoId(String content)` 使用正規表達式解析所有支援的 YouTube URL 格式
  - 實作靜態方法 `thumbnailUrl(String videoId)` 回傳標準縮圖 URL
  - 驗證提取的 Video ID 長度恆為 11 個字元，否則回傳 null
  - _需求：1.1, 1.2, 1.3, 1.4, 2.2, 5.1, 5.2_

  - [x] 2.1 為 `YouTubeDetector.extractVideoId` 撰寫屬性測試（Property 1）
    - 建立 `app/test/features/chat/youtube_detector_test.dart`
    - **Property 1：YouTube URL Round-Trip 解析**
    - **Validates: Requirements 1.1, 1.2, 5.1, 5.2**
    - 使用 `glados` 套件，對任意有效 videoId 組合成各支援格式 URL 後解析，應得到相同 videoId

  - [x] 2.2 為 `YouTubeDetector.extractVideoId` 撰寫屬性測試（Property 2）
    - **Property 2：非 YouTube 輸入的安全性**
    - **Validates: Requirements 1.3, 5.3, 5.4**
    - 對任意字串輸入，`extractVideoId` 不應拋出例外，應回傳 null

  - [x] 2.3 為 `YouTubeDetector.extractVideoId` 撰寫屬性測試（Property 3）
    - **Property 3：無效 YouTube URL 返回 null**
    - **Validates: Requirements 1.4**
    - 對格式錯誤的 YouTube URL（Video ID 長度不足 11、含非法字元），應回傳 null

  - [x] 2.4 為 `YouTubeDetector.thumbnailUrl` 撰寫屬性測試（Property 4）
    - **Property 4：縮圖 URL 格式正確性**
    - **Validates: Requirements 2.2**
    - 對任意有效 videoId，`thumbnailUrl` 應回傳包含 videoId 且格式為 `https://img.youtube.com/vi/{videoId}/hqdefault.jpg` 的字串

  - [x] 2.5 為 `YouTubeDetector` 撰寫單元測試（具體範例）
    - 測試所有支援的 URL 格式（`watch?v=`、`youtu.be/`、`shorts/`、`m.youtube.com`）
    - 測試邊界條件：空字串、純文字、Video ID 長度不足 11
    - _需求：1.1, 1.2, 1.3, 1.4_

- [x] 3. 檢查點 - 確認所有測試通過
  - 確認所有測試通過，如有問題請提出。

- [x] 4. 實作 `YouTubePreviewCard` Widget
  - 建立 `app/lib/features/chat/ui/widgets/youtube_preview_card.dart`
  - 實作 `StatefulWidget`，包含 `videoId`、`isMe`、`maxWidth` 參數
  - 使用 `CachedNetworkImageWidget`（現有元件）顯示縮圖，寬度為 `maxWidth`，高度為 `maxWidth * 9 / 16`
  - 在縮圖中央疊加 `Icons.play_circle_filled`（大小 48，白色）
  - 縮圖載入失敗時顯示帶有 `Icons.smart_display` 的佔位容器
  - 套用 `BorderRadius.circular(8)` 圓角
  - 點擊後將 `_isPlayerExpanded` 設為 true，切換至 `YouTubeInlinePlayer`
  - _需求：2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1_

  - [ ]* 4.1 為 `YouTubePreviewCard` 撰寫 Widget 測試
    - 建立 `app/test/features/chat/youtube_preview_card_test.dart`
    - 測試縮圖正確渲染（含播放按鈕圖示）
    - 測試點擊後切換至播放器狀態
    - 測試縮圖載入失敗時顯示佔位容器
    - _需求：2.3, 2.5, 3.1_

- [x] 5. 實作 `YouTubeInlinePlayer` Widget
  - 建立 `app/lib/features/chat/ui/widgets/youtube_inline_player.dart`
  - 實作 `StatefulWidget`，包含 `videoId`、`width`、`onError` callback 參數
  - 在 `initState` 中建立 `YoutubePlayerController`，設定 `autoPlay: true`
  - 在 `dispose` 中呼叫 `controller.close()` 釋放資源
  - 監聽 `controller.value.hasError`，發生錯誤時呼叫 `onError` callback 並顯示錯誤提示文字
  - 保持 16:9 顯示比例，顯示原生播放控制列
  - _需求：3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_

  - [ ]* 5.1 為 `YouTubeInlinePlayer` 撰寫 Widget 測試
    - 建立 `app/test/features/chat/youtube_inline_player_test.dart`
    - 測試播放器初始化後自動播放
    - 測試錯誤狀態下顯示錯誤提示並觸發 `onError` callback
    - 測試 `dispose` 時釋放播放器資源
    - _需求：3.3, 3.7, 3.8_

- [x] 6. 整合至 `MessageBubble`
  - 修改 `app/lib/features/chat/ui/widgets/message_bubble.dart`
  - 在檔案頂部新增 `YouTubeDetector`、`YouTubePreviewCard` 的 import
  - 在 `build()` 方法中，於現有 `hasPreview` 判斷之前插入 YouTube 偵測邏輯：
    - 僅在 `msg.type == MessageType.text`、非 `isUnsent`、非 `isDecryptionFailure`、非 `isDecryptingRetry` 時呼叫 `YouTubeDetector.extractVideoId`
  - 修改 `hasPreview` 條件，當 `youtubeVideoId != null` 時排除 `linkPreviewCard`
  - 在 `Column` children 中，以 `YouTubePreviewCard` 取代 `linkPreviewCard` 的條件渲染
  - 確保 `YouTubePreviewCard` 與時間戳之間保留 `SizedBox(height: 2)` 間距
  - _需求：4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ]* 6.1 為 `MessageBubble` YouTube 整合撰寫 Widget 測試
    - 建立 `app/test/features/chat/message_bubble_youtube_test.dart`
    - 測試含 YouTube URL 的文字訊息顯示 `YouTubePreviewCard`
    - 測試 YouTube URL 優先於 `LinkPreview` 顯示
    - 測試已收回訊息不顯示 YouTube 預覽
    - 測試解密失敗訊息不顯示 YouTube 預覽
    - _需求：4.1, 4.2, 4.5_

- [x] 7. 最終檢查點 - 確認所有測試通過
  - 確認所有測試通過，如有問題請提出。

## 備註

- 標有 `*` 的子任務為選填，可跳過以加速 MVP 開發
- 每個任務均對應具體需求，確保可追溯性
- 屬性測試使用現有 `glados` 套件（已在 `pubspec.yaml` dev_dependencies 中）
- 所有新 Widget 均使用現有 `CachedNetworkImageWidget` 和 `ChatThemeTokens`，保持視覺一致性
