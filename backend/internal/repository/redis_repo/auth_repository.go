package redis_repo

import (
	"context"
	"fmt"
	"time"

	"chatwmex_backend/internal/domain"
	"github.com/redis/go-redis/v9"
)

const (
	qrTokenPrefix      = "qr_login:"
	linkRateLimitPrefix = "link_rate_limit:"
	linkBlockedPrefix   = "link_blocked:"
	linkRateLimitTTL    = 300 * time.Second // 5 minutes
	linkBlockedTTL      = 900 * time.Second // 15 minutes
)

type authRepository struct {
	client *redis.Client
}

// NewAuthRepository creates a new AuthRepository using Redis.
func NewAuthRepository(client *redis.Client) domain.AuthRepository {
	return &authRepository{client: client}
}

func (r *authRepository) SaveQRToken(ctx context.Context, token string, expires time.Duration) error {
	key := qrTokenPrefix + token
	// Store state as pending
	err := r.client.HSet(ctx, key, map[string]interface{}{
		"status":  string(domain.QRTokenPending),
		"user_id": "",
	}).Err()
	if err != nil {
		return err
	}
	return r.client.Expire(ctx, key, expires).Err()
}

func (r *authRepository) ConfirmQRToken(ctx context.Context, token, userID string) error {
	key := qrTokenPrefix + token
	
	// Check if token exists
	exists, err := r.client.Exists(ctx, key).Result()
	if err != nil {
		return err
	}
	if exists == 0 {
		return fmt.Errorf("qr token expired or invalid")
	}

	return r.client.HSet(ctx, key, map[string]interface{}{
		"status":  string(domain.QRTokenConfirmed),
		"user_id": userID,
	}).Err()
}

func (r *authRepository) GetQRTokenStatus(ctx context.Context, token string) (domain.QRTokenStatus, string, error) {
	key := qrTokenPrefix + token

	res, err := r.client.HGetAll(ctx, key).Result()
	if err != nil {
		return "", "", err
	}
	if len(res) == 0 {
		return "", "", fmt.Errorf("qr token not found")
	}

	status := domain.QRTokenStatus(res["status"])
	userID := res["user_id"]
	return status, userID, nil
}

func (r *authRepository) SaveQRTokenWithPublicKey(ctx context.Context, token, webPublicKey string, expires time.Duration) error {
	key := qrTokenPrefix + token
	err := r.client.HSet(ctx, key, map[string]interface{}{
		"status":         string(domain.QRTokenPending),
		"user_id":        "",
		"device_id":      "",
		"web_public_key": webPublicKey,
		"used":           "false",
		"created_at":     time.Now().UTC().Format(time.RFC3339),
	}).Err()
	if err != nil {
		return err
	}
	return r.client.Expire(ctx, key, expires).Err()
}

func (r *authRepository) GetQRTokenDetail(ctx context.Context, token string) (*domain.QRTokenDetail, error) {
	key := qrTokenPrefix + token

	res, err := r.client.HGetAll(ctx, key).Result()
	if err != nil {
		return nil, err
	}
	if len(res) == 0 {
		return nil, fmt.Errorf("qr token not found")
	}

	var createdAt time.Time
	if v, ok := res["created_at"]; ok && v != "" {
		createdAt, _ = time.Parse(time.RFC3339, v)
	}

	return &domain.QRTokenDetail{
		Token:        token,
		Status:       domain.QRTokenStatus(res["status"]),
		UserID:       res["user_id"],
		DeviceID:     res["device_id"],
		WebPublicKey: res["web_public_key"],
		Used:         res["used"] == "true",
		CreatedAt:    createdAt,
	}, nil
}

func (r *authRepository) MarkQRTokenUsed(ctx context.Context, token string) error {
	key := qrTokenPrefix + token

	exists, err := r.client.Exists(ctx, key).Result()
	if err != nil {
		return err
	}
	if exists == 0 {
		return fmt.Errorf("qr token not found")
	}

	return r.client.HSet(ctx, key, "used", "true").Err()
}

func (r *authRepository) IncrementLinkFailure(ctx context.Context, userID string) (int, error) {
	key := linkRateLimitPrefix + userID

	count, err := r.client.Incr(ctx, key).Result()
	if err != nil {
		return 0, err
	}

	// Set TTL only on first increment (when count becomes 1).
	if count == 1 {
		r.client.Expire(ctx, key, linkRateLimitTTL)
	}

	return int(count), nil
}

func (r *authRepository) IsLinkBlocked(ctx context.Context, userID string) (bool, error) {
	key := linkBlockedPrefix + userID

	exists, err := r.client.Exists(ctx, key).Result()
	if err != nil {
		return false, err
	}
	return exists > 0, nil
}

func (r *authRepository) BlockLinkAttempts(ctx context.Context, userID string) error {
	key := linkBlockedPrefix + userID
	return r.client.Set(ctx, key, "true", linkBlockedTTL).Err()
}
