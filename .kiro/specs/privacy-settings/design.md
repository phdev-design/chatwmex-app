# Design Document: Privacy Settings

## Overview

本設計文件描述如何在現有的 Flutter + Go 聊天應用程式中加入類似 WhatsApp 的全域隱私設定功能。系統已具備 E2EE 加密、群組聊天、推送通知（OneSignal + RabbitMQ）、JWT 認證、MongoDB 持久化與 Redis 在線狀態管理。

本功能新增以下能力：
- 每位使用者可設定誰能看到其最後上線時間、在線狀態、個人頭像
- 可選擇是否顯示已讀回條（DM 層級，群組強制顯示）
- 後端在查詢在線狀態時套用隱私過濾（含互惠原則）
- 推送通知發送前檢查靜音設定（已有 `MuteUntil` 欄位，補上檢查邏輯）
- Flutter 前端新增隱私設定頁面

---

## Architecture

本功能遵循現有的 Clean Architecture 分層：

```
Flutter App (Riverpod)
    │
    ▼
GET/PUT /api/v1/privacy-settings   (新增)
POST /api/v1/online/presence       (修改：加入隱私過濾)
    │
    ▼ HTTP + JWT Auth Middleware
PrivacySettingHandler              (新增 delivery/http layer)
OnlineHandler                      (修改：注入 PrivacySettingUsecase + FriendRepository)
    │
    ▼
PrivacySettingUsecase              (新增 usecase layer)
PresenceUsecase (邏輯移入 usecase)  (新增，從 handler 抽出)
    │
    ▼
UserPrivacyRepository              (新增 domain interface)
MongoPrivacySettingRepository      (新增 mongo_repo implementation)
FriendRepository.IsFriend()        (已存在，複用)
ChatSettingRepository.GetSetting() (已存在，複用)
    │
    ▼
MongoDB: privacy_settings collection  (新增)
Redis: online presence                (已存在)
```

### 關鍵設計決策

1. **PrivacySetting 獨立 collection**：不合併進 `users` collection，保持單一職責，且未來可獨立擴展。
2. **Presence 過濾在 usecase 層**：將過濾邏輯從 handler 移至 usecase，便於測試與複用（WebSocket hub 也可呼叫）。
3. **互惠原則在 usecase 層集中處理**：避免分散在多處，確保一致性。
4. **推送通知靜音檢查在 message_usecase**：`buildPushNotificationMessage` 已有 `settingUsecase`，直接在此加入 `MuteUntil` 檢查，不需改動 RabbitMQ consumer。
5. **已讀回條過濾在 WebSocket handler**：`MarkMessagesAsReadBy` 觸發點在 WebSocket，在此注入 `PrivacySettingUsecase` 進行過濾。

---

## Components and Interfaces

### 後端新增 Domain 介面

```go
// backend/internal/domain/privacy_setting.go

package domain

import "context"

// PrivacyLevel 定義隱私等級
type PrivacyLevel int

const (
    PrivacyLevelEveryone  PrivacyLevel = 0 // 所有人
    PrivacyLevelContacts  PrivacyLevel = 1 // 我的聯絡人
    PrivacyLevelNobody    PrivacyLevel = 2 // 沒人
)

// PrivacySetting 儲存單一使用者的全域隱私偏好
type PrivacySetting struct {
    UserID               string       `json:"user_id"`
    LastSeenPrivacy      PrivacyLevel `json:"last_seen_privacy"`
    OnlineStatusPrivacy  PrivacyLevel `json:"online_status_privacy"`
    ProfilePhotoPrivacy  PrivacyLevel `json:"profile_photo_privacy"`
    ReadReceiptsEnabled  bool         `json:"read_receipts_enabled"`
}

// UserPrivacyRepository 定義隱私設定的持久化介面
type UserPrivacyRepository interface {
    GetPrivacySetting(ctx context.Context, userID string) (*PrivacySetting, error)
    UpsertPrivacySetting(ctx context.Context, setting *PrivacySetting) error
}

// PrivacySettingUsecase 定義隱私設定的業務邏輯介面
type PrivacySettingUsecase interface {
    GetPrivacySetting(ctx context.Context, userID string) (*PrivacySetting, error)
    UpdatePrivacySetting(ctx context.Context, userID string, req UpdatePrivacySettingRequest) (*PrivacySetting, error)
    // FilterPresence 套用隱私過濾，回傳過濾後的 PresenceInfo map
    FilterPresence(ctx context.Context, viewerID string, subjects map[string]*PresenceInfo) (map[string]*PresenceInfo, error)
    // ShouldShowReadReceipt 判斷在 DM 中是否應顯示已讀回條
    ShouldShowReadReceipt(ctx context.Context, readerID, senderID string, isGroup bool) (bool, error)
}

// UpdatePrivacySettingRequest 支援部分欄位更新（pointer = nil 表示不更新）
type UpdatePrivacySettingRequest struct {
    LastSeenPrivacy     *PrivacyLevel `json:"last_seen_privacy"`
    OnlineStatusPrivacy *PrivacyLevel `json:"online_status_privacy"`
    ProfilePhotoPrivacy *PrivacyLevel `json:"profile_photo_privacy"`
    ReadReceiptsEnabled *bool         `json:"read_receipts_enabled"`
}
```

### 後端修改 ChatSetting Domain

```go
// 在 domain/chat_setting.go 的 ChatSetting struct 新增欄位
type ChatSetting struct {
    // ... 現有欄位 ...
    ReadReceiptsEnabled *bool `json:"read_receipts_enabled"` // nil = 使用全域設定
}
```

### PrivacySettingUsecase 實作重點

```go
// FilterPresence 核心邏輯（pseudocode）
func (u *privacySettingUsecase) FilterPresence(ctx, viewerID, subjects) {
    viewerSetting := getOrDefault(viewerID)
    result := map[string]*PresenceInfo{}

    for subjectID, presence := range subjects {
        subjectSetting := getOrDefault(subjectID)
        filtered := &PresenceInfo{}

        // --- is_online 過濾 ---
        // 連動規則：OnlineStatusPrivacy=Contacts 且 LastSeenPrivacy=Nobody → 強制 false
        effectiveOnlinePrivacy := subjectSetting.OnlineStatusPrivacy
        if effectiveOnlinePrivacy == PrivacyLevelContacts &&
            subjectSetting.LastSeenPrivacy == PrivacyLevelNobody {
            effectiveOnlinePrivacy = PrivacyLevelNobody
        }

        switch effectiveOnlinePrivacy {
        case PrivacyLevelEveryone:
            // 互惠原則：若 viewer 自己也隱藏 online，則看不到別人的
            if viewerSetting.OnlineStatusPrivacy == PrivacyLevelNobody {
                filtered.IsOnline = false
            } else {
                filtered.IsOnline = presence.IsOnline
            }
        case PrivacyLevelContacts:
            isFriend := friendRepo.IsFriend(ctx, subjectID, viewerID)
            if isFriend && viewerSetting.OnlineStatusPrivacy != PrivacyLevelNobody {
                filtered.IsOnline = presence.IsOnline
            }
        case PrivacyLevelNobody:
            filtered.IsOnline = false
        }

        // --- last_seen 過濾（同上邏輯，互惠原則用 LastSeenPrivacy）---
        // ...

        result[subjectID] = filtered
    }
    return result
}
```

### HTTP Handler 新增

```go
// PrivacySettingHandler 處理 GET/PUT /api/v1/privacy-settings
type PrivacySettingHandler struct {
    usecase domain.PrivacySettingUsecase
}
```

### Flutter 新增 Repository

```dart
// app/lib/features/privacy/repositories/privacy_setting_repository.dart
class PrivacySettingRepository {
    Future<PrivacySetting> getPrivacySetting() async { ... }
    Future<PrivacySetting> updatePrivacySetting(UpdatePrivacySettingRequest req) async { ... }
}
```

---

## Data Models

### 後端：MongoDB `privacy_settings` Collection

```
Collection: privacy_settings
Index: { user_id: 1 } unique

Document schema:
{
  _id:                   ObjectID,
  user_id:               string,      // 使用者 ID（唯一）
  last_seen_privacy:     int,         // 0=Everyone, 1=Contacts, 2=Nobody
  online_status_privacy: int,         // 0=Everyone, 1=Contacts, 2=Nobody
  profile_photo_privacy: int,         // 0=Everyone, 1=Contacts, 2=Nobody
  read_receipts_enabled: bool,        // true=顯示已讀回條
  updated_at:            time.Time
}

Default values (when no record exists):
{
  last_seen_privacy:     0,
  online_status_privacy: 0,
  profile_photo_privacy: 0,
  read_receipts_enabled: true
}
```

### 後端：ChatSetting Collection 新增欄位

```
Collection: chat_settings（已存在）
新增欄位:
  read_receipts_enabled: *bool   // nil=使用全域設定, true/false=覆蓋全域
```

### Flutter：PrivacySetting Model

```dart
// app/lib/models/privacy_setting.dart
class PrivacySetting {
  final int lastSeenPrivacy;      // 0=Everyone, 1=Contacts, 2=Nobody
  final int onlineStatusPrivacy;
  final int profilePhotoPrivacy;
  final bool readReceiptsEnabled;

  const PrivacySetting({
    this.lastSeenPrivacy = 0,
    this.onlineStatusPrivacy = 0,
    this.profilePhotoPrivacy = 0,
    this.readReceiptsEnabled = true,
  });

  factory PrivacySetting.fromJson(Map<String, dynamic> json) { ... }
  Map<String, dynamic> toJson() { ... }
}
```

### Flutter：ChatSetting Model 新增欄位

```dart
class ChatSetting {
  // ... 現有欄位 ...
  final bool? readReceiptsEnabled; // null=使用全域設定
}
```

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Invalid PrivacyLevel Rejection

*For any* integer value submitted as a `PrivacyLevel` that is not in {0, 1, 2}, the `UpdatePrivacySetting` usecase SHALL return an error, and the stored setting SHALL remain unchanged.

**Validates: Requirements 1.2, 1.5**

---

### Property 2: Privacy Settings Update Round-Trip

*For any* valid `UpdatePrivacySettingRequest` containing all four fields with valid values, calling `UpdatePrivacySetting` followed by `GetPrivacySetting` for the same user SHALL return a `PrivacySetting` whose fields exactly match the submitted values.

**Validates: Requirements 1.4, 6.2**

---

### Property 3: Partial Update Preserves Unspecified Fields

*For any* `UpdatePrivacySettingRequest` that specifies only a subset of fields (one or more fields set to nil/omitted), calling `UpdatePrivacySetting` SHALL update only the specified fields, and all unspecified fields SHALL retain their previous values.

**Validates: Requirements 6.4**

---

### Property 4: Presence Filtering Respects Subject's Privacy Level

*For any* subject user with a given `LastSeenPrivacy` or `OnlineStatusPrivacy` level, and *for any* viewer user, the `FilterPresence` function SHALL return `last_seen = null` and/or `is_online = false` exactly when the subject's privacy level and the viewer's relationship (friend or not) dictate it, according to the following rules:
- Level 0 (Everyone): viewer always sees real value
- Level 1 (Contacts): viewer sees real value only if they are a friend of the subject
- Level 2 (Nobody): viewer always sees null/false

**Validates: Requirements 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9**

---

### Property 5: Reciprocity Rule for Presence

*For any* viewer whose own `LastSeenPrivacy` is `Nobody` (2), `FilterPresence` SHALL return `last_seen = null` for ALL subjects, regardless of each subject's own privacy setting. Similarly, *for any* viewer whose own `OnlineStatusPrivacy` is `Nobody` (2), `FilterPresence` SHALL return `is_online = false` for ALL subjects.

**Validates: Requirements 2.10, 2.11**

---

### Property 6: Online/LastSeen Linkage Rule

*For any* subject whose `OnlineStatusPrivacy` is `Contacts` (1) AND `LastSeenPrivacy` is `Nobody` (2), `FilterPresence` SHALL return `is_online = false` for ALL viewers, even if Redis reports the subject as currently online.

**Validates: Requirements 3.1**

---

### Property 7: Mute Check Suppresses Notifications

*For any* `ChatSetting` where `MuteUntil` is either `-1` (permanent) or a Unix timestamp strictly greater than the current time, the notification mute check function SHALL return `true` (is muted), and the push notification SHALL be skipped. *For any* `ChatSetting` where `MuteUntil` is `nil` or a timestamp less than or equal to the current time, the function SHALL return `false` (not muted), and the push notification SHALL proceed.

**Validates: Requirements 4.2, 4.3, 4.4**

---

### Property 8: DM Read Receipt Mutual Suppression

*For any* DM conversation between user A and user B, if either A's `ReadReceiptsEnabled` is `false` OR B's `ReadReceiptsEnabled` is `false`, then `ShouldShowReadReceipt` SHALL return `false` for both directions (A reading B's messages and B reading A's messages).

**Validates: Requirements 5.1, 5.2**

---

### Property 9: Group Read Receipts Always Shown

*For any* group message and *for any* group member, `ShouldShowReadReceipt` SHALL return `true` regardless of any individual member's `ReadReceiptsEnabled` setting.

**Validates: Requirements 5.3**

---

### Property 10: Unauthenticated Requests Rejected

*For any* request to `GET /api/v1/privacy-settings` or `PUT /api/v1/privacy-settings` that does not carry a valid JWT Bearer token, the server SHALL respond with HTTP 401.

**Validates: Requirements 6.3**

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| `GetPrivacySetting` — no record in DB | 回傳預設值（不報錯），不寫入 DB（lazy default） |
| `UpsertPrivacySetting` — DB error | 回傳 HTTP 500，附帶錯誤訊息 |
| `FilterPresence` — `GetPrivacySetting` fails for a subject | 對該 subject 套用最嚴格預設（`last_seen=null`, `is_online=false`），繼續處理其他 subjects |
| `FilterPresence` — `IsFriend` fails | 視為非好友（保守策略），繼續處理 |
| Mute check — `GetSetting` DB error | Fail-open：記錄 error log，繼續發送通知（Requirements 4.5） |
| `ShouldShowReadReceipt` — `GetPrivacySetting` fails | Fail-open：回傳 `true`（顯示已讀），避免功能中斷 |
| Invalid `PrivacyLevel` value in PUT body | HTTP 400，附帶描述性錯誤訊息 |
| Missing/invalid JWT | HTTP 401 |

---

## Testing Strategy

### Dual Testing Approach

本功能採用單元測試與屬性測試並行的策略：
- **單元測試**：驗證具體範例、邊界條件、錯誤處理路徑
- **屬性測試**：驗證對所有輸入組合都成立的普遍性規則

### Unit Tests（具體範例與邊界條件）

後端（Go，使用 `testing` + `testify`）：
- `TestGetPrivacySetting_DefaultValues`：新使用者首次查詢回傳預設值（Req 1.3）
- `TestGetPrivacySetting_ExistingRecord`：已有記錄時回傳正確值
- `TestPrivacySettingHandler_GET_Unauthorized`：無 JWT 回傳 401（Req 6.3）
- `TestPrivacySettingHandler_GET_Success`：有效 JWT 回傳 200 + PrivacySetting
- `TestPrivacySettingHandler_PUT_Success`：更新後回傳更新值
- `TestFilterPresence_MuteUntilNegativeOne`：永久靜音邊界（Req 4.3）
- `TestFilterPresence_MuteUntilExpired`：靜音已過期，正常發送（Req 4.4）
- `TestNotificationConsumer_DBError_FailOpen`：DB 錯誤時 fail-open（Req 4.5）
- `TestShouldShowReadReceipt_GroupAlwaysTrue`：群組強制顯示（Req 5.3）
- `TestChatSetting_ReadReceiptsEnabled_Field`：ChatSetting 包含新欄位（Req 5.4）
- `TestPresenceEndpoint_ResponseFormatUnchanged`：API 回應格式維持 `map[userID]*PresenceInfo`（Req 6.5）

前端（Flutter，使用 `flutter_test`）：
- `testPrivacySettingFromJson`：JSON 反序列化正確
- `testPrivacySettingToJson`：序列化後再反序列化等值（round-trip）
- `testPrivacySettingScreen_displaysCurrentValues`：設定頁面顯示目前值
- `testPrivacySettingScreen_updateCallsRepository`：點擊選項觸發 API 呼叫

### Property-Based Tests（屬性測試）

後端使用 [`pgregory.net/rapid`](https://github.com/pgregory/rapid) 作為 PBT 函式庫（與現有 codebase 一致）。每個屬性測試最少執行 **100 次**迭代。

每個測試以 tag 標記對應的設計屬性：
`// Feature: privacy-settings, Property N: <property_text>`

```go
// backend/internal/usecase/privacy_setting_pbt_test.go

// Feature: privacy-settings, Property 1: Invalid PrivacyLevel Rejection
func TestProperty1_InvalidPrivacyLevelRejected(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        invalidLevel := rapid.Int().Filter(func(v int) bool {
            return v < 0 || v > 2
        }).Draw(t, "invalidLevel")
        req := domain.UpdatePrivacySettingRequest{
            LastSeenPrivacy: (*domain.PrivacyLevel)(&invalidLevel),
        }
        _, err := usecase.UpdatePrivacySetting(ctx, "user1", req)
        assert.Error(t, err)
    })
}

// Feature: privacy-settings, Property 2: Privacy Settings Update Round-Trip
func TestProperty2_UpdateRoundTrip(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        level := rapid.SampledFrom([]domain.PrivacyLevel{0, 1, 2}).Draw(t, "level")
        enabled := rapid.Bool().Draw(t, "enabled")
        req := domain.UpdatePrivacySettingRequest{
            LastSeenPrivacy:     &level,
            OnlineStatusPrivacy: &level,
            ProfilePhotoPrivacy: &level,
            ReadReceiptsEnabled: &enabled,
        }
        updated, _ := usecase.UpdatePrivacySetting(ctx, userID, req)
        fetched, _ := usecase.GetPrivacySetting(ctx, userID)
        assert.Equal(t, updated, fetched)
    })
}

// Feature: privacy-settings, Property 3: Partial Update Preserves Unspecified Fields
func TestProperty3_PartialUpdatePreservesFields(t *testing.T) { ... }

// Feature: privacy-settings, Property 4: Presence Filtering Respects Privacy Level
func TestProperty4_PresenceFilteringByPrivacyLevel(t *testing.T) { ... }

// Feature: privacy-settings, Property 5: Reciprocity Rule for Presence
func TestProperty5_ReciprocityRule(t *testing.T) { ... }

// Feature: privacy-settings, Property 6: Online/LastSeen Linkage Rule
func TestProperty6_OnlineLastSeenLinkage(t *testing.T) { ... }

// Feature: privacy-settings, Property 7: Mute Check Suppresses Notifications
func TestProperty7_MuteCheckSuppressesNotifications(t *testing.T) {
    rapid.Check(t, func(t *rapid.T) {
        now := time.Now().Unix()
        // Generate future timestamps (muted) and past timestamps (not muted)
        muteUntil := rapid.Int64Range(now-86400, now+86400).Draw(t, "muteUntil")
        setting := &domain.ChatSetting{MuteUntil: &muteUntil}
        isMuted := isChatMuted(setting)
        assert.Equal(t, muteUntil > now, isMuted)
    })
}

// Feature: privacy-settings, Property 8: DM Read Receipt Mutual Suppression
func TestProperty8_DMReadReceiptMutualSuppression(t *testing.T) { ... }

// Feature: privacy-settings, Property 9: Group Read Receipts Always Shown
func TestProperty9_GroupReadReceiptsAlwaysShown(t *testing.T) { ... }

// Feature: privacy-settings, Property 10: Unauthenticated Requests Rejected
func TestProperty10_UnauthenticatedRequestsRejected(t *testing.T) { ... }
```

### 測試覆蓋目標

| 層級 | 目標覆蓋率 |
|---|---|
| `domain/privacy_setting.go` | 100%（純資料結構） |
| `usecase/privacy_setting_usecase.go` | ≥ 90% |
| `delivery/http/privacy_setting_handler.go` | ≥ 85% |
| `repository/mongo_repo/privacy_setting_repository.go` | ≥ 80% |
| Flutter `PrivacySetting` model | 100% |
| Flutter `PrivacySettingRepository` | ≥ 80% |
