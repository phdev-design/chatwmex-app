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

// QRTokenDetail holds the full details of a QR login token stored in Redis.
type QRTokenDetail struct {
	Token        string
	Status       QRTokenStatus
	UserID       string
	DeviceID     string
	WebPublicKey string
	Used         bool
	CreatedAt    time.Time
}
// ConfirmQRTokenResult holds the result of a successful QR token confirmation.
type ConfirmQRTokenResult struct {
	DeviceID  string `json:"device_id"`
	PublicKey string `json:"public_key"`
}

// AuthRepository defines the interface for authentication-related data persistence (e.g., Redis).
type AuthRepository interface {
	SaveQRToken(ctx context.Context, token string, expires time.Duration) error
	ConfirmQRToken(ctx context.Context, token, userID string) error
	GetQRTokenStatus(ctx context.Context, token string) (status QRTokenStatus, userID string, err error)

	// QR Token methods with public key support for linked devices.
	SaveQRTokenWithPublicKey(ctx context.Context, token, webPublicKey string, expires time.Duration) error
	GetQRTokenDetail(ctx context.Context, token string) (*QRTokenDetail, error)
	MarkQRTokenUsed(ctx context.Context, token string) error

	// Rate limiting for device link attempts.
	IncrementLinkFailure(ctx context.Context, userID string) (int, error)
	IsLinkBlocked(ctx context.Context, userID string) (bool, error)
	BlockLinkAttempts(ctx context.Context, userID string) error
}

// AuthUsecase defines the interface for authentication business logic.
type AuthUsecase interface {
	GenerateQRToken(ctx context.Context, webPublicKey string) (string, error)
	ConfirmQRToken(ctx context.Context, token, userID string) (*ConfirmQRTokenResult, error)
}
