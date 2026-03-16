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

// Feature: linked-devices, Property 12: 裝置清單顯示完整資訊

// Validates: Requirements 2.1
// Property 12: 裝置清單顯示完整資訊 — For any 已連結裝置清單，每個裝置項目的渲染結果
// 應包含裝置名稱、平台類型和最後活躍時間三個欄位。
func TestProperty12_DeviceListDisplaysCompleteInfo(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"Every device returned by GetLinkedDevices has non-empty DeviceName, Platform, and non-zero LastActiveAt",
		prop.ForAll(
			func(deviceCount int, deviceName string, platform string) bool {
				repo := newInMemoryLinkedDeviceRepo()
				uc := NewLinkedDeviceUsecase(repo, &noopNotifier{}, 5*time.Second)
				ctx := context.Background()
				userID := "test-user"

				// Link deviceCount devices via the usecase (which populates all fields).
				for i := 0; i < deviceCount; i++ {
					device := &domain.LinkedDevice{
						ID:         fmt.Sprintf("device-%d", i),
						DeviceName: fmt.Sprintf("%s-%d", deviceName, i),
						Platform:   platform,
						PublicKey:  fmt.Sprintf("key-%d", i),
					}
					err := uc.LinkDevice(ctx, userID, device)
					if err != nil {
						t.Logf("LinkDevice failed: %v", err)
						return false
					}
				}

				// Retrieve the device list via GetLinkedDevices.
				devices, err := uc.GetLinkedDevices(ctx, userID)
				if err != nil {
					t.Logf("GetLinkedDevices failed: %v", err)
					return false
				}

				// Verify the count matches.
				if len(devices) != deviceCount {
					t.Logf("Expected %d devices, got %d", deviceCount, len(devices))
					return false
				}

				// Property: every device must have non-empty DeviceName,
				// non-empty Platform, and non-zero LastActiveAt.
				for _, d := range devices {
					if d.DeviceName == "" {
						t.Logf("Device %s has empty DeviceName", d.ID)
						return false
					}
					if d.Platform == "" {
						t.Logf("Device %s has empty Platform", d.ID)
						return false
					}
					if d.LastActiveAt.IsZero() {
						t.Logf("Device %s has zero LastActiveAt", d.ID)
						return false
					}
				}

				return true
			},
			gen.IntRange(0, MaxLinkedDevices),                                          // deviceCount: 0 to 4
			gen.AlphaString().SuchThat(func(s string) bool { return len(s) > 0 }),     // deviceName: non-empty
			gen.OneConstOf("web", "desktop", "tablet"),                                 // platform: valid platform types
		),
	)

	properties.TestingRun(t)
}
