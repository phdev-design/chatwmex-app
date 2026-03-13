# 實作計畫：僅備份私鑰 (Key-Only Backup)

## 概述

本實作計畫將為 chatwmex-app 新增「僅備份私鑰」功能，允許使用者選擇輕量級備份模式，僅上傳加密後的私鑰至 Google Drive，而不包含對話紀錄與媒體檔案。實作將基於現有的 Flutter + Dart 架構，擴充 BackupManager、CryptoService 與 GoogleDriveService，並修改相關 UI 元件。

## 任務清單

- [x] 1. 建立資料模型與列舉類型
  - 建立 `app/lib/models/backup_mode.dart`，定義 BackupMode 列舉（full, keyOnly, none）
  - 建立 `app/lib/models/key_backup_file.dart`，定義 KeyBackupFile 資料模型
  - 建立 `app/lib/models/backup_file_info.dart`，定義 BackupFileInfo 與 BackupType 列舉
  - 為每個模型新增 JSON 序列化/反序列化方法
  - 為 BackupMode 新增 displayName 與 description getter
  - _需求: 1.1, 8.1, 9.1, 9.2_

- [ ]* 1.1 為資料模型撰寫單元測試
  - 測試 BackupMode 的 fromString 方法
  - 測試 KeyBackupFile 的 JSON 序列化與反序列化
  - 測試 KeyBackupFile.isValid() 驗證邏輯
  - 測試 BackupFileInfo 的 displaySize 格式化
  - _需求: 10.3_

- [x] 2. 擴充 BackupState 資料模型
  - 在 `app/lib/core/backup/backup_manager.dart` 的 BackupState 類別中新增 backupMode 屬性
  - 修改 BackupState 建構函式，預設值為 BackupMode.full
  - 修改 copyWith 方法，支援 backupMode 參數
  - _需求: 1.1, 8.1_

- [x] 3. 實作 BackupManager 的備份模式管理
  - [x] 3.1 實作 setBackupMode 方法
    - 使用 SharedPreferences 持久化備份模式設定
    - 更新 BackupState 的 backupMode 屬性
    - _需求: 1.5, 8.2_

  - [x] 3.2 修改 BackupManager 初始化邏輯
    - 在建構函式或初始化方法中從 SharedPreferences 讀取備份模式
    - 載入上次儲存的備份模式至 state
    - _需求: 8.3_

  - [ ]* 3.3 撰寫屬性測試：備份模式持久化往返一致性
    - **屬性 1: Backup Mode Persistence Round-Trip**
    - **驗證需求: 1.1, 1.5, 8.2, 8.3**
    - 測試任意備份模式設定後重啟應用程式，載入的模式應與原始設定相同

- [x] 4. 實作僅金鑰備份功能
  - [x] 4.1 實作 BackupManager.backupKeyOnly 方法
    - 從 CryptoService 取得原始私鑰
    - 使用 backupPassword 加密私鑰
    - 建立 KeyBackupFile JSON 結構
    - 上傳至 Google Drive（檔名：chatwmex_key_backup.json）
    - 更新 lastBackupDate 與 BackupState
    - 處理錯誤情境（無私鑰、上傳失敗）
    - _需求: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ]* 4.2 撰寫單元測試：僅金鑰備份流程
    - 測試成功備份情境
    - 測試無私鑰時的錯誤處理
    - 測試上傳失敗時的錯誤處理
    - 驗證 lastBackupDate 更新
    - _需求: 3.6, 10.3_

  - [ ]* 4.3 撰寫屬性測試：加密輸出格式有效性
    - **屬性 4: Encrypted Key Format Validity**
    - **驗證需求: 2.4, 9.1, 9.2**
    - 測試任意私鑰與密碼加密後的輸出應為有效 JSON，包含所有必要欄位

- [x] 5. 實作僅金鑰還原功能
  - [x] 5.1 實作 BackupManager.restoreKeyOnly 方法
    - 從 Google Drive 下載金鑰備份檔案
    - 解析 JSON 並驗證版本相容性
    - 使用 backupPassword 解密私鑰
    - 還原私鑰至 FlutterSecureStorage
    - 處理錯誤情境（下載失敗、版本不相容、密碼錯誤、檔案損壞）
    - _需求: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7_

  - [ ]* 5.2 撰寫單元測試：僅金鑰還原流程
    - 測試成功還原情境
    - 測試密碼錯誤時的錯誤處理
    - 測試版本不相容時的錯誤處理
    - 測試檔案損壞時的錯誤處理
    - 驗證還原失敗時本地資料不變
    - _需求: 5.5, 6.4, 10.3_

  - [ ]* 5.3 撰寫屬性測試：私鑰加密往返一致性
    - **屬性 2: Private Key Encryption Round-Trip**
    - **驗證需求: 2.2, 5.4**
    - 測試任意私鑰與密碼，加密後再解密應得到原始私鑰

- [x] 6. 檢查點 - 確保核心備份與還原邏輯正確
  - 確保所有測試通過，若有疑問請詢問使用者

- [x] 7. 修改 BackupManager.backupNow 方法
  - 根據 state.backupMode 決定執行哪種備份
  - BackupMode.full: 呼叫現有的完整備份邏輯
  - BackupMode.keyOnly: 驗證 backupPassword 存在，呼叫 backupKeyOnly
  - BackupMode.none: 不執行任何操作
  - 處理 keyOnly 模式下缺少密碼的錯誤
  - _需求: 1.1, 3.1_

- [ ]* 7.1 撰寫單元測試：backupNow 路由邏輯
  - 測試 full 模式呼叫完整備份
  - 測試 keyOnly 模式呼叫僅金鑰備份
  - 測試 none 模式不執行任何操作
  - 測試 keyOnly 模式缺少密碼時的錯誤
  - _需求: 1.1, 3.1, 10.3_

- [x] 8. 擴充 GoogleDriveService
  - [x] 8.1 實作 listAllBackups 方法
    - 列出 Google Drive 中所有備份檔案
    - 根據檔名判斷備份類型（包含 "key_backup" 為 keyOnly，否則為 full）
    - 回傳 List<BackupFileInfo>，包含檔案 ID、名稱、建立時間、大小與類型
    - _需求: 5.1_

  - [ ]* 8.2 撰寫單元測試：listAllBackups 方法
    - 測試正確識別金鑰備份檔案
    - 測試正確識別完整備份檔案
    - 測試空列表情境
    - _需求: 10.3_

- [x] 9. 實作 UI：備份模式選擇介面
  - [x] 9.1 修改 SettingsPage
    - 在 `app/lib/features/profile/ui/settings_page.dart` 新增備份模式選擇 ListTile
    - 顯示當前備份模式的 displayName
    - 點擊時開啟備份模式選擇對話框
    - _需求: 1.2, 1.3_

  - [x] 9.2 實作備份模式選擇對話框
    - 建立 _showBackupModeDialog 方法
    - 使用 RadioListTile 或 SimpleDialog 顯示三種模式
    - 每個選項顯示 displayName 與 description
    - 選擇後呼叫 BackupManager.setBackupMode
    - _需求: 1.3, 1.4_

  - [ ]* 9.3 撰寫 Widget 測試：備份模式選擇介面
    - 測試備份模式選項正確顯示
    - 測試選擇模式後狀態更新
    - 測試說明文字正確顯示
    - _需求: 1.2, 1.3, 1.4, 10.3_

- [x] 10. 實作 UI：備份執行流程修改
  - [x] 10.1 修改 BackupConversationsPage._handleBackupNow
    - 在 `app/lib/features/chat/ui/backup_conversations_page.dart` 修改備份執行邏輯
    - 根據 backupMode 決定是否需要密碼輸入
    - keyOnly 模式：必須輸入密碼
    - full 模式：可選擇是否輸入密碼
    - none 模式：顯示提示訊息，不執行備份
    - _需求: 1.1, 3.1_

  - [x] 10.2 實作密碼輸入對話框
    - 建立 _showPasswordDialog 方法，支援 required 參數
    - 使用 TextField 輸入密碼，支援顯示/隱藏密碼
    - 驗證密碼長度（至少 6 個字元）
    - 回傳密碼或 null（使用者取消）
    - _需求: 3.1_

  - [ ]* 10.3 撰寫 Widget 測試：備份執行流程
    - 測試 keyOnly 模式顯示密碼對話框
    - 測試密碼驗證邏輯
    - 測試使用者取消時不執行備份
    - _需求: 10.3_

- [x] 11. 實作 UI：還原流程修改
  - [x] 11.1 修改 BackupHistoryPage._handleRestore
    - 在 `app/lib/features/chat/ui/backup_conversations_page.dart` 或相關頁面修改還原邏輯
    - 根據 BackupFileInfo.type 決定還原流程
    - BackupType.keyOnly: 顯示密碼輸入對話框，呼叫 restoreKeyOnly
    - BackupType.full: 使用現有的完整還原邏輯
    - _需求: 5.1, 5.2, 5.3_

  - [x] 11.2 實作還原成功回饋
    - keyOnly 還原成功後顯示 SnackBar：「私鑰還原成功！正在從伺服器同步訊息...」
    - full 還原成功後顯示現有的成功訊息
    - _需求: 5.8_

  - [ ]* 11.3 撰寫 Widget 測試：還原流程
    - 測試 keyOnly 還原顯示密碼輸入
    - 測試還原成功顯示正確訊息
    - 測試還原失敗顯示錯誤訊息
    - _需求: 10.3_

- [x] 12. 檢查點 - 確保 UI 整合正確
  - 確保所有測試通過，若有疑問請詢問使用者

- [x] 13. 實作錯誤處理與使用者回饋
  - [x] 13.1 統一錯誤訊息處理
    - 在 BackupManager 中為所有錯誤情境設定清楚的錯誤訊息
    - 網路錯誤：「網路連線失敗，請檢查您的網路設定」
    - 認證錯誤：「請先連接 Google Drive」
    - 儲存空間錯誤：「雲端儲存空間不足，請清理空間後重試」
    - 密碼錯誤：「恢復密碼錯誤，請重新輸入」
    - 檔案損壞：「備份檔案損壞，無法還原」
    - 版本不相容：「備份檔案版本不相容」
    - _需求: 7.1, 7.2, 7.3, 7.4, 9.4_

  - [x] 13.2 實作進度指示器
    - 在 BackupConversationsPage 中，當 isBackingUp 為 true 時顯示 CircularProgressIndicator
    - 禁用備份按鈕防止重複操作
    - _需求: 7.6_

  - [ ]* 13.3 撰寫單元測試：錯誤處理
    - 測試各種錯誤情境的錯誤訊息
    - 驗證錯誤訊息非空且具描述性
    - _需求: 7.1, 7.2, 7.3, 7.4, 10.3, 10.4_

  - [ ]* 13.4 撰寫屬性測試：備份失敗錯誤回報
    - **屬性 6: Backup Failure Error Reporting**
    - **驗證需求: 3.6, 4.5**
    - 測試任意備份操作失敗時，系統應顯示非空錯誤訊息

- [ ] 14. 實作加密安全性驗證
  - [ ]* 14.1 撰寫屬性測試：加密隨機性
    - **屬性 3: Encryption Randomness**
    - **驗證需求: 2.3**
    - 測試多次加密相同私鑰應產生不同的 salt 與 IV

  - [ ]* 14.2 撰寫屬性測試：無明文洩漏
    - **屬性 5: No Plaintext Leakage**
    - **驗證需求: 2.5**
    - 測試加密輸出不應包含原始私鑰的明文或 base64 編碼形式

- [x] 15. 程式碼品質與文件
  - [x] 15.1 執行 Flutter analyze
    - 確保所有新增程式碼符合 analysis_options.yaml 規範
    - 修正所有 lint 警告與錯誤
    - _需求: 10.1_

  - [x] 15.2 新增文件註解
    - 為所有公開 API 新增 Dart 文件註解
    - 為複雜邏輯新增內聯註解
    - _需求: 10.2_

  - [x] 15.3 執行所有測試
    - 執行 `flutter test` 確保所有單元測試與屬性測試通過
    - 確保測試覆蓋率達到 80% 以上
    - _需求: 10.3_

- [x] 16. 最終檢查點
  - 確保所有測試通過，若有疑問請詢問使用者

## 注意事項

- 標記 `*` 的任務為可選測試任務，可跳過以加快 MVP 開發
- 每個任務都標註了對應的需求編號，確保可追溯性
- 檢查點任務確保增量驗證，及早發現問題
- 屬性測試驗證通用正確性屬性，單元測試驗證具體範例與邊界條件
- 所有程式碼應使用 Dart 語言，遵循 Flutter 最佳實踐
