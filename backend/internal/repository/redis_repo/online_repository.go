package redis_repo

import (
	"context"
	"fmt"

	"chatwmex_backend/internal/domain"

	"github.com/redis/go-redis/v9"
)

const onlineUsersSetKey = "online_users"

// OnlineRepository implements domain.OnlineRepository for Redis.
type OnlineRepository struct {
	client *redis.Client
}

// NewOnlineRepository creates a new instance of OnlineRepository.
func NewOnlineRepository(client *redis.Client) domain.OnlineRepository {
	return &OnlineRepository{
		client: client,
	}
}

// SetUserOnline marks a user as online.
// It uses a Redis Set to store online user IDs.
// Optionally, we could use HSET with timestamp for "last seen".
// For simplicity and scalability (checking membership), we use a Set.
func (r *OnlineRepository) SetUserOnline(ctx context.Context, userID string) error {
	return r.client.SAdd(ctx, onlineUsersSetKey, userID).Err()
}

// SetUserOffline marks a user as offline.
func (r *OnlineRepository) SetUserOffline(ctx context.Context, userID string) error {
	return r.client.SRem(ctx, onlineUsersSetKey, userID).Err()
}

// IsUserOnline checks if a user is online.
func (r *OnlineRepository) IsUserOnline(ctx context.Context, userID string) (bool, error) {
	return r.client.SIsMember(ctx, onlineUsersSetKey, userID).Result()
}

// GetOnlineUsers checks the online status for a list of users.
// Returns a map where key is userID and value is true if online.
func (r *OnlineRepository) GetOnlineUsers(ctx context.Context, userIDs []string) (map[string]bool, error) {
	// For small lists, we can use SMISMEMBER (available in Redis 6.2+).
	// If not available, we can use pipeline with SISMEMBER.
	// Let's use Pipeline for compatibility.

	pipe := r.client.Pipeline()
	cmds := make([]*redis.BoolCmd, len(userIDs))

	for i, id := range userIDs {
		cmds[i] = pipe.SIsMember(ctx, onlineUsersSetKey, id)
	}

	_, err := pipe.Exec(ctx)
	if err != nil && err != redis.Nil {
		return nil, fmt.Errorf("failed to execute pipeline: %w", err)
	}

	result := make(map[string]bool)
	for i, cmd := range cmds {
		isOnline, _ := cmd.Result() // Ignore individual errors, treat as offline
		result[userIDs[i]] = isOnline
	}

	return result, nil
}
