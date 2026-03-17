# Requirements Document

## Introduction

本功能為現有的 Flutter + Go 聊天應用程式（已具備 E2EE 加密、群組聊天、推送通知）加入類似 WhatsApp 的全域隱私設定。使用者可控制誰能看到自己的最後上線時間、在線狀態、個人頭像，以及是否顯示已讀回條。後端需在查詢在線狀態時套用隱私過濾邏輯（含互惠原則），並在發送推送通知前檢查靜音設定。

## Glossary

- **Privacy_Setting_Service**：負責管理與查詢全域隱私設定的後端服務
- **Presence_Service**：負責查詢使用者在線狀態與最後上線時間的後端服務
- **Notification_Service**：負責發送推送通知的後端服務
- **PrivacySetting**：儲存單一使用者全域隱私偏好的資料結構
- **PresenceInfo**：包含 `is_online` 與 `last_seen` 的在線資訊結構（已存在於 `domain/online.go`）
- **ChatSetting**：儲存單一聊天室行為設定的資料結構（已存在於 `domain/chat_setting.go`）
- **PrivacyLevel**：隱私等級列舉，0 = 所有人（Everyone）、1 = 我的聯絡人（My Contacts）、2 = 沒人（Nobody）
- **Viewer**：發起查詢的使用者（User A）
- **Subject**：被查詢狀態的使用者（User B）
- **Reciprocity_Rule**：互惠原則，若 Viewer 自己也隱藏了同一項資訊，則即使 Subject 公開，也對 Viewer 隱藏該資訊
- **Read_Receipt**：已讀回條，即訊息已被對方閱讀的藍色勾勾標記
- **MuteUntil**：ChatSetting 中的靜音截止時間戳（Unix timestamp），nil 表示不靜音，-1 表示永久靜音

---

## Requirements

### Requirement 1：全域隱私設定的領域模型

**User Story:** 身為使用者，我希望能設定誰可以看到我的最後上線時間、在線狀態、個人頭像，以及是否顯示已讀回條，以便保護我的個人隱私。

#### Acceptance Criteria

1. THE Privacy_Setting_Service SHALL 為每位使用者維護一筆 PrivacySetting 記錄，包含以下欄位：`LastSeenPrivacy`（PrivacyLevel）、`OnlineStatusPrivacy`（PrivacyLevel）、`ProfilePhotoPrivacy`（PrivacyLevel）、`ReadReceiptsEnabled`（布林值）。
2. THE Privacy_Setting_Service SHALL 以 PrivacyLevel 列舉表示隱私等級：0 = 所有人、1 = 我的聯絡人、2 = 沒人。
3. WHEN 使用者首次查詢自身 PrivacySetting 且尚無記錄時，THE Privacy_Setting_Service SHALL 回傳預設值：`LastSeenPrivacy = 0`（所有人）、`OnlineStatusPrivacy = 0`（所有人）、`ProfilePhotoPrivacy = 0`（所有人）、`ReadReceiptsEnabled = true`。
4. WHEN 使用者提交合法的 PrivacySetting 更新請求時，THE Privacy_Setting_Service SHALL 將更新後的設定持久化至資料庫，並回傳更新後的完整 PrivacySetting 物件。
5. IF 使用者提交的 PrivacyLevel 值不在 0、1、2 範圍內，THEN THE Privacy_Setting_Service SHALL 回傳 HTTP 400 錯誤並附帶描述性錯誤訊息。

---

### Requirement 2：在線狀態與最後上線時間的隱私過濾

**User Story:** 身為使用者，我希望系統在回傳他人的在線狀態與最後上線時間前，先套用對方的隱私設定，以便尊重每位使用者的隱私選擇。

#### Acceptance Criteria

1. WHEN Viewer 查詢 Subject 的 PresenceInfo 時，THE Presence_Service SHALL 先讀取 Subject 的 PrivacySetting，再決定回傳的 `is_online` 與 `last_seen` 值。
2. WHEN Subject 的 `LastSeenPrivacy` 為 0（所有人）時，THE Presence_Service SHALL 回傳 Subject 的真實 `last_seen` 時間給 Viewer。
3. WHEN Subject 的 `LastSeenPrivacy` 為 1（我的聯絡人）且 Viewer 在 Subject 的好友名單中時，THE Presence_Service SHALL 回傳 Subject 的真實 `last_seen` 時間給 Viewer。
4. WHEN Subject 的 `LastSeenPrivacy` 為 1（我的聯絡人）且 Viewer 不在 Subject 的好友名單中時，THE Presence_Service SHALL 回傳 `last_seen = null` 給 Viewer。
5. WHEN Subject 的 `LastSeenPrivacy` 為 2（沒人）時，THE Presence_Service SHALL 回傳 `last_seen = null` 給 Viewer，無論 Viewer 是否為 Subject 的聯絡人。
6. WHEN Subject 的 `OnlineStatusPrivacy` 為 0（所有人）時，THE Presence_Service SHALL 回傳 Subject 的真實 `is_online` 狀態給 Viewer。
7. WHEN Subject 的 `OnlineStatusPrivacy` 為 1（我的聯絡人）且 Viewer 在 Subject 的好友名單中時，THE Presence_Service SHALL 回傳 Subject 的真實 `is_online` 狀態給 Viewer。
8. WHEN Subject 的 `OnlineStatusPrivacy` 為 1（我的聯絡人）且 Viewer 不在 Subject 的好友名單中時，THE Presence_Service SHALL 回傳 `is_online = false` 給 Viewer。
9. WHEN Subject 的 `OnlineStatusPrivacy` 為 2（沒人）時，THE Presence_Service SHALL 回傳 `is_online = false` 給 Viewer，無論 Viewer 是否為 Subject 的聯絡人。
10. WHEN Viewer 自身的 `LastSeenPrivacy` 為 2（沒人）時，THE Presence_Service SHALL 對 Viewer 隱藏所有其他使用者的 `last_seen`，回傳 `last_seen = null`（互惠原則）。
11. WHEN Viewer 自身的 `OnlineStatusPrivacy` 為 2（沒人）時，THE Presence_Service SHALL 對 Viewer 隱藏所有其他使用者的 `is_online`，回傳 `is_online = false`（互惠原則）。

---

### Requirement 3：在線狀態與最後上線時間的連動規則

**User Story:** 身為使用者，我希望當我將「在線狀態」設為與「最後上線時間」相同，且「最後上線時間」設為「沒人」時，系統不會洩漏我的在線狀態，以便確保設定的一致性。

#### Acceptance Criteria

1. WHEN Subject 的 `OnlineStatusPrivacy` 為 1（我的聯絡人）且 Subject 的 `LastSeenPrivacy` 為 2（沒人）時，THE Presence_Service SHALL 對所有 Viewer 回傳 `is_online = false`，即使 Redis 中 Subject 的在線狀態為 true。
2. WHEN Subject 的 `OnlineStatusPrivacy` 為 0（所有人）且 Subject 的 `LastSeenPrivacy` 為 2（沒人）時，THE Presence_Service SHALL 仍依照 `OnlineStatusPrivacy = 0` 的規則回傳真實 `is_online` 狀態（在線狀態設定優先）。

---

### Requirement 4：推送通知的靜音檢查

**User Story:** 身為使用者，我希望在靜音某個聊天室後，系統不會在靜音期間發送該聊天室的推送通知，以便避免打擾。

#### Acceptance Criteria

1. WHEN Notification_Service 準備向使用者發送推送通知時，THE Notification_Service SHALL 先查詢該使用者對應聊天室的 ChatSetting。
2. WHEN ChatSetting 的 `MuteUntil` 不為 nil 且 `MuteUntil` 的值大於目前 Unix 時間戳時，THE Notification_Service SHALL 跳過該次推送通知的發送。
3. WHEN ChatSetting 的 `MuteUntil` 為 -1（永久靜音）時，THE Notification_Service SHALL 跳過該次推送通知的發送。
4. WHEN ChatSetting 的 `MuteUntil` 為 nil，或 `MuteUntil` 的值小於或等於目前 Unix 時間戳時，THE Notification_Service SHALL 正常發送推送通知。
5. IF 查詢 ChatSetting 時發生資料庫錯誤，THEN THE Notification_Service SHALL 記錄錯誤日誌並繼續發送推送通知（fail-open 策略，避免通知遺失）。

---

### Requirement 5：已讀回條的隱私控制

**User Story:** 身為使用者，我希望能選擇關閉已讀回條，讓對方看不到我已讀訊息的藍色勾勾，以便保護我的閱讀隱私。

#### Acceptance Criteria

1. WHEN 使用者在個人對話（DM）中讀取訊息，且 Viewer 的 `ReadReceiptsEnabled` 為 false 時，THE Privacy_Setting_Service SHALL 不向 Subject 回報 Viewer 的已讀狀態。
2. WHEN 使用者在個人對話（DM）中讀取訊息，且 Subject 的 `ReadReceiptsEnabled` 為 false 時，THE Privacy_Setting_Service SHALL 不向 Viewer 回報 Subject 的已讀狀態（互惠原則：雙方都看不到藍色勾勾）。
3. WHEN 使用者在群組對話中讀取訊息時，THE Privacy_Setting_Service SHALL 忽略個人的 `ReadReceiptsEnabled` 設定，強制讓訊息發送者看到群組成員的已讀狀態。
4. THE ChatSetting SHALL 包含 `ReadReceiptsEnabled` 布林欄位，供前端在個別聊天室層級查詢已讀回條的顯示狀態。

---

### Requirement 6：隱私設定的 API 端點

**User Story:** 身為使用者，我希望能透過 API 查詢與更新自己的隱私設定，以便前端 Flutter 應用程式能正確顯示與儲存設定。

#### Acceptance Criteria

1. THE Privacy_Setting_Service SHALL 提供 `GET /api/v1/privacy-settings` 端點，讓已驗證的使用者查詢自身的 PrivacySetting。
2. THE Privacy_Setting_Service SHALL 提供 `PUT /api/v1/privacy-settings` 端點，讓已驗證的使用者更新自身的 PrivacySetting。
3. WHEN 未攜帶有效 JWT token 的請求存取隱私設定端點時，THE Privacy_Setting_Service SHALL 回傳 HTTP 401 錯誤。
4. WHEN 使用者透過 `PUT /api/v1/privacy-settings` 提交部分欄位更新時，THE Privacy_Setting_Service SHALL 僅更新請求中包含的欄位，保留其餘欄位的現有值。
5. THE Presence_Service 的 `POST /api/v1/online/presence` 端點 SHALL 在回傳 PresenceInfo 前套用 Requirement 2 與 Requirement 3 所定義的隱私過濾邏輯，且 API 回應格式維持不變（`map[userID]*PresenceInfo`）。
