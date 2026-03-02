package domain

import (
	"context"
	"time"
)

type Device struct {
	ID        string    `json:"id" bson:"_id"` // Push Token or Subscription ID
	UserID    string    `json:"user_id" bson:"user_id"`
	Platform  string    `json:"platform" bson:"platform"` // ios, android
	LastActive time.Time `json:"last_active" bson:"last_active"`
}

type DeviceRepository interface {
	Upsert(ctx context.Context, device *Device) error
	Delete(ctx context.Context, deviceID string) error
	DeleteByUserID(ctx context.Context, userID string) error
	GetByID(ctx context.Context, deviceID string) (*Device, error)
	GetByUserID(ctx context.Context, userID string) ([]*Device, error)
}

type DeviceUsecase interface {
	RegisterDevice(ctx context.Context, deviceID, userID, platform string) error
	UnregisterDevice(ctx context.Context, deviceID string) error
	UnregisterAllDevices(ctx context.Context, userID string) error
}
