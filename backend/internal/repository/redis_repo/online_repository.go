package redis_repo

import (
	"context"
	"fmt"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/redis/go-redis/v9"
)

const (
	onlineUsersSetKey  = "online_users"
	lastSeenKeyPrefix  = "last_seen:"
	lastSeenTTL        = 30 * 24 * time.Hour // 保留 30 天
)

// OnlineRepository implements domain.OnlineRepository for Redis.
type OnlineRepository struct {
	client *redis.Client
}

// NewOnlineRepository creates a new instance of OnlineRepository.
func NewOnlineRepository(client *redis.Client) domain.OnlineRepository {
	return &OnlineRepository{client: client}
}

func (r *OnlineRepository) SetUserOnline(ctx context.Context, userID string) error {
	return r.client.SAdd(ctx, onlineUsersSetKey, userID).Err()
}

func (r *OnlineRepository) SetUserOffline(ctx context.Context, userID string) error {
	return r.client.SRem(ctx, onlineUsersSetKey, userID).Err()
}

func (r *OnlineRepository) IsUserOnline(ctx context.Context, userID string) (bool, error) {
	return r.client.SIsMember(ctx, onlineUsersSetKey, userID).Result()
}

func (r *OnlineRepository) GetOnlineUsers(ctx context.Context, userIDs []string) (map[string]bool, error) {
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
		isOnline, _ := cmd.Result()
		result[userIDs[i]] = isOnline
	}
	return result, nil
}

// SetUserLastSeen stores the last seen timestamp for a user.
func (r *OnlineRepository) SetUserLastSeen(ctx context.Context, userID string, t time.Time) error {
	key := lastSeenKeyPrefix + userID
	return r.client.Set(ctx, key, t.UTC().Format(time.RFC3339), lastSeenTTL).Err()
}

// GetUserLastSeen retrieves the last seen timestamp for a user.
func (r *OnlineRepository) GetUserLastSeen(ctx context.Context, userID string) (*time.Time, error) {
	key := lastSeenKeyPrefix + userID
	val, err := r.client.Get(ctx, key).Result()
	if err == redis.Nil {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get last seen: %w", err)
	}
	t, err := time.Parse(time.RFC3339, val)
	if err != nil {
		return nil, fmt.Errorf("failed to parse last seen time: %w", err)
	}
	return &t, nil
}

// GetUsersPresence returns online status and last seen for a list of users in one batch.
func (r *OnlineRepository) GetUsersPresence(ctx context.Context, userIDs []string) (map[string]*domain.PresenceInfo, error) {
	if len(userIDs) == 0 {
		return map[string]*domain.PresenceInfo{}, nil
	}

	pipe := r.client.Pipeline()
	onlineCmds := make([]*redis.BoolCmd, len(userIDs))
	lastSeenCmds := make([]*redis.StringCmd, len(userIDs))

	for i, id := range userIDs {
		onlineCmds[i] = pipe.SIsMember(ctx, onlineUsersSetKey, id)
		lastSeenCmds[i] = pipe.Get(ctx, lastSeenKeyPrefix+id)
	}

	_, err := pipe.Exec(ctx)
	if err != nil && err != redis.Nil {
		return nil, fmt.Errorf("failed to execute presence pipeline: %w", err)
	}

	result := make(map[string]*domain.PresenceInfo, len(userIDs))
	for i, id := range userIDs {
		isOnline, _ := onlineCmds[i].Result()
		info := &domain.PresenceInfo{IsOnline: isOnline}

		if val, err := lastSeenCmds[i].Result(); err == nil {
			if t, err := time.Parse(time.RFC3339, val); err == nil {
				info.LastSeen = &t
			}
		}
		result[id] = info
	}
	return result, nil
}

// ClearAllOnline removes all entries from the online_users set.
// Called on server startup to clear stale presence from previous runs.
func (r *OnlineRepository) ClearAllOnline(ctx context.Context) error {
	return r.client.Del(ctx, onlineUsersSetKey).Err()
}
