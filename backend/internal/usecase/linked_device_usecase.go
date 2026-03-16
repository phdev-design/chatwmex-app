package usecase

import (
	"context"
	"errors"
	"time"

	"chatwmex_backend/internal/domain"
)

// MaxLinkedDevices is the maximum number of linked devices allowed per user.
const MaxLinkedDevices = 4

// WebSocketNotifier defines the interface for sending WebSocket events to users.
// This is implemented by the WebSocket Hub.
type WebSocketNotifier interface {
	SendNotification(userID, event string, data interface{})
}

type linkedDeviceUsecase struct {
	linkedDeviceRepo domain.LinkedDeviceRepository
	wsNotifier       WebSocketNotifier
	contextTimeout   time.Duration
}

// NewLinkedDeviceUsecase creates a new LinkedDeviceUsecase.
func NewLinkedDeviceUsecase(repo domain.LinkedDeviceRepository, ws WebSocketNotifier, timeout time.Duration) domain.LinkedDeviceUsecase {
	return &linkedDeviceUsecase{
		linkedDeviceRepo: repo,
		wsNotifier:       ws,
		contextTimeout:   timeout,
	}
}

func (u *linkedDeviceUsecase) LinkDevice(c context.Context, userID string, device *domain.LinkedDevice) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	count, err := u.linkedDeviceRepo.CountByUserID(ctx, userID)
	if err != nil {
		return err
	}
	if count >= MaxLinkedDevices {
		return errors.New("max_devices_reached")
	}

	device.UserID = userID
	device.LinkedAt = time.Now()
	device.LastActiveAt = time.Now()
	device.ExpiresAt = device.LinkedAt.Add(30 * 24 * time.Hour)

	return u.linkedDeviceRepo.Create(ctx, device)
}

func (u *linkedDeviceUsecase) UnlinkDevice(c context.Context, userID, deviceID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	device, err := u.linkedDeviceRepo.GetByID(ctx, deviceID)
	if err != nil {
		return err
	}
	if device == nil {
		return errors.New("device_not_found")
	}
	if device.UserID != userID {
		return errors.New("unauthorized")
	}

	err = u.linkedDeviceRepo.Delete(ctx, deviceID)
	if err != nil {
		return err
	}

	// Notify the unlinked device via WebSocket
	if u.wsNotifier != nil {
		u.wsNotifier.SendNotification(deviceID, "device_unlinked", map[string]interface{}{
			"device_id": deviceID,
		})
	}

	return nil
}

func (u *linkedDeviceUsecase) UnlinkAllDevices(c context.Context, userID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// Get all devices first to notify them
	devices, err := u.linkedDeviceRepo.GetByUserID(ctx, userID)
	if err != nil {
		return err
	}

	err = u.linkedDeviceRepo.DeleteByUserID(ctx, userID)
	if err != nil {
		return err
	}

	// Notify all unlinked devices via WebSocket
	if u.wsNotifier != nil {
		for _, device := range devices {
			u.wsNotifier.SendNotification(device.ID, "device_unlinked", map[string]interface{}{
				"device_id": device.ID,
			})
		}
	}

	return nil
}

func (u *linkedDeviceUsecase) GetLinkedDevices(c context.Context, userID string) ([]*domain.LinkedDevice, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.linkedDeviceRepo.GetByUserID(ctx, userID)
}

func (u *linkedDeviceUsecase) GetLinkedDeviceCount(c context.Context, userID string) (int, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.linkedDeviceRepo.CountByUserID(ctx, userID)
}

func (u *linkedDeviceUsecase) DeliverSessionKey(c context.Context, userID, deviceID, encryptedKey, senderPublicKey string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// Verify the device belongs to the user
	device, err := u.linkedDeviceRepo.GetByID(ctx, deviceID)
	if err != nil {
		return err
	}
	if device == nil {
		return errors.New("device_not_found")
	}
	if device.UserID != userID {
		return errors.New("unauthorized")
	}

	// Deliver the encrypted session key via WebSocket
	if u.wsNotifier == nil {
		return errors.New("session_key_delivery_failed")
	}

	u.wsNotifier.SendNotification(deviceID, "session_key_delivery", map[string]interface{}{
		"device_id":         deviceID,
		"encrypted_key":     encryptedKey,
		"sender_public_key": senderPublicKey,
	})

	return nil
}
