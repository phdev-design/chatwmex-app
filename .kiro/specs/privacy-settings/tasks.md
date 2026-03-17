# Implementation Plan: Privacy Settings

## Overview

Implement WhatsApp-style global privacy settings across the Go backend (Clean Architecture) and Flutter frontend (Riverpod). The backend adds a new `privacy_settings` MongoDB collection, a `PrivacySettingUsecase` with presence filtering and read receipt logic, a new HTTP handler, and modifications to the online presence handler, push notification usecase, and WebSocket read receipt flow. The Flutter frontend adds a `PrivacySetting` model, repository, and settings UI screen.

## Tasks

- [x] 1. Backend domain model and interfaces
  - Create `backend/internal/domain/privacy_setting.go` with `PrivacyLevel` enum (0/1/2), `PrivacySetting` struct, `UserPrivacyRepository` interface, `PrivacySettingUsecase` interface, and `UpdatePrivacySettingRequest` struct
  - Add `ReadReceiptsEnabled *bool` field to `ChatSetting` struct in `backend/internal/domain/chat_setting.go`
  - _Requirements: 1.1, 1.2, 5.4_

- [x] 2. MongoDB repository for privacy settings
  - Create `backend/internal/repository/mongo_repo/privacy_setting_repository.go` implementing `UserPrivacyRepository`
  - Implement `GetPrivacySetting`: query `privacy_settings` collection by `user_id`; return default values (all 0, `read_receipts_enabled=true`) when no record found (lazy default, no DB write)
  - Implement `UpsertPrivacySetting`: upsert by `user_id` with `updated_at` timestamp
  - Create unique index on `user_id` field
  - _Requirements: 1.3, 1.4, 6.2_

- [x] 3. PrivacySettingUsecase implementation
  - Create `backend/internal/usecase/privacy_setting_usecase.go` implementing `PrivacySettingUsecase`
  - Implement `GetPrivacySetting`: delegate to repository, return defaults when no record
  - Implement `UpdatePrivacySetting`: validate all `PrivacyLevel` values are in {0,1,2}; return HTTP 400 error for invalid values; upsert only non-nil fields (partial update)
  - Implement `FilterPresence`: apply per-subject privacy filtering with online/last_seen linkage rule (OnlineStatusPrivacy=Contacts + LastSeenPrivacy=Nobody → force is_online=false); apply reciprocity rule for viewer; on `GetPrivacySetting` error for a subject, apply strictest defaults; on `IsFriend` error, treat as non-friend
  - Implement `ShouldShowReadReceipt`: return `true` always for group; for DM, return `true` only if both reader and sender have `ReadReceiptsEnabled=true`; fail-open on DB error
  - _Requirements: 1.3, 1.4, 1.5, 2.1–2.11, 3.1, 3.2, 5.1, 5.2, 5.3, 6.4_

  - [x] 3.1 Write property test: Property 1 — Invalid PrivacyLevel Rejection
    - **Property 1: Invalid PrivacyLevel Rejection**
    - Use `rapid.Int().Filter(v < 0 || v > 2)` to generate invalid levels; assert `UpdatePrivacySetting` returns error and stored setting is unchanged
    - **Validates: Requirements 1.2, 1.5**

  - [x] 3.2 Write property test: Property 2 — Privacy Settings Update Round-Trip
    - **Property 2: Privacy Settings Update Round-Trip**
    - Generate valid `UpdatePrivacySettingRequest` with all four fields; assert `GetPrivacySetting` after update returns identical values
    - **Validates: Requirements 1.4, 6.2**

  - [x] 3.3 Write property test: Property 3 — Partial Update Preserves Unspecified Fields
    - **Property 3: Partial Update Preserves Unspecified Fields**
    - Generate requests with random subset of fields set (others nil); assert unspecified fields retain prior values
    - **Validates: Requirements 6.4**

  - [x] 3.4 Write property test: Property 4 — Presence Filtering Respects Subject's Privacy Level
    - **Property 4: Presence Filtering Respects Subject's Privacy Level**
    - Generate subject privacy level, viewer friendship status, and real presence values; assert `FilterPresence` output matches expected visibility rules for all combinations
    - **Validates: Requirements 2.2–2.9**

  - [x] 3.5 Write property test: Property 5 — Reciprocity Rule for Presence
    - **Property 5: Reciprocity Rule for Presence**
    - Generate viewer with `LastSeenPrivacy=Nobody` or `OnlineStatusPrivacy=Nobody`; assert `FilterPresence` returns null/false for ALL subjects regardless of subject settings
    - **Validates: Requirements 2.10, 2.11**

  - [x] 3.6 Write property test: Property 6 — Online/LastSeen Linkage Rule
    - **Property 6: Online/LastSeen Linkage Rule**
    - Generate subject with `OnlineStatusPrivacy=Contacts` and `LastSeenPrivacy=Nobody`; assert `FilterPresence` returns `is_online=false` for all viewers even when Redis reports online
    - **Validates: Requirements 3.1**

  - [x] 3.7 Write property test: Property 8 — DM Read Receipt Mutual Suppression
    - **Property 8: DM Read Receipt Mutual Suppression**
    - Generate pairs where at least one party has `ReadReceiptsEnabled=false`; assert `ShouldShowReadReceipt` returns false for both directions
    - **Validates: Requirements 5.1, 5.2**

  - [x] 3.8 Write property test: Property 9 — Group Read Receipts Always Shown
    - **Property 9: Group Read Receipts Always Shown**
    - Generate arbitrary `ReadReceiptsEnabled` values for reader and sender with `isGroup=true`; assert `ShouldShowReadReceipt` always returns true
    - **Validates: Requirements 5.3**

- [x] 4. Checkpoint — Ensure all usecase tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. HTTP handler for privacy settings endpoints
  - Create `backend/internal/delivery/http/privacy_setting_handler.go` with `PrivacySettingHandler` struct
  - Implement `GET /api/v1/privacy-settings`: extract user ID from JWT middleware context; call `GetPrivacySetting`; return 200 + JSON
  - Implement `PUT /api/v1/privacy-settings`: decode `UpdatePrivacySettingRequest` body; call `UpdatePrivacySetting`; return 200 + updated JSON or 400/500 on error
  - Register both routes in the router with JWT auth middleware
  - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [x] 5.1 Write unit tests for privacy setting handler
    - `TestPrivacySettingHandler_GET_Unauthorized`: no JWT → 401
    - `TestPrivacySettingHandler_GET_Success`: valid JWT → 200 + PrivacySetting JSON
    - `TestPrivacySettingHandler_PUT_Success`: valid update body → 200 + updated JSON
    - `TestPrivacySettingHandler_PUT_InvalidLevel`: invalid PrivacyLevel → 400
    - _Requirements: 6.1, 6.2, 6.3_

  - [x] 5.2 Write property test: Property 10 — Unauthenticated Requests Rejected
    - **Property 10: Unauthenticated Requests Rejected**
    - Generate arbitrary request bodies for GET and PUT without valid JWT; assert server responds with HTTP 401 for all inputs
    - **Validates: Requirements 6.3**

- [x] 6. Modify OnlineHandler to apply privacy filtering
  - In `backend/internal/delivery/http/online_handler.go`, inject `PrivacySettingUsecase` and `FriendRepository` into `OnlineHandler`
  - In the `POST /api/v1/online/presence` handler, after fetching raw `PresenceInfo` map from Redis, call `privacyUsecase.FilterPresence(ctx, viewerID, rawPresence)` and return the filtered map
  - Ensure API response format (`map[userID]*PresenceInfo`) remains unchanged
  - _Requirements: 2.1–2.11, 3.1, 3.2, 6.5_

  - [x] 6.1 Write unit test: presence endpoint response format unchanged
    - `TestPresenceEndpoint_ResponseFormatUnchanged`: assert response is still `map[userID]*PresenceInfo` after filtering
    - _Requirements: 6.5_

- [x] 7. Modify push notification usecase to check MuteUntil
  - In `backend/internal/usecase/message_usecase.go`, locate `buildPushNotificationMessage` (or equivalent notification dispatch logic)
  - Before sending push notification, call `chatSettingUsecase.GetSetting(ctx, recipientID, roomID)` and check `MuteUntil`: skip if `MuteUntil == -1` or `*MuteUntil > time.Now().Unix()`
  - On DB error fetching `ChatSetting`, log error and continue sending (fail-open per Req 4.5)
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [x] 7.1 Write property test: Property 7 — Mute Check Suppresses Notifications
    - **Property 7: Mute Check Suppresses Notifications**
    - Use `rapid.Int64Range(now-86400, now+86400)` to generate `MuteUntil` values; assert mute helper returns true iff `muteUntil == -1 || muteUntil > now`
    - **Validates: Requirements 4.2, 4.3, 4.4**

  - [x] 7.2 Write unit tests for mute check edge cases
    - `TestFilterPresence_MuteUntilNegativeOne`: permanent mute → skip notification
    - `TestFilterPresence_MuteUntilExpired`: expired mute → send notification
    - `TestNotificationConsumer_DBError_FailOpen`: DB error → log + send notification
    - _Requirements: 4.3, 4.4, 4.5_

- [x] 8. Modify read receipt logic in WebSocket handler
  - In `backend/internal/delivery/websocket/`, locate the `MarkMessagesAsReadBy` trigger point
  - Inject `PrivacySettingUsecase` into the WebSocket hub or handler
  - Before broadcasting a read receipt event, call `ShouldShowReadReceipt(ctx, readerID, senderID, isGroup)`; skip broadcast if it returns false
  - Group messages (`isGroup=true`) always broadcast read receipts regardless of individual settings
  - _Requirements: 5.1, 5.2, 5.3_

- [x] 9. Checkpoint — Ensure all backend tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Flutter PrivacySetting model
  - Create `app/lib/models/privacy_setting.dart` with `PrivacySetting` class: fields `lastSeenPrivacy`, `onlineStatusPrivacy`, `profilePhotoPrivacy` (int, default 0), `readReceiptsEnabled` (bool, default true)
  - Implement `fromJson` factory and `toJson` method
  - Add `readReceiptsEnabled` nullable bool field to existing `ChatSetting` model in `app/lib/models/chat_setting.dart`
  - _Requirements: 1.1, 1.2, 1.3, 5.4_

  - [x] 10.1 Write unit tests for PrivacySetting model
    - `testPrivacySettingFromJson`: assert correct deserialization from JSON
    - `testPrivacySettingToJson`: assert round-trip (serialize then deserialize yields equal object)
    - _Requirements: 1.1, 1.2_

- [x] 11. Flutter PrivacySetting repository
  - Create `app/lib/features/privacy/repositories/privacy_setting_repository.dart`
  - Implement `getPrivacySetting()`: GET `/api/v1/privacy-settings` with JWT auth header; return `PrivacySetting`
  - Implement `updatePrivacySetting(UpdatePrivacySettingRequest req)`: PUT `/api/v1/privacy-settings`; return updated `PrivacySetting`
  - Create Riverpod provider for `PrivacySettingRepository`
  - _Requirements: 6.1, 6.2, 6.3_

  - [x] 11.1 Write unit tests for PrivacySettingRepository
    - Mock HTTP client; assert `getPrivacySetting` parses response correctly
    - Assert `updatePrivacySetting` sends correct JSON body and returns updated model
    - _Requirements: 6.1, 6.2_

- [x] 12. Flutter privacy settings UI screen
  - Create `app/lib/features/privacy/privacy_settings_page.dart`
  - Display current values for Last Seen, Online Status, Profile Photo (radio group: Everyone / My Contacts / Nobody) and Read Receipts (toggle)
  - On selection change, call `privacySettingRepository.updatePrivacySetting(...)` with only the changed field
  - Use Riverpod `StateNotifierProvider` or `AsyncNotifierProvider` to manage loading/error state
  - Wire the page into the existing settings navigation
  - _Requirements: 1.1, 1.4, 6.1, 6.2, 6.4_

  - [x] 12.1 Write widget tests for privacy settings screen
    - `testPrivacySettingScreen_displaysCurrentValues`: assert UI shows values from repository
    - `testPrivacySettingScreen_updateCallsRepository`: assert tapping an option triggers `updatePrivacySetting` with correct partial request
    - _Requirements: 1.4, 6.4_

- [x] 13. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- All property tests use `pgregory.net/rapid` (already in the backend codebase)
- Each property test file should include the tag comment: `// Feature: privacy-settings, Property N: <property_text>`
- Property tests should run a minimum of 100 iterations
- The `FilterPresence` error handling strategy: fail-strict per subject (apply `last_seen=null, is_online=false`) but continue processing remaining subjects
- The mute check and `ShouldShowReadReceipt` both use fail-open strategy to avoid feature disruption on DB errors
