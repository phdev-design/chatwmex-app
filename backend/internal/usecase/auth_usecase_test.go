package usecase

import (
	"context"
	"errors"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// MockAuthRepository is a mock implementation of domain.AuthRepository.
type MockAuthRepository struct {
	mock.Mock
}

func (m *MockAuthRepository) SaveQRToken(ctx context.Context, token string, expires time.Duration) error {
	args := m.Called(ctx, token, expires)
	return args.Error(0)
}

func (m *MockAuthRepository) ConfirmQRToken(ctx context.Context, token, userID string) error {
	args := m.Called(ctx, token, userID)
	return args.Error(0)
}

func (m *MockAuthRepository) GetQRTokenStatus(ctx context.Context, token string) (domain.QRTokenStatus, string, error) {
	args := m.Called(ctx, token)
	return args.Get(0).(domain.QRTokenStatus), args.String(1), args.Error(2)
}

func (m *MockAuthRepository) SaveQRTokenWithPublicKey(ctx context.Context, token, webPublicKey string, expires time.Duration) error {
	args := m.Called(ctx, token, webPublicKey, expires)
	return args.Error(0)
}

func (m *MockAuthRepository) GetQRTokenDetail(ctx context.Context, token string) (*domain.QRTokenDetail, error) {
	args := m.Called(ctx, token)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*domain.QRTokenDetail), args.Error(1)
}

func (m *MockAuthRepository) MarkQRTokenUsed(ctx context.Context, token string) error {
	args := m.Called(ctx, token)
	return args.Error(0)
}

func (m *MockAuthRepository) IncrementLinkFailure(ctx context.Context, userID string) (int, error) {
	args := m.Called(ctx, userID)
	return args.Int(0), args.Error(1)
}

func (m *MockAuthRepository) IsLinkBlocked(ctx context.Context, userID string) (bool, error) {
	args := m.Called(ctx, userID)
	return args.Bool(0), args.Error(1)
}

func (m *MockAuthRepository) BlockLinkAttempts(ctx context.Context, userID string) error {
	args := m.Called(ctx, userID)
	return args.Error(0)
}

// MockLinkedDeviceUsecase is a mock implementation of domain.LinkedDeviceUsecase.
type MockLinkedDeviceUsecase struct {
	mock.Mock
}

func (m *MockLinkedDeviceUsecase) LinkDevice(ctx context.Context, userID string, device *domain.LinkedDevice) error {
	args := m.Called(ctx, userID, device)
	return args.Error(0)
}

func (m *MockLinkedDeviceUsecase) UnlinkDevice(ctx context.Context, userID, deviceID string) error {
	args := m.Called(ctx, userID, deviceID)
	return args.Error(0)
}

func (m *MockLinkedDeviceUsecase) UnlinkAllDevices(ctx context.Context, userID string) error {
	args := m.Called(ctx, userID)
	return args.Error(0)
}

func (m *MockLinkedDeviceUsecase) GetLinkedDevices(ctx context.Context, userID string) ([]*domain.LinkedDevice, error) {
	args := m.Called(ctx, userID)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).([]*domain.LinkedDevice), args.Error(1)
}

func (m *MockLinkedDeviceUsecase) GetLinkedDeviceCount(ctx context.Context, userID string) (int, error) {
	args := m.Called(ctx, userID)
	return args.Int(0), args.Error(1)
}

func (m *MockLinkedDeviceUsecase) DeliverSessionKey(ctx context.Context, userID, deviceID, encryptedKey, senderPublicKey string) error {
	args := m.Called(ctx, userID, deviceID, encryptedKey, senderPublicKey)
	return args.Error(0)
}

func TestConfirmQRToken_Success(t *testing.T) {
	authRepo := new(MockAuthRepository)
	ldUsecase := new(MockLinkedDeviceUsecase)
	uc := NewAuthUsecase(authRepo, ldUsecase, time.Second)
	ctx := context.Background()

	detail := &domain.QRTokenDetail{
		Token:        "test-token",
		Status:       domain.QRTokenPending,
		Used:         false,
		WebPublicKey: "web-pub-key",
		CreatedAt:    time.Now(),
	}

	authRepo.On("IsLinkBlocked", mock.Anything, "user1").Return(false, nil)
	authRepo.On("GetQRTokenDetail", mock.Anything, "test-token").Return(detail, nil)
	authRepo.On("MarkQRTokenUsed", mock.Anything, "test-token").Return(nil)
	authRepo.On("ConfirmQRToken", mock.Anything, "test-token", "user1").Return(nil)
	ldUsecase.On("LinkDevice", mock.Anything, "user1", mock.AnythingOfType("*domain.LinkedDevice")).Return(nil)

	result, err := uc.ConfirmQRToken(ctx, "test-token", "user1")
	assert.NoError(t, err)
	assert.NotNil(t, result)
	assert.NotEmpty(t, result.DeviceID)
	assert.Equal(t, "web-pub-key", result.PublicKey)
	authRepo.AssertExpectations(t)
	ldUsecase.AssertExpectations(t)
}

func TestConfirmQRToken_RateLimited(t *testing.T) {
	authRepo := new(MockAuthRepository)
	ldUsecase := new(MockLinkedDeviceUsecase)
	uc := NewAuthUsecase(authRepo, ldUsecase, time.Second)
	ctx := context.Background()

	authRepo.On("IsLinkBlocked", mock.Anything, "user1").Return(true, nil)

	_, err := uc.ConfirmQRToken(ctx, "test-token", "user1")
	assert.Error(t, err)
	assert.Equal(t, "rate_limited", err.Error())
}

func TestConfirmQRToken_TokenAlreadyUsed(t *testing.T) {
	authRepo := new(MockAuthRepository)
	ldUsecase := new(MockLinkedDeviceUsecase)
	uc := NewAuthUsecase(authRepo, ldUsecase, time.Second)
	ctx := context.Background()

	detail := &domain.QRTokenDetail{
		Token:     "test-token",
		Used:      true,
		CreatedAt: time.Now(),
	}

	authRepo.On("IsLinkBlocked", mock.Anything, "user1").Return(false, nil)
	authRepo.On("GetQRTokenDetail", mock.Anything, "test-token").Return(detail, nil)
	authRepo.On("IncrementLinkFailure", mock.Anything, "user1").Return(1, nil)

	_, err := uc.ConfirmQRToken(ctx, "test-token", "user1")
	assert.Error(t, err)
	assert.Equal(t, "qr_token_already_used", err.Error())
}

func TestConfirmQRToken_TokenExpired(t *testing.T) {
	authRepo := new(MockAuthRepository)
	ldUsecase := new(MockLinkedDeviceUsecase)
	uc := NewAuthUsecase(authRepo, ldUsecase, time.Second)
	ctx := context.Background()

	detail := &domain.QRTokenDetail{
		Token:     "test-token",
		Used:      false,
		CreatedAt: time.Now().Add(-4 * time.Minute), // expired
	}

	authRepo.On("IsLinkBlocked", mock.Anything, "user1").Return(false, nil)
	authRepo.On("GetQRTokenDetail", mock.Anything, "test-token").Return(detail, nil)
	authRepo.On("IncrementLinkFailure", mock.Anything, "user1").Return(1, nil)

	_, err := uc.ConfirmQRToken(ctx, "test-token", "user1")
	assert.Error(t, err)
	assert.Equal(t, "qr_token_expired", err.Error())
}

func TestConfirmQRToken_InvalidToken(t *testing.T) {
	authRepo := new(MockAuthRepository)
	ldUsecase := new(MockLinkedDeviceUsecase)
	uc := NewAuthUsecase(authRepo, ldUsecase, time.Second)
	ctx := context.Background()

	authRepo.On("IsLinkBlocked", mock.Anything, "user1").Return(false, nil)
	authRepo.On("GetQRTokenDetail", mock.Anything, "bad-token").Return(nil, errors.New("not found"))
	authRepo.On("IncrementLinkFailure", mock.Anything, "user1").Return(1, nil)

	_, err := uc.ConfirmQRToken(ctx, "bad-token", "user1")
	assert.Error(t, err)
	assert.Equal(t, "qr_token_invalid", err.Error())
}

func TestConfirmQRToken_MaxDevicesReached(t *testing.T) {
	authRepo := new(MockAuthRepository)
	ldUsecase := new(MockLinkedDeviceUsecase)
	uc := NewAuthUsecase(authRepo, ldUsecase, time.Second)
	ctx := context.Background()

	detail := &domain.QRTokenDetail{
		Token:        "test-token",
		Used:         false,
		WebPublicKey: "web-pub-key",
		CreatedAt:    time.Now(),
	}

	authRepo.On("IsLinkBlocked", mock.Anything, "user1").Return(false, nil)
	authRepo.On("GetQRTokenDetail", mock.Anything, "test-token").Return(detail, nil)
	authRepo.On("MarkQRTokenUsed", mock.Anything, "test-token").Return(nil)
	authRepo.On("ConfirmQRToken", mock.Anything, "test-token", "user1").Return(nil)
	ldUsecase.On("LinkDevice", mock.Anything, "user1", mock.AnythingOfType("*domain.LinkedDevice")).Return(errors.New("max_devices_reached"))
	authRepo.On("IncrementLinkFailure", mock.Anything, "user1").Return(1, nil)

	_, err := uc.ConfirmQRToken(ctx, "test-token", "user1")
	assert.Error(t, err)
	assert.Equal(t, "max_devices_reached", err.Error())
}

func TestConfirmQRToken_FailureCountTriggersBlock(t *testing.T) {
	authRepo := new(MockAuthRepository)
	ldUsecase := new(MockLinkedDeviceUsecase)
	uc := NewAuthUsecase(authRepo, ldUsecase, time.Second)
	ctx := context.Background()

	authRepo.On("IsLinkBlocked", mock.Anything, "user1").Return(false, nil)
	authRepo.On("GetQRTokenDetail", mock.Anything, "bad-token").Return(nil, errors.New("not found"))
	authRepo.On("IncrementLinkFailure", mock.Anything, "user1").Return(5, nil)
	authRepo.On("BlockLinkAttempts", mock.Anything, "user1").Return(nil)

	_, err := uc.ConfirmQRToken(ctx, "bad-token", "user1")
	assert.Error(t, err)
	assert.Equal(t, "qr_token_invalid", err.Error())
	authRepo.AssertCalled(t, "BlockLinkAttempts", mock.Anything, "user1")
}

func TestConfirmQRToken_NilLinkedDeviceUsecase(t *testing.T) {
	authRepo := new(MockAuthRepository)
	uc := NewAuthUsecase(authRepo, nil, time.Second)
	ctx := context.Background()

	detail := &domain.QRTokenDetail{
		Token:     "test-token",
		Used:      false,
		CreatedAt: time.Now(),
	}

	authRepo.On("IsLinkBlocked", mock.Anything, "user1").Return(false, nil)
	authRepo.On("GetQRTokenDetail", mock.Anything, "test-token").Return(detail, nil)
	authRepo.On("MarkQRTokenUsed", mock.Anything, "test-token").Return(nil)
	authRepo.On("ConfirmQRToken", mock.Anything, "test-token", "user1").Return(nil)

	result, err := uc.ConfirmQRToken(ctx, "test-token", "user1")
	assert.NoError(t, err)
	assert.Nil(t, result)
}
