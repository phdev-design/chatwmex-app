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

// Feature: linked-devices, Property 15: 取消連結後金鑰重新分發

// recordingNotifier records all SendNotification calls for verification.
type recordingNotifier struct {
	mu    sync.Mutex
	calls []notificationCall
}

type notificationCall struct {
	targetID string
	event    string
	data     interface{}
}

func newRecordingNotifier() *recordingNotifier {
	return &recordingNotifier{}
}

func (n *recordingNotifier) SendNotification(targetID, event string, data interface{}) {
	n.mu.Lock()
	defer n.mu.Unlock()
	n.calls = append(n.calls, notificationCall{
		targetID: targetID,
		event:    event,
		data:     data,
	})
}

func (n *recordingNotifier) getCalls() []notificationCall {
	n.mu.Lock()
	defer n.mu.Unlock()
	result := make([]notificationCall, len(n.calls))
	copy(result, n.calls)
	return result
}

// Validates: Requirements 5.6
// Property 15: 取消連結後金鑰重新分發 — For any 取消連結操作，若使用者仍有其餘已連結裝置，
// 主裝置應為每個剩餘裝置產生並分發新的 Session Key。
//
// This test verifies that after unlinking a device, DeliverSessionKey can be
// successfully called for every remaining linked device, and that each remaining
// device receives the session_key_delivery notification.
func TestProperty15_SessionKeyRedistributionAfterUnlink(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"After unlinking a device with remaining devices, session key delivery succeeds for each remaining device",
		prop.ForAll(
			func(totalDevices int, unlinkIdx int) bool {
				// totalDevices is 2-4 (need at least 2 so there are remaining devices after unlink)
				unlinkIdx = unlinkIdx % totalDevices

				repo := newInMemoryLinkedDeviceRepo()
				notifier := newRecordingNotifier()
				uc := NewLinkedDeviceUsecase(repo, notifier, 5*time.Second)
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

				// Verify the unlinked device is removed.
				remaining, err := uc.GetLinkedDevices(ctx, userID)
				if err != nil {
					t.Logf("GetLinkedDevices failed: %v", err)
					return false
				}
				if len(remaining) != totalDevices-1 {
					t.Logf("Expected %d remaining devices, got %d", totalDevices-1, len(remaining))
					return false
				}

				// Simulate the primary device redistributing session keys to all
				// remaining devices (as required by Requirement 5.6).
				// DeliverSessionKey must succeed for each remaining device.
				for _, dev := range remaining {
					encryptedKey := fmt.Sprintf("new-encrypted-session-key-for-%s", dev.ID)
					senderPublicKey := "primary-device-public-key"
					err := uc.DeliverSessionKey(ctx, userID, dev.ID, encryptedKey, senderPublicKey)
					if err != nil {
						t.Logf("DeliverSessionKey failed for device %s: %v", dev.ID, err)
						return false
					}
				}

				// Verify that session_key_delivery notifications were sent to
				// each remaining device.
				calls := notifier.getCalls()

				// Filter for session_key_delivery events only.
				sessionKeyCalls := make(map[string]bool)
				for _, call := range calls {
					if call.event == "session_key_delivery" {
						sessionKeyCalls[call.targetID] = true
					}
				}

				// Every remaining device must have received a session_key_delivery.
				for _, dev := range remaining {
					if !sessionKeyCalls[dev.ID] {
						t.Logf("Device %s did not receive session_key_delivery", dev.ID)
						return false
					}
				}

				// The unlinked device must NOT have received a session_key_delivery.
				if sessionKeyCalls[unlinkDeviceID] {
					t.Logf("Unlinked device %s should not receive session_key_delivery", unlinkDeviceID)
					return false
				}

				// The number of session_key_delivery calls must equal the number
				// of remaining devices.
				if len(sessionKeyCalls) != len(remaining) {
					t.Logf("Expected %d session_key_delivery calls, got %d", len(remaining), len(sessionKeyCalls))
					return false
				}

				return true
			},
			gen.IntRange(2, 4), // totalDevices: 2 to 4 (need at least 2 for remaining devices)
			gen.IntRange(0, 3), // unlinkIdx: index of device to unlink
		),
	)

	properties.TestingRun(t)
}
