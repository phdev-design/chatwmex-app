package usecase

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

// Feature: linked-devices, Property 1: 裝置數量上限不變量

// inMemoryLinkedDeviceRepo is a stateful in-memory implementation of
// domain.LinkedDeviceRepository used for property-based testing.
type inMemoryLinkedDeviceRepo struct {
	mu      sync.Mutex
	devices map[string]*domain.LinkedDevice // keyed by device ID
}

func newInMemoryLinkedDeviceRepo() *inMemoryLinkedDeviceRepo {
	return &inMemoryLinkedDeviceRepo{
		devices: make(map[string]*domain.LinkedDevice),
	}
}

func (r *inMemoryLinkedDeviceRepo) Create(_ context.Context, device *domain.LinkedDevice) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.devices[device.ID] = device
	return nil
}

func (r *inMemoryLinkedDeviceRepo) Delete(_ context.Context, deviceID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.devices, deviceID)
	return nil
}

func (r *inMemoryLinkedDeviceRepo) DeleteByUserID(_ context.Context, userID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for id, d := range r.devices {
		if d.UserID == userID {
			delete(r.devices, id)
		}
	}
	return nil
}

func (r *inMemoryLinkedDeviceRepo) GetByID(_ context.Context, deviceID string) (*domain.LinkedDevice, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	d, ok := r.devices[deviceID]
	if !ok {
		return nil, nil
	}
	return d, nil
}

func (r *inMemoryLinkedDeviceRepo) GetByUserID(_ context.Context, userID string) ([]*domain.LinkedDevice, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	var result []*domain.LinkedDevice
	for _, d := range r.devices {
		if d.UserID == userID {
			result = append(result, d)
		}
	}
	return result, nil
}

func (r *inMemoryLinkedDeviceRepo) CountByUserID(_ context.Context, userID string) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	count := 0
	for _, d := range r.devices {
		if d.UserID == userID {
			count++
		}
	}
	return count, nil
}

func (r *inMemoryLinkedDeviceRepo) UpdateLastActive(_ context.Context, _ string) error {
	return nil
}

// noopNotifier is a no-op WebSocketNotifier for testing.
type noopNotifier struct{}

func (n *noopNotifier) SendNotification(_, _ string, _ interface{}) {}

// Validates: Requirements 2.6
// Property 1: 裝置數量上限不變量 — For any 使用者，其已連結裝置數量在任何操作後都不應超過 4 台。
func TestProperty1_MaxLinkedDevicesInvariant(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	// Generator: initial device count from 0 to MaxLinkedDevices (valid states only,
	// since devices can only be added through LinkDevice which enforces the limit)
	// and a number of additional LinkDevice attempts from 1 to 8.
	properties.Property(
		"After any sequence of LinkDevice calls, device count never exceeds MaxLinkedDevices",
		prop.ForAll(
			func(initialCount int, attempts int) bool {
				repo := newInMemoryLinkedDeviceRepo()
				uc := NewLinkedDeviceUsecase(repo, &noopNotifier{}, 5*time.Second)
				ctx := context.Background()
				userID := "test-user"

				// Seed the repo with initialCount existing devices for this user.
				// These represent devices previously linked through the usecase.
				for i := 0; i < initialCount; i++ {
					_ = repo.Create(ctx, &domain.LinkedDevice{
						ID:       fmt.Sprintf("existing-%d", i),
						UserID:   userID,
						Platform: "web",
					})
				}

				// Attempt to link additional devices via the usecase.
				for i := 0; i < attempts; i++ {
					device := &domain.LinkedDevice{
						ID:         fmt.Sprintf("new-%d", i),
						DeviceName: fmt.Sprintf("Device %d", i),
						Platform:   "web",
						PublicKey:  "test-key",
					}
					err := uc.LinkDevice(ctx, userID, device)

					// After each operation, count must not exceed the limit.
					currentCount, _ := repo.CountByUserID(ctx, userID)
					if currentCount > MaxLinkedDevices {
						return false
					}

					// When at the limit, LinkDevice must return max_devices_reached.
					if err != nil && err.Error() != "max_devices_reached" {
						return false
					}
				}

				// Final invariant: count must never exceed MaxLinkedDevices.
				finalCount, _ := repo.CountByUserID(ctx, userID)
				return finalCount <= MaxLinkedDevices
			},
			gen.IntRange(0, MaxLinkedDevices), // initialCount: valid states 0..4
			gen.IntRange(1, 8),                // attempts: 1 to 8 additional link attempts
		),
	)

	properties.TestingRun(t)
}

// Feature: linked-devices, Property 11: 登出級聯取消所有連結

// Validates: Requirements 8.5
// Property 11: 登出級聯取消所有連結 — For any 使用者登出後，GetLinkedDevices 應回傳空清單。
func TestProperty11_LogoutCascadeUnlinksAllDevices(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	// Generator: random number of linked devices (0-4) for a user.
	properties.Property(
		"After UnlinkAllDevices, GetLinkedDevices returns an empty list",
		prop.ForAll(
			func(deviceCount int) bool {
				repo := newInMemoryLinkedDeviceRepo()
				uc := NewLinkedDeviceUsecase(repo, &noopNotifier{}, 5*time.Second)
				ctx := context.Background()
				userID := "logout-user"

				// Seed the repo with deviceCount linked devices for this user.
				for i := 0; i < deviceCount; i++ {
					_ = repo.Create(ctx, &domain.LinkedDevice{
						ID:           fmt.Sprintf("device-%d", i),
						UserID:       userID,
						DeviceName:   fmt.Sprintf("Web Device %d", i),
						Platform:     "web",
						PublicKey:    "test-key",
						LinkedAt:     time.Now(),
						LastActiveAt: time.Now(),
						ExpiresAt:    time.Now().Add(30 * 24 * time.Hour),
					})
				}

				// Simulate logout: call UnlinkAllDevices.
				err := uc.UnlinkAllDevices(ctx, userID)
				if err != nil {
					return false
				}

				// After logout, GetLinkedDevices should return an empty list.
				devices, err := uc.GetLinkedDevices(ctx, userID)
				if err != nil {
					return false
				}

				return len(devices) == 0
			},
			gen.IntRange(0, 4), // deviceCount: 0 to MaxLinkedDevices
		),
	)

	properties.TestingRun(t)
}


// Feature: linked-devices, Property 14: 連結成功建立裝置記錄

// Validates: Requirements 4.1, 4.6
// Property 14: 連結成功建立裝置記錄 — For any 成功連結，應建立包含所有必要欄位的 LinkedDevice 記錄，ExpiresAt 為連結時間加 30 天。
func TestProperty14_LinkDeviceCreatesCompleteRecord(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"LinkDevice creates a LinkedDevice record with all required fields and ExpiresAt = LinkedAt + 30 days",
		prop.ForAll(
			func(deviceID string, userID string, deviceName string, publicKey string) bool {
				repo := newInMemoryLinkedDeviceRepo()
				uc := NewLinkedDeviceUsecase(repo, &noopNotifier{}, 5*time.Second)
				ctx := context.Background()

				beforeLink := time.Now()

				device := &domain.LinkedDevice{
					ID:         deviceID,
					DeviceName: deviceName,
					Platform:   "web",
					PublicKey:  publicKey,
				}

				err := uc.LinkDevice(ctx, userID, device)
				if err != nil {
					t.Logf("LinkDevice failed unexpectedly: %v", err)
					return false
				}

				afterLink := time.Now()

				// Retrieve the stored device record.
				stored, err := repo.GetByID(ctx, deviceID)
				if err != nil || stored == nil {
					return false
				}

				// Verify all required fields are populated.
				if stored.ID != deviceID {
					return false
				}
				if stored.UserID != userID {
					return false
				}
				if stored.Platform != "web" {
					return false
				}

				// LinkedAt should be between beforeLink and afterLink.
				if stored.LinkedAt.Before(beforeLink) || stored.LinkedAt.After(afterLink) {
					return false
				}

				// LastActiveAt should be between beforeLink and afterLink.
				if stored.LastActiveAt.Before(beforeLink) || stored.LastActiveAt.After(afterLink) {
					return false
				}

				// ExpiresAt must be exactly LinkedAt + 30 days.
				expected := stored.LinkedAt.Add(30 * 24 * time.Hour)
				if !stored.ExpiresAt.Equal(expected) {
					return false
				}

				return true
			},
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),
		),
	)

	properties.TestingRun(t)
}

