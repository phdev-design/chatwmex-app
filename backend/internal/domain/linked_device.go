package domain

import (
	"context"
	"time"
)

// LinkedDevice represents a device linked to a user's account via QR code scanning.
type LinkedDevice struct {
	ID           string    `json:"id" bson:"_id"`
	UserID       string    `json:"user_id" bson:"user_id"`
	DeviceName   string    `json:"device_name" bson:"device_name"`
	Platform     string    `json:"platform" bson:"platform"`           // "web"
	PublicKey    string    `json:"public_key" bson:"public_key"`       // Web 端的 X25519 公鑰
	LinkedAt     time.Time `json:"linked_at" bson:"linked_at"`
	LastActiveAt time.Time `json:"last_active_at" bson:"last_active_at"`
	ExpiresAt    time.Time `json:"expires_at" bson:"expires_at"`       // 30 天後自動過期
}

// LinkedDeviceRepository defines the interface for linked device data persistence.
type LinkedDeviceRepository interface {
	Create(ctx context.Context, device *LinkedDevice) error
	Delete(ctx context.Context, deviceID string) error
	DeleteByUserID(ctx context.Context, userID string) error
	GetByID(ctx context.Context, deviceID string) (*LinkedDevice, error)
	GetByUserID(ctx context.Context, userID string) ([]*LinkedDevice, error)
	CountByUserID(ctx context.Context, userID string) (int, error)
	UpdateLastActive(ctx context.Context, deviceID string) error
}

// LinkedDeviceUsecase defines the interface for linked device business logic.
type LinkedDeviceUsecase interface {
	LinkDevice(ctx context.Context, userID string, device *LinkedDevice) error
	UnlinkDevice(ctx context.Context, userID, deviceID string) error
	UnlinkAllDevices(ctx context.Context, userID string) error
	GetLinkedDevices(ctx context.Context, userID string) ([]*LinkedDevice, error)
	GetLinkedDeviceCount(ctx context.Context, userID string) (int, error)
	DeliverSessionKey(ctx context.Context, userID, deviceID, encryptedKey, senderPublicKey string) error
}
