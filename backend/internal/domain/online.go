package domain

import (
	"context"
)

// OnlineRepository defines the interface for managing online status in Redis.
type OnlineRepository interface {
	SetUserOnline(ctx context.Context, userID string) error
	SetUserOffline(ctx context.Context, userID string) error
	IsUserOnline(ctx context.Context, userID string) (bool, error)
	GetOnlineUsers(ctx context.Context, userIDs []string) (map[string]bool, error)
}
