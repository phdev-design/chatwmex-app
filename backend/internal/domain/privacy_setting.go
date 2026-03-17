package domain

import "context"

// PrivacyLevel defines the visibility level for a privacy setting.
type PrivacyLevel int

const (
	PrivacyLevelEveryone PrivacyLevel = 0 // 所有人
	PrivacyLevelContacts PrivacyLevel = 1 // 我的聯絡人
	PrivacyLevelNobody   PrivacyLevel = 2 // 沒人
)

// PrivacySetting stores a single user's global privacy preferences.
type PrivacySetting struct {
	UserID              string       `json:"user_id"`
	LastSeenPrivacy     PrivacyLevel `json:"last_seen_privacy"`
	OnlineStatusPrivacy PrivacyLevel `json:"online_status_privacy"`
	ProfilePhotoPrivacy PrivacyLevel `json:"profile_photo_privacy"`
	ReadReceiptsEnabled bool         `json:"read_receipts_enabled"`
}

// UserPrivacyRepository defines the persistence interface for privacy settings.
type UserPrivacyRepository interface {
	GetPrivacySetting(ctx context.Context, userID string) (*PrivacySetting, error)
	UpsertPrivacySetting(ctx context.Context, setting *PrivacySetting) error
}

// PrivacySettingUsecase defines the business logic interface for privacy settings.
type PrivacySettingUsecase interface {
	GetPrivacySetting(ctx context.Context, userID string) (*PrivacySetting, error)
	UpdatePrivacySetting(ctx context.Context, userID string, req UpdatePrivacySettingRequest) (*PrivacySetting, error)
	// FilterPresence applies privacy filtering and returns the filtered PresenceInfo map.
	FilterPresence(ctx context.Context, viewerID string, subjects map[string]*PresenceInfo) (map[string]*PresenceInfo, error)
	// ShouldShowReadReceipt determines whether a read receipt should be shown in a DM.
	ShouldShowReadReceipt(ctx context.Context, readerID, senderID string, isGroup bool) (bool, error)
}

// UpdatePrivacySettingRequest supports partial field updates (nil pointer = do not update).
type UpdatePrivacySettingRequest struct {
	LastSeenPrivacy     *PrivacyLevel `json:"last_seen_privacy"`
	OnlineStatusPrivacy *PrivacyLevel `json:"online_status_privacy"`
	ProfilePhotoPrivacy *PrivacyLevel `json:"profile_photo_privacy"`
	ReadReceiptsEnabled *bool         `json:"read_receipts_enabled"`
}
