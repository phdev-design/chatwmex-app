package domain

import (
	"context"
	"time"
)

// OfflineLinkedMessage represents a message buffered for an offline linked device.
type OfflineLinkedMessage struct {
	ID        string    `json:"id" bson:"_id"`
	DeviceID  string    `json:"device_id" bson:"device_id"`
	Message   *Message  `json:"message" bson:"message"`
	CreatedAt time.Time `json:"created_at" bson:"created_at"`
	ExpiresAt time.Time `json:"expires_at" bson:"expires_at"` // 7 天 TTL
}

// OfflineLinkedMessageRepository defines the interface for offline linked message data persistence.
type OfflineLinkedMessageRepository interface {
	Store(ctx context.Context, msg *OfflineLinkedMessage) error
	GetByDeviceID(ctx context.Context, deviceID string) ([]*OfflineLinkedMessage, error)
	DeleteByDeviceID(ctx context.Context, deviceID string) error
}
