package redis_repo

import (
	"context"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupTestRedis(t *testing.T) (*miniredis.Miniredis, domain.AuthRepository) {
	t.Helper()
	mr := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	repo := NewAuthRepository(client)
	return mr, repo
}

func TestSaveQRTokenWithPublicKey(t *testing.T) {
	mr, repo := setupTestRedis(t)
	ctx := context.Background()

	err := repo.SaveQRTokenWithPublicKey(ctx, "tok123", "pubkey-abc", 3*time.Minute)
	require.NoError(t, err)

	// Verify hash fields stored correctly.
	key := qrTokenPrefix + "tok123"
	assert.True(t, mr.Exists(key))
	vals := mr.HGet(key, "web_public_key")
	assert.Equal(t, "pubkey-abc", vals)
	assert.Equal(t, "false", mr.HGet(key, "used"))
	assert.Equal(t, string(domain.QRTokenPending), mr.HGet(key, "status"))
	assert.NotEmpty(t, mr.HGet(key, "created_at"))
}

func TestGetQRTokenDetail(t *testing.T) {
	_, repo := setupTestRedis(t)
	ctx := context.Background()

	err := repo.SaveQRTokenWithPublicKey(ctx, "tok456", "pubkey-xyz", 3*time.Minute)
	require.NoError(t, err)

	detail, err := repo.GetQRTokenDetail(ctx, "tok456")
	require.NoError(t, err)
	assert.Equal(t, "tok456", detail.Token)
	assert.Equal(t, domain.QRTokenPending, detail.Status)
	assert.Equal(t, "pubkey-xyz", detail.WebPublicKey)
	assert.False(t, detail.Used)
	assert.False(t, detail.CreatedAt.IsZero())
}

func TestGetQRTokenDetail_NotFound(t *testing.T) {
	_, repo := setupTestRedis(t)
	ctx := context.Background()

	detail, err := repo.GetQRTokenDetail(ctx, "nonexistent")
	assert.Error(t, err)
	assert.Nil(t, detail)
}

func TestMarkQRTokenUsed(t *testing.T) {
	_, repo := setupTestRedis(t)
	ctx := context.Background()

	err := repo.SaveQRTokenWithPublicKey(ctx, "tok789", "pk", 3*time.Minute)
	require.NoError(t, err)

	err = repo.MarkQRTokenUsed(ctx, "tok789")
	require.NoError(t, err)

	detail, err := repo.GetQRTokenDetail(ctx, "tok789")
	require.NoError(t, err)
	assert.True(t, detail.Used)
}

func TestMarkQRTokenUsed_NotFound(t *testing.T) {
	_, repo := setupTestRedis(t)
	ctx := context.Background()

	err := repo.MarkQRTokenUsed(ctx, "nonexistent")
	assert.Error(t, err)
}

func TestIncrementLinkFailure(t *testing.T) {
	_, repo := setupTestRedis(t)
	ctx := context.Background()

	count, err := repo.IncrementLinkFailure(ctx, "user1")
	require.NoError(t, err)
	assert.Equal(t, 1, count)

	count, err = repo.IncrementLinkFailure(ctx, "user1")
	require.NoError(t, err)
	assert.Equal(t, 2, count)
}

func TestIsLinkBlocked_NotBlocked(t *testing.T) {
	_, repo := setupTestRedis(t)
	ctx := context.Background()

	blocked, err := repo.IsLinkBlocked(ctx, "user1")
	require.NoError(t, err)
	assert.False(t, blocked)
}

func TestBlockLinkAttempts(t *testing.T) {
	_, repo := setupTestRedis(t)
	ctx := context.Background()

	err := repo.BlockLinkAttempts(ctx, "user1")
	require.NoError(t, err)

	blocked, err := repo.IsLinkBlocked(ctx, "user1")
	require.NoError(t, err)
	assert.True(t, blocked)
}
