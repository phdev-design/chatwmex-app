package usecase

import (
	"context"
	"time"
	"github.com/google/uuid"

	"chatwmex_backend/internal/domain"
)

type authUsecase struct {
	authRepo       domain.AuthRepository
	contextTimeout time.Duration
}

// NewAuthUsecase creates a new AuthUsecase.
func NewAuthUsecase(repo domain.AuthRepository, timeout time.Duration) domain.AuthUsecase {
	return &authUsecase{
		authRepo:       repo,
		contextTimeout: timeout,
	}
}

func (u *authUsecase) GenerateQRToken(c context.Context) (string, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	token := uuid.New().String()
	// Expiry of 3 minutes
	err := u.authRepo.SaveQRToken(ctx, token, 3*time.Minute)
	if err != nil {
		return "", err
	}

	return token, nil
}

func (u *authUsecase) ConfirmQRToken(c context.Context, token, userID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.authRepo.ConfirmQRToken(ctx, token, userID)
}
