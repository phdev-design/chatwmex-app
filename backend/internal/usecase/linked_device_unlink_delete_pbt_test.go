package usecase

import (
	"context"
	"fmt"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

// Feature: linked-devices, Property 8: 取消連結刪除裝置記錄

// Validates: Requirements 4.3
// Property 8: 取消連結刪除裝置記錄 — For any 已連結裝置，執行取消連結操作後，
// 該裝置記錄應從資料庫中被刪除，且後續查詢該裝置 ID 應回傳空結果。
func TestProperty8_UnlinkDeviceDeletesRecord(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"After UnlinkDevice, GetByID returns nil and device no longer appears in GetByUserID results",
		prop.ForAll(
			func(totalDevices int, unlinkIdx int) bool {
				unlinkIdx = unlinkIdx % totalDevices

				repo := newInMemoryLinkedDeviceRepo()
				uc := NewLinkedDeviceUsecase(repo, &noopNotifier{}, 5*time.Second)
				ctx := context.Background()
				userID := "test-user"

				// Seed the repo with totalDevices linked devices.
				deviceIDs := make([]string, totalDevices)
				for i := 0; i < totalDevices; i++ {
					devID := fmt.Sprintf("device-%d", i)
					deviceIDs[i] = devID
					_ = repo.Create(ctx, &domain.LinkedDevice{
						ID:           devID,
						UserID:       userID,
						DeviceName:   fmt.Sprintf("Web Device %d", i),
						Platform:     "web",
						PublicKey:    fmt.Sprintf("public-key-%d", i),
						LinkedAt:     time.Now(),
						LastActiveAt: time.Now(),
						ExpiresAt:    time.Now().Add(30 * 24 * time.Hour),
					})
				}

				// Unlink one device.
				unlinkDeviceID := deviceIDs[unlinkIdx]
				err := uc.UnlinkDevice(ctx, userID, unlinkDeviceID)
				if err != nil {
					t.Logf("UnlinkDevice failed: %v", err)
					return false
				}

				// Verify GetByID returns nil for the unlinked device.
				device, err := repo.GetByID(ctx, unlinkDeviceID)
				if err != nil {
					t.Logf("GetByID returned error: %v", err)
					return false
				}
				if device != nil {
					t.Logf("GetByID should return nil for unlinked device %s, got %+v", unlinkDeviceID, device)
					return false
				}

				// Verify the device no longer appears in GetByUserID results.
				remaining, err := repo.GetByUserID(ctx, userID)
				if err != nil {
					t.Logf("GetByUserID returned error: %v", err)
					return false
				}
				for _, d := range remaining {
					if d.ID == unlinkDeviceID {
						t.Logf("Unlinked device %s still appears in GetByUserID results", unlinkDeviceID)
						return false
					}
				}

				// Verify remaining count is totalDevices - 1.
				if len(remaining) != totalDevices-1 {
					t.Logf("Expected %d remaining devices, got %d", totalDevices-1, len(remaining))
					return false
				}

				return true
			},
			gen.IntRange(1, 4), // totalDevices: 1 to 4
			gen.IntRange(0, 3), // unlinkIdx: index of device to unlink
		),
	)

	properties.TestingRun(t)
}
