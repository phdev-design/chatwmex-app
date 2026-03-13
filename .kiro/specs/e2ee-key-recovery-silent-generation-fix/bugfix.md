# Bugfix Requirements Document

## Introduction

當前 E2EE 加密服務在初始化時，若偵測不到本地儲存的私鑰（例如 iOS 模擬器重啟導致 Keychain 資料遺失、用戶更換裝置或重新安裝應用），會自動靜默生成一把全新的金鑰對。這導致用戶無法解密任何歷史訊息，且沒有機會使用備份密碼還原舊金鑰。

本 bugfix 旨在修復此靜默金鑰生成行為，改為在偵測到私鑰遺失時，提示用戶選擇「從雲端還原金鑰」或「強制生成新金鑰」，確保用戶能夠有意識地做出選擇，並在可能的情況下保留對歷史訊息的存取能力。

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN `CryptoService.initialize(userId)` 被呼叫且 `_secureStorage` 中找不到 `storedPrivateKeyBase64` THEN 系統自動靜默生成新的金鑰對並寫入 Storage，不通知用戶

1.2 WHEN 用戶在 iOS 模擬器重啟後登入應用 THEN 系統靜默生成新金鑰，導致所有歷史訊息顯示為無法解密

1.3 WHEN 用戶更換裝置或重新安裝應用後登入 THEN 系統靜默生成新金鑰，用戶失去存取歷史訊息的機會，即使他們擁有備份密碼

1.4 WHEN 私鑰遺失且系統靜默生成新金鑰 THEN 用戶沒有任何 UI 提示或警告，無法得知歷史訊息將永久無法解密

### Expected Behavior (Correct)

2.1 WHEN `CryptoService.initialize(userId)` 被呼叫且 `_secureStorage` 中找不到 `storedPrivateKeyBase64` 且 `forceGenerate` 參數為 `false` THEN 系統 SHALL 拋出 `PrivateKeyNotFoundException` 例外，不自動生成金鑰

2.2 WHEN `CryptoService.initialize(userId, forceGenerate: true)` 被呼叫且 `_secureStorage` 中找不到 `storedPrivateKeyBase64` THEN 系統 SHALL 生成新的金鑰對並寫入 Storage

2.3 WHEN 應用初始化過程中捕捉到 `PrivateKeyNotFoundException` THEN 系統 SHALL 顯示金鑰還原 UI（對話框或專屬頁面），提供「從雲端還原金鑰」和「強制生成新金鑰」兩個選項

2.4 WHEN 用戶在金鑰還原 UI 中輸入備份密碼並點擊「從雲端還原金鑰」THEN 系統 SHALL 從後端取得加密的私鑰 payload，使用 `decryptPrivateKeyFromBackup` 解密，並在成功後呼叫 `restorePrivateKey` 還原金鑰

2.5 WHEN 用戶在金鑰還原 UI 中輸入錯誤的備份密碼 THEN 系統 SHALL 顯示錯誤提示訊息「密碼錯誤，請重試」

2.6 WHEN 用戶在金鑰還原 UI 中點擊「強制生成新金鑰」按鈕 THEN 系統 SHALL 顯示警告訊息說明歷史訊息將無法解密，並在用戶確認後呼叫 `initialize(userId, forceGenerate: true)`

2.7 WHEN 金鑰還原或強制生成成功完成 THEN 系統 SHALL 繼續正常的登入流程，進入聊天列表頁面

### Unchanged Behavior (Regression Prevention)

3.1 WHEN `CryptoService.initialize(userId)` 被呼叫且 `_secureStorage` 中存在有效的 `storedPrivateKeyBase64` THEN 系統 SHALL CONTINUE TO 正常載入現有私鑰並完成初始化

3.2 WHEN 用戶正常登入且本地私鑰存在 THEN 系統 SHALL CONTINUE TO 直接進入聊天列表，不顯示金鑰還原 UI

3.3 WHEN `encryptPrivateKeyForBackup` 和 `decryptPrivateKeyFromBackup` 方法被呼叫 THEN 系統 SHALL CONTINUE TO 使用現有的加密/解密邏輯處理備份金鑰

3.4 WHEN 用戶發送或接收加密訊息 THEN 系統 SHALL CONTINUE TO 使用現有的 E2EE 加密/解密流程

3.5 WHEN 應用在其他平台（Android、Web）運行 THEN 系統 SHALL CONTINUE TO 保持相同的金鑰管理行為
