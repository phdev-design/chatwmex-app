# 需求文件：已連結裝置 (Linked Devices)

## 簡介

本功能為 ChatWMEX 聊天應用新增「已連結裝置」管理機制，讓使用者可透過手機掃描網頁版 QR Code 來連結網頁端裝置，實現手機與網頁端的即時訊息同步。此功能建立在現有的 E2EE（端對端加密）架構之上，需確保連結裝置間的加密金鑰安全傳遞，維持訊息的端對端加密保護。

## 詞彙表

- **主裝置 (Primary_Device)**：使用者的手機端 Flutter 應用，擁有完整的 E2EE 私鑰，為唯一可授權連結的裝置
- **已連結裝置 (Linked_Device)**：透過 QR Code 掃描授權連結的網頁端裝置，從主裝置接收加密會話金鑰
- **裝置管理頁面 (Device_Management_Page)**：設定頁面中的「已連結裝置」子頁面，顯示所有已連結裝置並提供管理功能
- **QR_Token**：後端產生的一次性驗證令牌，嵌入 QR Code 中供手機掃描確認
- **連結會話 (Link_Session)**：主裝置與已連結裝置之間建立的加密通訊會話
- **會話金鑰 (Session_Key)**：主裝置為已連結裝置產生的對稱加密金鑰，用於已連結裝置解密訊息
- **後端伺服器 (Backend_Server)**：Go 語言後端服務，負責 QR Token 管理、裝置註冊與 WebSocket 訊息轉發
- **網頁端 (Web_Client)**：React 前端應用，作為已連結裝置運行於瀏覽器中
- **設定頁面 (Settings_Page)**：Flutter 應用中的設定主頁面，包含各項設定入口

## 需求

### 需求 1：設定頁面新增已連結裝置入口

**使用者故事：** 身為使用者，我希望在設定頁面中看到「已連結裝置」選項，以便管理我的連結裝置。

#### 驗收條件

1. THE Settings_Page SHALL 在「一般設定」區塊中顯示「已連結裝置 (Linked Devices)」選項，位於「分類名單 (Room Labels)」之後
2. WHEN 使用者點擊「已連結裝置」選項，THE Settings_Page SHALL 導航至 Device_Management_Page
3. THE Settings_Page SHALL 在「已連結裝置」選項旁顯示目前已連結裝置的數量徽章（當數量大於 0 時）

### 需求 2：裝置管理頁面

**使用者故事：** 身為使用者，我希望有一個專屬頁面來查看和管理所有已連結的裝置，以便掌握帳號的裝置使用狀態。

#### 驗收條件

1. THE Device_Management_Page SHALL 顯示所有已連結裝置的清單，每個項目包含裝置名稱、平台類型（Web）、最後活躍時間
2. THE Device_Management_Page SHALL 在頁面頂部顯示「連結新裝置」按鈕
3. WHEN 使用者點擊「連結新裝置」按鈕，THE Device_Management_Page SHALL 開啟 QR Code 掃描器
4. WHEN 使用者對某個已連結裝置執行左滑或長按操作，THE Device_Management_Page SHALL 顯示「取消連結」選項
5. WHILE 沒有任何已連結裝置，THE Device_Management_Page SHALL 顯示空狀態提示畫面，包含說明文字與「連結新裝置」引導按鈕
6. THE Device_Management_Page SHALL 限制已連結裝置數量上限為 4 台
7. WHEN 已連結裝置數量達到上限 4 台，THE Device_Management_Page SHALL 停用「連結新裝置」按鈕並顯示已達上限提示

### 需求 3：QR Code 掃描連結流程

**使用者故事：** 身為使用者，我希望透過手機掃描網頁版的 QR Code 來快速連結裝置，以便在網頁端使用聊天功能。

#### 驗收條件

1. WHEN Web_Client 開啟登入頁面，THE Backend_Server SHALL 產生一個有效期為 3 分鐘的 QR_Token 並回傳給 Web_Client
2. WHEN Web_Client 收到 QR_Token，THE Web_Client SHALL 將 QR_Token 編碼為 QR Code 並顯示於登入頁面
3. WHEN Primary_Device 掃描 QR Code 並解析出 QR_Token，THE Primary_Device SHALL 顯示連結確認對話框，包含「確認連結」與「取消」按鈕
4. WHEN 使用者在 Primary_Device 上點擊「確認連結」，THE Primary_Device SHALL 將 QR_Token 與使用者身份資訊傳送至 Backend_Server 進行確認
5. WHEN Backend_Server 收到 QR_Token 確認請求，THE Backend_Server SHALL 驗證 QR_Token 有效性、產生 Web JWT Token，並透過 WebSocket 通知 Web_Client 連結成功
6. IF QR_Token 已過期或無效，THEN THE Backend_Server SHALL 回傳錯誤訊息，且 Primary_Device 顯示「QR Code 已過期，請重新掃描」提示
7. IF QR_Token 已被使用過，THEN THE Backend_Server SHALL 回傳錯誤訊息，且 Primary_Device 顯示「此 QR Code 已被使用」提示
8. WHEN QR_Token 有效期剩餘不足 30 秒，THE Web_Client SHALL 自動重新產生新的 QR Code

### 需求 4：已連結裝置註冊與管理

**使用者故事：** 身為使用者，我希望系統能自動記錄已連結的裝置資訊，以便我隨時查看和管理。

#### 驗收條件

1. WHEN 連結流程成功完成，THE Backend_Server SHALL 在裝置資料庫中建立新的 Linked_Device 記錄，包含裝置 ID、使用者 ID、平台類型（web）、連結時間、最後活躍時間
2. WHEN Linked_Device 透過 WebSocket 傳送或接收訊息，THE Backend_Server SHALL 更新該裝置的最後活躍時間
3. WHEN 使用者在 Device_Management_Page 選擇「取消連結」某裝置，THE Backend_Server SHALL 刪除該 Linked_Device 記錄並撤銷其 JWT Token
4. WHEN 某 Linked_Device 被取消連結，THE Backend_Server SHALL 透過 WebSocket 通知該 Web_Client 連結已被撤銷
5. WHEN Web_Client 收到連結撤銷通知，THE Web_Client SHALL 清除本地會話資料並導航至登入頁面
6. IF Linked_Device 連續 30 天未活躍，THEN THE Backend_Server SHALL 自動取消該裝置的連結

### 需求 5：E2EE 金鑰安全傳遞

**使用者故事：** 身為使用者，我希望連結裝置時加密金鑰能安全傳遞，以確保網頁端也能解密訊息且不降低安全性。

#### 驗收條件

1. WHEN 連結流程成功完成，THE Primary_Device SHALL 為 Linked_Device 產生一組專屬的 Session_Key
2. THE Primary_Device SHALL 使用 Linked_Device 的公鑰加密 Session_Key 後，透過 Backend_Server 安全傳遞給 Linked_Device
3. THE Backend_Server SHALL 僅轉發加密後的 Session_Key，不得儲存或解密 Session_Key 的明文
4. WHEN Linked_Device 收到加密的 Session_Key，THE Linked_Device SHALL 使用自身私鑰解密並安全儲存於瀏覽器的安全儲存區
5. IF Session_Key 傳遞過程中發生錯誤，THEN THE Primary_Device SHALL 顯示「金鑰傳遞失敗，請重新連結」提示，並中止連結流程
6. WHEN 使用者取消連結某 Linked_Device，THE Primary_Device SHALL 產生新的 Session_Key 並重新分發給其餘已連結裝置

### 需求 6：訊息即時同步

**使用者故事：** 身為使用者，我希望手機與網頁端的訊息能即時同步，以便在任何裝置上都能看到最新的對話內容。

#### 驗收條件

1. WHEN Primary_Device 發送一則訊息，THE Backend_Server SHALL 同時將該訊息的加密副本轉發給所有已連結的 Linked_Device
2. WHEN 任一 Linked_Device 發送一則訊息，THE Backend_Server SHALL 同時將該訊息的加密副本轉發給 Primary_Device 及其他已連結的 Linked_Device
3. WHILE Linked_Device 處於離線狀態，THE Backend_Server SHALL 暫存未送達的訊息，待 Linked_Device 重新上線後依序送達
4. WHEN Linked_Device 重新上線，THE Backend_Server SHALL 將所有暫存的未送達訊息依時間順序送達至該 Linked_Device
5. THE Backend_Server SHALL 為離線 Linked_Device 暫存訊息的保留期限為 7 天
6. WHEN 使用者在任一裝置上讀取訊息，THE Backend_Server SHALL 將已讀狀態同步至所有已連結裝置

### 需求 7：網頁端 QR Code 登入頁面

**使用者故事：** 身為使用者，我希望網頁版有清楚的 QR Code 登入介面，以便快速完成裝置連結。

#### 驗收條件

1. THE Web_Client SHALL 在未登入狀態下顯示 QR Code 登入頁面，包含 QR Code 圖片、操作說明文字
2. THE Web_Client SHALL 在 QR Code 下方顯示「使用 ChatWMEX 手機版掃描 QR Code 登入」說明文字
3. WHILE 等待手機掃描確認，THE Web_Client SHALL 顯示載入動畫表示等待中
4. WHEN 連結成功，THE Web_Client SHALL 導航至聊天主頁面
5. IF QR_Token 過期且未被掃描，THEN THE Web_Client SHALL 顯示「QR Code 已過期」提示並提供「重新產生」按鈕

### 需求 8：連結裝置安全防護

**使用者故事：** 身為使用者，我希望系統提供安全防護機制，以防止未授權的裝置連結。

#### 驗收條件

1. THE Backend_Server SHALL 確保每個 QR_Token 僅能被使用一次
2. WHEN 同一使用者在 5 分鐘內連續 5 次連結失敗，THE Backend_Server SHALL 暫時封鎖該使用者的連結功能 15 分鐘
3. WHEN 新裝置成功連結，THE Primary_Device SHALL 顯示推播通知告知使用者「新裝置已連結」
4. THE Web_Client SHALL 在每次頁面載入時驗證 JWT Token 有效性，無效時導航至登入頁面
5. WHEN 使用者在 Primary_Device 上登出帳號，THE Backend_Server SHALL 自動取消所有 Linked_Device 的連結
