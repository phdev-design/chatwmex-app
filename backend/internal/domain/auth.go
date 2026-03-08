package domain

import (
	"context"
	"time"
)

// QRTokenStatus represents the state of a QR login token.
type QRTokenStatus string

const (
	QRTokenPending   QRTokenStatus = "pending"
	QRTokenConfirmed QRTokenStatus = "confirmed"
)

// AuthRepository defines the interface for authentication-related data persistence (e.g., Redis).
type AuthRepository interface {
	SaveQRToken(ctx context.Context, token string, expires time.Duration) error
	ConfirmQRToken(ctx context.Context, token, userID string) error
	GetQRTokenStatus(ctx context.Context, token string) (status QRTokenStatus, userID string, err error)
}

// AuthUsecase defines the interface for authentication business logic.
type AuthUsecase interface {
	GenerateQRToken(ctx context.Context) (string, error)
	ConfirmQRToken(ctx context.Context, token, userID string) error
}
