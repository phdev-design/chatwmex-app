package infrastructure

import (
	"context"
	"fmt"
	"time"

	"chatwmex_backend/internal/config"

	"github.com/redis/go-redis/v9"
)

// NewRedisClient establishes a connection to Redis and returns the client instance.
func NewRedisClient(cfg *config.Config) (*redis.Client, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
		DB:       0, // use default DB
	})

	// Ping the server
	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to ping Redis: %w", err)
	}

	fmt.Println("Connected to Redis successfully")

	return client, nil
}
