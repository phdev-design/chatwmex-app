package usecase

import (
	"context"
	"time"

	"chatwmex_backend/internal/domain"
)

type deviceUsecase struct {
	deviceRepo     domain.DeviceRepository
	contextTimeout time.Duration
}

func NewDeviceUsecase(deviceRepo domain.DeviceRepository, timeout time.Duration) domain.DeviceUsecase {
	return &deviceUsecase{
		deviceRepo:     deviceRepo,
		contextTimeout: timeout,
	}
}

func (u *deviceUsecase) RegisterDevice(c context.Context, deviceID, userID, platform string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	device := &domain.Device{
		ID:       deviceID,
		UserID:   userID,
		Platform: platform,
	}

	// Upsert handles the logic:
	// 1. If ID doesn't exist, create new mapping to UserID
	// 2. If ID exists (was mapped to OldUser), update to NewUser
	// This ensures OldUser no longer receives notifications for this device.
	return u.deviceRepo.Upsert(ctx, device)
}

func (u *deviceUsecase) UnregisterDevice(c context.Context, deviceID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.deviceRepo.Delete(ctx, deviceID)
}

func (u *deviceUsecase) UnregisterAllDevices(c context.Context, userID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.deviceRepo.DeleteByUserID(ctx, userID)
}
