package redis_repo

import (
	"context"
	"fmt"
	"time"

	"chatwmex_backend/internal/domain"
	"github.com/redis/go-redis/v9"
)

const qrTokenPrefix = "qr_login:"

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
