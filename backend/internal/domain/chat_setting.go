package domain

import (
	"context"
	"time"
)

// ChatSetting stores per-chat configurations, such as the disappearing messages timer.
// ChatID can be either a RoomID (for group chats) or a deterministic string (e.g., "userID_contactID") for DMs.
type ChatSetting struct {
	ID                string    `json:"id"`
	ChatID            string    `json:"chat_id"`
	DisappearingTimer int       `json:"disappearing_timer"`  // Timer in seconds (e.g., 86400 for 24h, 0 for off)
	MuteUntil         *int64    `json:"mute_until"`          // 新增：Unix timestamp，nil=不靜音，-1=永久靜音
	SaveToCameraRoll  *int      `json:"save_to_camera_roll"` // 0=Global, 1=Always, 2=Never
	AutoDownload        *int      `json:"auto_download"`         // 0=Global, 1=Always, 2=Wi-Fi Only, 3=Never
	MediaQuality        *int      `json:"media_quality"`         // 0=Global, 1=HD, 2=Data Saver
	ReadReceiptsEnabled *bool     `json:"read_receipts_enabled"` // nil=use global setting
	UpdatedAt           time.Time `json:"updated_at"`
}

// ChatSettingRepository defines the interface for persisting chat settings.
type ChatSettingRepository interface {
	GetSetting(ctx context.Context, chatID string) (*ChatSetting, error)
	UpsertSetting(ctx context.Context, setting *ChatSetting) error
}

// ChatSettingUsecase defines the interface for chat settings business logic.
type ChatSettingUsecase interface {
	GetChatSetting(ctx context.Context, chatID string) (*ChatSetting, error)
	UpdateDisappearingTimer(ctx context.Context, chatID string, timerSeconds int) (*ChatSetting, error)
	UpdateMuteUntil(ctx context.Context, chatID string, muteUntil *int64) (*ChatSetting, error)
	UpdateMediaSettings(ctx context.Context, chatID string, saveToCameraRoll, autoDownload, mediaQuality *int) (*ChatSetting, error)
}
