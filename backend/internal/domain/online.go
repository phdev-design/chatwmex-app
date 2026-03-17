package domain

import (
	"context"
	"time"
)

// OnlineRepository defines the interface for managing online status in Redis.
type OnlineRepository interface {
	SetUserOnline(ctx context.Context, userID string) error
	SetUserOffline(ctx context.Context, userID string) error
	IsUserOnline(ctx context.Context, userID string) (bool, error)
	GetOnlineUsers(ctx context.Context, userIDs []string) (map[string]bool, error)
	// Presence: last seen
	SetUserLastSeen(ctx context.Context, userID string, t time.Time) error
	GetUserLastSeen(ctx context.Context, userID string) (*time.Time, error)
	GetUsersPresence(ctx context.Context, userIDs []string) (map[string]*PresenceInfo, error)
	// ClearAllOnline removes all entries from the online set (called on server startup)
	ClearAllOnline(ctx context.Context) error
}

// PresenceInfo holds online status and last seen time for a user.
type PresenceInfo struct {
	IsOnline bool       `json:"is_online"`
	LastSeen *time.Time `json:"last_seen,omitempty"`
}
