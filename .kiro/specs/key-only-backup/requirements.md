# 需求文件

## 簡介

本功能為 chatwmex-app（基於 Flutter 與 Go + MongoDB 的端到端加密聊天應用程式）新增「僅備份私鑰 (Key-Only Backup)」選項。此輕量級備份機制允許使用者僅將加密後的私鑰上傳至雲端，而不包含對話紀錄與媒體檔案。換機時，使用者可透過還原私鑰，從後端拉取加密歷史訊息並在本地解密。

## 術語表

- **Backup_System**: 負責管理備份與還原流程的系統元件
- **Crypto_Service**: 負責加密、解密與金鑰管理的服務元件
- **Recovery_Password**: 使用者設定的恢復密碼，用於加密私鑰
- **Private_Key**: 使用者的端到端加密私鑰
- **Backup_Mode**: 備份模式設定，包含 full（完整備份）、keyOnly（僅備份金鑰）、none（不備份）
- **Key_Backup_File**: 僅包含加密私鑰的輕量級備份檔案（chatwmex_key_backup.json）
- **Full_Backup_File**: 包含對話紀錄與媒體的完整備份檔案
- **Cloud_Storage**: 雲端儲存服務（Google Drive）
- **Settings_UI**: 備份設定使用者介面
- **Secure_Storage**: 安全儲存私鑰的本地儲存機制

## 需求

### 需求 1: 備份模式設定

**使用者故事:** 作為使用者，我想要選擇不同的備份模式，以便根據我的需求在速度、空間與完整性之間做出選擇。

#### 驗收標準

1. THE Backup_System SHALL 支援三種 Backup_Mode：full（完整備份）、keyOnly（僅備份金鑰）、none（不備份）
2. WHEN 使用者開啟備份設定頁面，THE Settings_UI SHALL 顯示備份模式選擇介面
3. THE Settings_UI SHALL 提供單選按鈕或分段控制元件供使用者選擇備份模式
4. WHEN 使用者選擇 keyOnly 模式，THE Settings_UI SHALL 顯示說明文字：「僅備份您的加密身分金鑰。速度最快，不佔空間。對話紀錄將在您換機登入時從伺服器同步並解密。」
5. WHEN 使用者變更備份模式，THE Backup_System SHALL 將新設定持久化至本地儲存

### 需求 2: 私鑰安全導出

**使用者故事:** 作為使用者，我想要確保我的私鑰在備份時受到保護，以便即使備份檔案外洩也不會危及我的安全。

#### 驗收標準

1. THE Crypto_Service SHALL 提供安全導出 Private_Key 的方法
2. WHEN 導出 Private_Key，THE Crypto_Service SHALL 使用 Recovery_Password 對 Private_Key 進行 AES-GCM 加密
3. THE Crypto_Service SHALL 產生隨機的 salt 與 initialization vector 用於金鑰加密
4. THE Crypto_Service SHALL 將加密後的私鑰、salt、initialization vector 與加密參數封裝為 JSON 格式
5. THE Crypto_Service SHALL NOT 以明文形式導出或儲存 Private_Key

### 需求 3: 僅金鑰備份執行

**使用者故事:** 作為使用者，我想要快速備份我的私鑰到雲端，以便在不需要完整備份時節省時間與空間。

#### 驗收標準

1. WHEN Backup_Mode 設定為 keyOnly，THE Backup_System SHALL 執行僅金鑰備份流程
2. WHEN 執行僅金鑰備份，THE Backup_System SHALL 呼叫 Crypto_Service 取得加密後的 Private_Key 資料
3. THE Backup_System SHALL 產生 Key_Backup_File，檔名為 chatwmex_key_backup.json
4. THE Backup_System SHALL 將 Key_Backup_File 上傳至 Cloud_Storage
5. WHEN 僅金鑰備份完成，THE Backup_System SHALL 通知使用者備份成功
6. WHEN 僅金鑰備份失敗，THE Backup_System SHALL 顯示具體的錯誤訊息

### 需求 4: 完整備份執行

**使用者故事:** 作為使用者，我想要備份完整的對話紀錄與媒體檔案，以便在換機時完整還原所有資料。

#### 驗收標準

1. WHEN Backup_Mode 設定為 full，THE Backup_System SHALL 執行完整備份流程
2. WHEN 執行完整備份，THE Backup_System SHALL 打包對話紀錄資料庫與媒體檔案
3. THE Backup_System SHALL 產生 Full_Backup_File 並上傳至 Cloud_Storage
4. WHEN 完整備份完成，THE Backup_System SHALL 通知使用者備份成功並顯示備份大小
5. WHEN 完整備份失敗，THE Backup_System SHALL 顯示具體的錯誤訊息

### 需求 5: 僅金鑰還原

**使用者故事:** 作為使用者，我想要從雲端還原我的私鑰，以便在新裝置上解密從伺服器同步的歷史訊息。

#### 驗收標準

1. WHEN 使用者啟動還原流程，THE Backup_System SHALL 檢查 Cloud_Storage 中存在的備份檔案類型
2. WHEN 偵測到 Key_Backup_File，THE Backup_System SHALL 下載並解析該檔案
3. WHEN 解析 Key_Backup_File，THE Backup_System SHALL 提示使用者輸入 Recovery_Password
4. WHEN 使用者輸入 Recovery_Password，THE Crypto_Service SHALL 使用該密碼解密 Private_Key
5. IF 解密失敗，THEN THE Backup_System SHALL 顯示錯誤訊息並允許使用者重新輸入密碼
6. WHEN 解密成功，THE Backup_System SHALL 將 Private_Key 儲存至 Secure_Storage
7. WHEN Private_Key 還原完成，THE Backup_System SHALL 觸發從後端同步加密歷史訊息的流程
8. WHEN 還原流程完成，THE Backup_System SHALL 通知使用者還原成功

### 需求 6: 完整備份還原

**使用者故事:** 作為使用者，我想要從雲端還原完整的對話紀錄與媒體檔案，以便在新裝置上立即存取所有歷史資料。

#### 驗收標準

1. WHEN 偵測到 Full_Backup_File，THE Backup_System SHALL 下載該檔案
2. THE Backup_System SHALL 解壓縮並還原對話紀錄資料庫與媒體檔案
3. WHEN 完整還原完成，THE Backup_System SHALL 通知使用者還原成功
4. WHEN 完整還原失敗，THE Backup_System SHALL 顯示具體的錯誤訊息並保持原有資料不變

### 需求 7: 錯誤處理與使用者回饋

**使用者故事:** 作為使用者，我想要在備份或還原過程中遇到問題時收到清楚的錯誤提示，以便了解問題並採取適當行動。

#### 驗收標準

1. WHEN 網路連線失敗，THE Backup_System SHALL 顯示「網路連線失敗，請檢查您的網路設定」訊息
2. WHEN Cloud_Storage 空間不足，THE Backup_System SHALL 顯示「雲端儲存空間不足，請清理空間後重試」訊息
3. WHEN Recovery_Password 錯誤，THE Backup_System SHALL 顯示「恢復密碼錯誤，請重新輸入」訊息
4. WHEN 備份檔案損壞，THE Backup_System SHALL 顯示「備份檔案損壞，無法還原」訊息
5. THE Backup_System SHALL 使用 SnackBar 或 Dialog 顯示所有錯誤訊息
6. WHEN 備份或還原操作進行中，THE Settings_UI SHALL 顯示進度指示器

### 需求 8: 資料模型與持久化

**使用者故事:** 作為開發者，我需要確保備份模式設定能夠正確儲存與讀取，以便系統能記住使用者的選擇。

#### 驗收標準

1. THE Backup_System SHALL 在設定模型中定義 Backup_Mode 列舉類型
2. THE Backup_System SHALL 使用 SharedPreferences 或本地資料庫持久化 Backup_Mode 設定
3. WHEN 應用程式啟動，THE Backup_System SHALL 讀取並載入上次儲存的 Backup_Mode 設定
4. THE Backup_System SHALL 提供 API 供其他元件查詢當前的 Backup_Mode

### 需求 9: 金鑰備份檔案格式

**使用者故事:** 作為開發者，我需要定義清楚的金鑰備份檔案格式，以便確保跨版本相容性與安全性。

#### 驗收標準

1. THE Key_Backup_File SHALL 使用 JSON 格式
2. THE Key_Backup_File SHALL 包含以下欄位：version（格式版本）、encryptedKey（加密後的私鑰）、salt（鹽值）、iv（初始化向量）、algorithm（加密演算法名稱）、timestamp（備份時間戳記）
3. THE Backup_System SHALL 在還原時驗證 Key_Backup_File 的格式版本
4. IF Key_Backup_File 格式版本不相容，THEN THE Backup_System SHALL 顯示「備份檔案版本不相容」錯誤訊息

### 需求 10: 程式碼品質與規範

**使用者故事:** 作為開發者，我需要確保程式碼符合專案規範，以便維持程式碼品質與可維護性。

#### 驗收標準

1. THE Backup_System SHALL 符合專案的 lint 規範（analysis_options.yaml）
2. THE Backup_System SHALL 為所有公開 API 提供文件註解
3. THE Backup_System SHALL 為關鍵邏輯提供單元測試
4. THE Backup_System SHALL 處理所有可預期的例外情況
