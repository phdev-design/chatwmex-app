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
	DisappearingTimer int       `json:"disappearing_timer"` // Timer in seconds (e.g., 86400 for 24h, 0 for off)
	UpdatedAt         time.Time `json:"updated_at"`
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
}
