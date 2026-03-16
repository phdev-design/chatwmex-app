package usecase

import (
	"context"
	"sync"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

// Feature: linked-devices, Property 2: QR Token 一次性使用
// Feature: linked-devices, Property 3: 過期 QR Token 拒絕確認

// inMemoryAuthRepo is a stateful in-memory implementation of
// domain.AuthRepository used for property-based testing of auth usecase.
type inMemoryAuthRepo struct {
	mu     sync.Mutex
	tokens map[string]*domain.QRTokenDetail

	failureCounts map[string]int
	blocked       map[string]bool
}

func newInMemoryAuthRepo() *inMemoryAuthRepo {
	return &inMemoryAuthRepo{
		tokens:        make(map[string]*domain.QRTokenDetail),
		failureCounts: make(map[string]int),
		blocked:       make(map[string]bool),
	}
}

func (r *inMemoryAuthRepo) SaveQRToken(_ context.Context, token string, _ time.Duration) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.tokens[token] = &domain.QRTokenDetail{
		Token:     token,
		Status:    domain.QRTokenPending,
		Used:      false,
		CreatedAt: time.Now(),
	}
	return nil
}

func (r *inMemoryAuthRepo) ConfirmQRToken(_ context.Context, token, userID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	d, ok := r.tokens[token]
	if !ok {
		return nil
	}
	d.Status = domain.QRTokenConfirmed
	d.UserID = userID
	return nil
}

func (r *inMemoryAuthRepo) GetQRTokenStatus(_ context.Context, token string) (domain.QRTokenStatus, string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	d, ok := r.tokens[token]
	if !ok {
		return "", "", nil
	}
	return d.Status, d.UserID, nil
}

func (r *inMemoryAuthRepo) SaveQRTokenWithPublicKey(_ context.Context, token, webPublicKey string, _ time.Duration) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.tokens[token] = &domain.QRTokenDetail{
		Token:        token,
		Status:       domain.QRTokenPending,
		Used:         false,
		WebPublicKey: webPublicKey,
		CreatedAt:    time.Now(),
	}
	return nil
}

func (r *inMemoryAuthRepo) GetQRTokenDetail(_ context.Context, token string) (*domain.QRTokenDetail, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	d, ok := r.tokens[token]
	if !ok {
		return nil, nil
	}
	// Return a copy to avoid data races
	cp := *d
	return &cp, nil
}

func (r *inMemoryAuthRepo) MarkQRTokenUsed(_ context.Context, token string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	d, ok := r.tokens[token]
	if !ok {
		return nil
	}
	d.Used = true
	return nil
}

func (r *inMemoryAuthRepo) IncrementLinkFailure(_ context.Context, userID string) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.failureCounts[userID]++
	return r.failureCounts[userID], nil
}

func (r *inMemoryAuthRepo) IsLinkBlocked(_ context.Context, userID string) (bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.blocked[userID], nil
}

func (r *inMemoryAuthRepo) BlockLinkAttempts(_ context.Context, userID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.blocked[userID] = true
	return nil
}

// seedToken creates a QR token in the in-memory repo with a specific creation time.
func (r *inMemoryAuthRepo) seedToken(token string, createdAt time.Time) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.tokens[token] = &domain.QRTokenDetail{
		Token:        token,
		Status:       domain.QRTokenPending,
		Used:         false,
		WebPublicKey: "test-pub-key",
		CreatedAt:    createdAt,
	}
}

// stubLinkedDeviceUsecase is a minimal stub that always succeeds for LinkDevice.
type stubLinkedDeviceUsecase struct{}

func (s *stubLinkedDeviceUsecase) LinkDevice(_ context.Context, _ string, _ *domain.LinkedDevice) error {
	return nil
}
func (s *stubLinkedDeviceUsecase) UnlinkDevice(_ context.Context, _, _ string) error { return nil }
func (s *stubLinkedDeviceUsecase) UnlinkAllDevices(_ context.Context, _ string) error { return nil }
func (s *stubLinkedDeviceUsecase) GetLinkedDevices(_ context.Context, _ string) ([]*domain.LinkedDevice, error) {
	return nil, nil
}
func (s *stubLinkedDeviceUsecase) GetLinkedDeviceCount(_ context.Context, _ string) (int, error) {
	return 0, nil
}
func (s *stubLinkedDeviceUsecase) DeliverSessionKey(_ context.Context, _, _, _, _ string) error {
	return nil
}

// Validates: Requirements 3.7, 8.1
// Property 2: QR Token 一次性使用 — For any QR Token，被成功確認使用一次後，後續確認請求都應回傳錯誤。
func TestProperty2_QRTokenOneTimeUse(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"After ConfirmQRToken succeeds once, subsequent calls with the same token must fail with qr_token_already_used",
		prop.ForAll(
			func(token string, userID string) bool {
				repo := newInMemoryAuthRepo()
				ldStub := &stubLinkedDeviceUsecase{}
				uc := NewAuthUsecase(repo, ldStub, 5*time.Second)
				ctx := context.Background()

				// Seed a fresh, valid (not expired, not used) QR token.
				repo.seedToken(token, time.Now())

				// First call should succeed.
				_, err := uc.ConfirmQRToken(ctx, token, userID)
				if err != nil {
					// If the first call fails, the property is vacuously true
					// (we can't test one-time-use if the first use didn't succeed).
					// This shouldn't happen with our setup, so flag it.
					t.Logf("unexpected first-call failure for token=%q user=%q: %v", token, userID, err)
					return false
				}

				// Second call with the same token must fail.
				_, err2 := uc.ConfirmQRToken(ctx, token, userID)
				if err2 == nil {
					return false
				}
				return err2.Error() == "qr_token_already_used"
			},
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),
		),
	)

	properties.TestingRun(t)
}

// Validates: Requirements 3.6
// Property 3: 過期 QR Token 拒絕確認 — For any 已過期的 QR Token，確認請求應回傳錯誤。
func TestProperty3_ExpiredQRTokenRejected(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"ConfirmQRToken must fail with qr_token_expired for any token created more than 3 minutes ago",
		prop.ForAll(
			func(token string, userID string, extraSeconds int) bool {
				repo := newInMemoryAuthRepo()
				ldStub := &stubLinkedDeviceUsecase{}
				uc := NewAuthUsecase(repo, ldStub, 5*time.Second)
				ctx := context.Background()

				// Seed a token that was created more than 3 minutes ago.
				// extraSeconds is [1..600], so the token is 3m1s to 3m10m old.
				expiredAt := time.Now().Add(-(3*time.Minute + time.Duration(extraSeconds)*time.Second))
				repo.seedToken(token, expiredAt)

				_, err := uc.ConfirmQRToken(ctx, token, userID)
				if err == nil {
					return false
				}
				return err.Error() == "qr_token_expired"
			},
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),
			gen.IntRange(1, 600), // extra seconds past the 3-minute expiry
		),
	)

	properties.TestingRun(t)
}

// Validates: Requirements 8.2
// Property 10: 連結失敗速率限制 — For any 使用者在 5 分鐘內連續失敗 5 次後，後續連結請求應被封鎖 15 分鐘。
func TestProperty10_LinkFailureRateLimiting(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"After 5 consecutive link failures, subsequent ConfirmQRToken calls must return rate_limited",
		prop.ForAll(
			func(userID string) bool {
				repo := newInMemoryAuthRepo()
				ldStub := &stubLinkedDeviceUsecase{}
				uc := NewAuthUsecase(repo, ldStub, 5*time.Second)
				ctx := context.Background()

				// Trigger 5 consecutive failures by using non-existent tokens.
				// Each call with an invalid token increments the failure counter
				// via recordFailure. When the counter reaches maxLinkFailures (5),
				// the user is blocked.
				for i := 0; i < maxLinkFailures; i++ {
					invalidToken := "nonexistent-token-" + userID + "-" + string(rune('0'+i))
					_, err := uc.ConfirmQRToken(ctx, invalidToken, userID)
					if err == nil {
						// Should always fail for a non-existent token
						return false
					}
					if err.Error() == "rate_limited" {
						// Should not be rate-limited before reaching the threshold
						return false
					}
				}

				// The 6th call should be blocked with rate_limited.
				// Seed a valid token to ensure the rate limit check is the
				// reason for rejection, not an invalid token.
				repo.seedToken("valid-token-"+userID, time.Now())
				_, err := uc.ConfirmQRToken(ctx, "valid-token-"+userID, userID)
				if err == nil {
					return false
				}
				return err.Error() == "rate_limited"
			},
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),
		),
	)

	properties.TestingRun(t)
}

