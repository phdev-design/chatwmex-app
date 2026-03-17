package usecase

import (
	"context"
	"errors"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/stretchr/testify/assert"
	"pgregory.net/rapid"
)

// ---------------------------------------------------------------------------
// Property 7: Mute Check Suppresses Notifications
// Feature: privacy-settings, Property 7: Mute Check Suppresses Notifications
// ---------------------------------------------------------------------------

// Validates: Requirements 4.2, 4.3, 4.4
func TestProperty7_MuteCheckSuppressesNotifications(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		now := time.Now().Unix()
		muteUntil := rapid.Int64Range(now-86400, now+86400).Draw(t, "muteUntil")
		setting := &domain.ChatSetting{MuteUntil: &muteUntil}
		isMuted := isChatMuted(setting)
		assert.Equal(t, muteUntil > now, isMuted)
	})
}

// ---------------------------------------------------------------------------
// Unit tests for mute check edge cases
// ---------------------------------------------------------------------------

// Validates: Requirements 4.3
func TestMuteCheck_MuteUntilNegativeOne(t *testing.T) {
	muteUntil := int64(-1)
	setting := &domain.ChatSetting{MuteUntil: &muteUntil}
	assert.True(t, isChatMuted(setting), "permanent mute (-1) should return isMuted=true")
}

// Validates: Requirements 4.4
func TestMuteCheck_MuteUntilExpired(t *testing.T) {
	past := time.Now().Unix() - 3600 // 1 hour ago
	setting := &domain.ChatSetting{MuteUntil: &past}
	assert.False(t, isChatMuted(setting), "expired mute (past timestamp) should return isMuted=false")
}

// Validates: Requirements 4.4
func TestMuteCheck_NotMuted(t *testing.T) {
	setting := &domain.ChatSetting{MuteUntil: nil}
	assert.False(t, isChatMuted(setting), "nil MuteUntil should return isMuted=false")
}

// ---------------------------------------------------------------------------
// Fail-open test: DB error → log + send notification
// ---------------------------------------------------------------------------

// mockChatSettingUsecase is a minimal mock for ChatSettingUsecase.
type mockChatSettingUsecase struct {
	getSettingFn func(ctx context.Context, chatID string) (*domain.ChatSetting, error)
}

func (m *mockChatSettingUsecase) GetChatSetting(ctx context.Context, chatID string) (*domain.ChatSetting, error) {
	if m.getSettingFn != nil {
		return m.getSettingFn(ctx, chatID)
	}
	return nil, nil
}

func (m *mockChatSettingUsecase) UpdateDisappearingTimer(ctx context.Context, chatID string, timerSeconds int) (*domain.ChatSetting, error) {
	return nil, nil
}

func (m *mockChatSettingUsecase) UpdateMuteUntil(ctx context.Context, chatID string, muteUntil *int64) (*domain.ChatSetting, error) {
	return nil, nil
}

func (m *mockChatSettingUsecase) UpdateMediaSettings(ctx context.Context, chatID string, saveToCameraRoll, autoDownload, mediaQuality *int) (*domain.ChatSetting, error) {
	return nil, nil
}

// mockDeviceRepo is a minimal mock for DeviceRepository that returns one device.
type mockDeviceRepo struct {
	devices []*domain.Device
}

func (m *mockDeviceRepo) GetByUserID(_ context.Context, _ string) ([]*domain.Device, error) {
	return m.devices, nil
}

func (m *mockDeviceRepo) Upsert(_ context.Context, _ *domain.Device) error { return nil }
func (m *mockDeviceRepo) Delete(_ context.Context, _ string) error          { return nil }
func (m *mockDeviceRepo) DeleteByUserID(_ context.Context, _ string) error  { return nil }
func (m *mockDeviceRepo) GetByID(_ context.Context, _ string) (*domain.Device, error) {
	return nil, nil
}

// mockRoomRepo is a minimal mock for RoomRepository.
type mockRoomRepo struct{}

func (m *mockRoomRepo) Create(_ context.Context, _ *domain.Room) error { return nil }
func (m *mockRoomRepo) GetByID(_ context.Context, _ string) (*domain.Room, error) {
	return nil, nil
}
func (m *mockRoomRepo) AddMember(_ context.Context, _, _ string) error    { return nil }
func (m *mockRoomRepo) RemoveMember(_ context.Context, _, _ string) error { return nil }
func (m *mockRoomRepo) DeleteRoom(_ context.Context, _ string) error      { return nil }
func (m *mockRoomRepo) GetMembers(_ context.Context, _ string) ([]string, error) {
	return nil, nil
}
func (m *mockRoomRepo) GetUserRooms(_ context.Context, _ string) ([]*domain.Room, error) {
	return nil, nil
}
func (m *mockRoomRepo) UpdateRoom(_ context.Context, _ string, _ map[string]interface{}) error {
	return nil
}
func (m *mockRoomRepo) UpdateOwner(_ context.Context, _, _ string) error { return nil }

// mockUserRepo is a minimal mock for UserRepository.
type mockUserRepo struct{}

func (m *mockUserRepo) Create(_ context.Context, _ *domain.User) error { return nil }
func (m *mockUserRepo) GetByID(_ context.Context, _ string) (*domain.User, error) {
	return nil, nil
}
func (m *mockUserRepo) GetByUsername(_ context.Context, _ string) (*domain.User, error) {
	return nil, nil
}
func (m *mockUserRepo) GetByEmail(_ context.Context, _ string) (*domain.User, error) {
	return nil, nil
}
func (m *mockUserRepo) Update(_ context.Context, _ *domain.User) error { return nil }
func (m *mockUserRepo) UpdateAvatar(_ context.Context, _, _ string) error { return nil }
func (m *mockUserRepo) UpdatePublicKey(_ context.Context, _, _ string) error { return nil }
func (m *mockUserRepo) UpdateKeyBackup(_ context.Context, _, _, _ string) error { return nil }

// Validates: Requirements 4.5
// TestNotificationConsumer_DBError_FailOpen verifies that when GetChatSetting returns a DB error,
// the notification is still sent (fail-open strategy).
func TestNotificationConsumer_DBError_FailOpen(t *testing.T) {
	dbErr := errors.New("mongo: connection refused")

	settingUC := &mockChatSettingUsecase{
		getSettingFn: func(_ context.Context, _ string) (*domain.ChatSetting, error) {
			return nil, dbErr
		},
	}

	deviceRepo := &mockDeviceRepo{
		devices: []*domain.Device{{ID: "player-abc"}},
	}

	uc := &messageUsecase{
		settingUsecase: settingUC,
		deviceRepo:     deviceRepo,
		roomRepo:       &mockRoomRepo{},
		userRepo:       &mockUserRepo{},
	}

	msg := &domain.Message{
		SenderID:   "sender1",
		ReceiverID: "receiver1",
		Content:    "hello",
	}

	// buildPushNotificationMessage should still return a non-nil message (fail-open)
	result := uc.buildPushNotificationMessage(context.Background(), []string{"receiver1"}, msg)
	assert.NotNil(t, result, "notification should still be built when DB error occurs (fail-open)")
	assert.Contains(t, result.PlayerIDs, "player-abc")
}
