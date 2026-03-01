package services

import (
	"context"
	"fmt"
	"time"

	"chatwme/backend/database"

	"github.com/redis/go-redis/v9"
)

type CacheService struct {
	redis *database.RedisClient
}

func NewCacheService(redis *database.RedisClient) *CacheService {
	return &CacheService{
		redis: redis,
	}
}

// UserRoomKey generates the key for user room membership
func (s *CacheService) UserRoomKey(userID, roomID string) string {
	return fmt.Sprintf("user_room:%s:%s", userID, roomID)
}

// IsUserInRoom checks if a user is in a room using Redis cache
// Returns (isInRoom, foundInCache, error)
func (s *CacheService) IsUserInRoom(ctx context.Context, userID, roomID string) (bool, bool, error) {
	key := s.UserRoomKey(userID, roomID)
	val, err := s.redis.Client.Get(ctx, key).Result()
	if err == redis.Nil {
		return false, false, nil // Not found in cache
	} else if err != nil {
		return false, false, err
	}
	return val == "1", true, nil
}

// SetUserInRoom sets the user room membership in cache
func (s *CacheService) SetUserInRoom(ctx context.Context, userID, roomID string, isInRoom bool) error {
	key := s.UserRoomKey(userID, roomID)
	val := "0"
	if isInRoom {
		val = "1"
	}
	// Cache for 1 hour
	return s.redis.Client.Set(ctx, key, val, 1*time.Hour).Err()
}

// BlockedUserKey generates the key for blocked user check
func (s *CacheService) BlockedUserKey(blockerID, blockedID string) string {
	return fmt.Sprintf("blocked:%s:%s", blockerID, blockedID)
}

// IsUserBlocked checks if a user is blocked using Redis cache
// Returns (isBlocked, foundInCache, error)
func (s *CacheService) IsUserBlocked(ctx context.Context, blockerID, blockedID string) (bool, bool, error) {
	key := s.BlockedUserKey(blockerID, blockedID)
	val, err := s.redis.Client.Get(ctx, key).Result()
	if err == redis.Nil {
		return false, false, nil // Not in cache
	} else if err != nil {
		return false, false, err
	}
	return val == "1", true, nil
}

// SetUserBlocked sets the blocked status in cache
func (s *CacheService) SetUserBlocked(ctx context.Context, blockerID, blockedID string, isBlocked bool) error {
	key := s.BlockedUserKey(blockerID, blockedID)
	val := "0"
	if isBlocked {
		val = "1"
	}
	return s.redis.Client.Set(ctx, key, val, 1*time.Hour).Err()
}

// RoomParticipantsKey generates the key for room participants
func (s *CacheService) RoomParticipantsKey(roomID string) string {
	return fmt.Sprintf("room_participants:%s", roomID)
}

// GetRoomParticipants gets room participants from cache
// Returns (participants, foundInCache, error)
func (s *CacheService) GetRoomParticipants(ctx context.Context, roomID string) ([]string, bool, error) {
	key := s.RoomParticipantsKey(roomID)
	// Check if key exists first? Or just SMEMBERS.
	// If key doesn't exist, SMEMBERS returns empty list.
	// But empty list could mean "no participants" (unlikely) or "not cached".
	// We can use EXISTS.
	exists, err := s.redis.Client.Exists(ctx, key).Result()
	if err != nil {
		return nil, false, err
	}
	if exists == 0 {
		return nil, false, nil
	}

	members, err := s.redis.Client.SMembers(ctx, key).Result()
	if err != nil {
		return nil, false, err
	}
	return members, true, nil
}

// SetRoomParticipants sets the room participants in cache
func (s *CacheService) SetRoomParticipants(ctx context.Context, roomID string, userIDs []string) error {
	key := s.RoomParticipantsKey(roomID)
	pipe := s.redis.Client.Pipeline()
	pipe.Del(ctx, key)
	if len(userIDs) > 0 {
		// Convert []string to []interface{}
		members := make([]interface{}, len(userIDs))
		for i, v := range userIDs {
			members[i] = v
		}
		pipe.SAdd(ctx, key, members...)
		pipe.Expire(ctx, key, 1*time.Hour)
	}
	_, err := pipe.Exec(ctx)
	return err
}

// CheckRateLimit checks if a user has exceeded the rate limit
// Returns true if allowed, false if limit exceeded
func (s *CacheService) CheckRateLimit(ctx context.Context, userID string, limit int, window time.Duration) (bool, error) {
	key := fmt.Sprintf("rate_limit:%s", userID)
	count, err := s.redis.Client.Incr(ctx, key).Result()
	if err != nil {
		return false, err
	}
	if count == 1 {
		s.redis.Client.Expire(ctx, key, window)
	}
	return count <= int64(limit), nil
}
