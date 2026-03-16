package usecase

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"

	"chatwmex_backend/internal/domain"
)

const (
	// maxLinkFailures is the threshold before blocking link attempts.
	maxLinkFailures = 5
)

type authUsecase struct {
	authRepo            domain.AuthRepository
	linkedDeviceUsecase domain.LinkedDeviceUsecase
	contextTimeout      time.Duration
}

// NewAuthUsecase creates a new AuthUsecase.
func NewAuthUsecase(repo domain.AuthRepository, ldUsecase domain.LinkedDeviceUsecase, timeout time.Duration) domain.AuthUsecase {
	return &authUsecase{
		authRepo:            repo,
		linkedDeviceUsecase: ldUsecase,
		contextTimeout:      timeout,
	}
}

func (u *authUsecase) GenerateQRToken(c context.Context, webPublicKey string) (string, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	token := uuid.New().String()
	// Expiry of 3 minutes
	if webPublicKey != "" {
		err := u.authRepo.SaveQRTokenWithPublicKey(ctx, token, webPublicKey, 3*time.Minute)
		if err != nil {
			return "", err
		}
	} else {
		err := u.authRepo.SaveQRToken(ctx, token, 3*time.Minute)
		if err != nil {
			return "", err
		}
	}

	return token, nil
}

func (u *authUsecase) ConfirmQRToken(c context.Context, token, userID string) (*domain.ConfirmQRTokenResult, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// Step 1: Check if user is rate-limited
	blocked, err := u.authRepo.IsLinkBlocked(ctx, userID)
	if err != nil {
		return nil, err
	}
	if blocked {
		return nil, errors.New("rate_limited")
	}

	// Step 2: Get QR token detail
	detail, err := u.authRepo.GetQRTokenDetail(ctx, token)
	if err != nil {
		u.recordFailure(ctx, userID)
		return nil, errors.New("qr_token_invalid")
	}
	if detail == nil {
		u.recordFailure(ctx, userID)
		return nil, errors.New("qr_token_invalid")
	}

	// Step 3: Check if token is already used
	if detail.Used {
		u.recordFailure(ctx, userID)
		return nil, errors.New("qr_token_already_used")
	}

	// Step 4: Check if token is expired (created more than 3 minutes ago)
	if time.Since(detail.CreatedAt) > 3*time.Minute {
		u.recordFailure(ctx, userID)
		return nil, errors.New("qr_token_expired")
	}

	// Step 5: Mark token as used
	if err := u.authRepo.MarkQRTokenUsed(ctx, token); err != nil {
		return nil, err
	}

	// Step 6: Confirm the QR token in the repository (existing logic)
	if err := u.authRepo.ConfirmQRToken(ctx, token, userID); err != nil {
		return nil, err
	}

	// Step 7: Create LinkedDevice record
	var result *domain.ConfirmQRTokenResult
	if u.linkedDeviceUsecase != nil {
		deviceID := uuid.New().String()
		device := &domain.LinkedDevice{
			ID:        deviceID,
			Platform:  "web",
			PublicKey: detail.WebPublicKey,
		}
		if err := u.linkedDeviceUsecase.LinkDevice(ctx, userID, device); err != nil {
			u.recordFailure(ctx, userID)
			return nil, err
		}
		result = &domain.ConfirmQRTokenResult{
			DeviceID:  deviceID,
			PublicKey: detail.WebPublicKey,
		}
	}

	return result, nil
}

// recordFailure increments the link failure count and blocks the user if the threshold is reached.
func (u *authUsecase) recordFailure(ctx context.Context, userID string) {
	count, err := u.authRepo.IncrementLinkFailure(ctx, userID)
	if err != nil {
		return
	}
	if count >= maxLinkFailures {
		_ = u.authRepo.BlockLinkAttempts(ctx, userID)
	}
}
