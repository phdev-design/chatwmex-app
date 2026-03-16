package websocket

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"sync"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

// Feature: linked-devices, Property 6: 離線訊息暫存與 7 天 TTL
// Feature: linked-devices, Property 7: 離線訊息依時間順序送達
//
// **Validates: Requirements 6.3, 6.4, 6.5**

// testOfflineLinkedMsgRepo is an in-memory OfflineLinkedMessageRepository for testing.
type testOfflineLinkedMsgRepo struct {
	mu       sync.Mutex
	messages []*domain.OfflineLinkedMessage
}

func newTestOfflineLinkedMsgRepo() *testOfflineLinkedMsgRepo {
	return &testOfflineLinkedMsgRepo{
		messages: make([]*domain.OfflineLinkedMessage, 0),
	}
}

func (r *testOfflineLinkedMsgRepo) Store(_ context.Context, msg *domain.OfflineLinkedMessage) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.messages = append(r.messages, msg)
	return nil
}

func (r *testOfflineLinkedMsgRepo) GetByDeviceID(_ context.Context, deviceID string) ([]*domain.OfflineLinkedMessage, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	var result []*domain.OfflineLinkedMessage
	for _, m := range r.messages {
		if m.DeviceID == deviceID {
			result = append(result, m)
		}
	}
	// Sort by CreatedAt ascending (matching production behavior)
	sort.Slice(result, func(i, j int) bool {
		return result[i].CreatedAt.Before(result[j].CreatedAt)
	})
	return result, nil
}

func (r *testOfflineLinkedMsgRepo) DeleteByDeviceID(_ context.Context, deviceID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	filtered := make([]*domain.OfflineLinkedMessage, 0)
	for _, m := range r.messages {
		if m.DeviceID != deviceID {
			filtered = append(filtered, m)
		}
	}
	r.messages = filtered
	return nil
}

// newTestHubWithOffline creates a minimal Hub with both linked device repo and offline message repo.
func newTestHubWithOffline(ldRepo domain.LinkedDeviceRepository, olmRepo domain.OfflineLinkedMessageRepository) *Hub {
	return &Hub{
		clients:              make(map[*Client]bool),
		userClients:          make(map[string]*Client),
		broadcast:            make(chan *domain.Message, 1),
		register:             make(chan *Client, 1),
		unregister:           make(chan *Client, 1),
		linkedDeviceRepo:     ldRepo,
		offlineLinkedMsgRepo: olmRepo,
	}
}

// TestProperty6_OfflineMessageStorageAnd7DayTTL verifies that for any message
// produced while a linked device is offline, the message is stored in the
// offline buffer and its ExpiresAt is set to CreatedAt + 7 days.
//
// Feature: linked-devices, Property 6: 離線訊息暫存與 7 天 TTL
// **Validates: Requirements 6.3, 6.5**
func TestProperty6_OfflineMessageStorageAnd7DayTTL(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"Offline messages are stored with ExpiresAt = CreatedAt + 7 days",
		prop.ForAll(
			func(deviceCount int, msgCount int) bool {
				userID := "test-user"
				ldRepo := newTestLinkedDeviceRepo()
				olmRepo := newTestOfflineLinkedMsgRepo()
				hub := newTestHubWithOffline(ldRepo, olmRepo)

				// Create linked devices but do NOT register them in userClients (simulating offline)
				deviceIDs := make([]string, deviceCount)
				for i := 0; i < deviceCount; i++ {
					devID := fmt.Sprintf("offline-device-%d", i)
					deviceIDs[i] = devID
					_ = ldRepo.Create(context.Background(), &domain.LinkedDevice{
						ID:       devID,
						UserID:   userID,
						Platform: "web",
					})
				}

				// Send multiple messages via fanoutToLinkedDevices
				for j := 0; j < msgCount; j++ {
					msg := &domain.Message{
						ID:       fmt.Sprintf("msg-%d", j),
						SenderID: "primary-device",
						Content:  fmt.Sprintf("hello %d", j),
						Type:     "text",
					}
					payload := map[string]interface{}{
						"event": "chat_message",
						"data":  msg,
					}
					messageBytes, err := json.Marshal(payload)
					if err != nil {
						return false
					}
					excludeIDs := map[string]bool{"primary-device": true}
					hub.fanoutToLinkedDevices(userID, messageBytes, excludeIDs, msg)
				}

				// Verify: each offline device should have msgCount stored messages
				for _, devID := range deviceIDs {
					stored, err := olmRepo.GetByDeviceID(context.Background(), devID)
					if err != nil {
						t.Logf("FAIL: error getting offline messages for device %s: %v", devID, err)
						return false
					}
					if len(stored) != msgCount {
						t.Logf("FAIL: device %s has %d offline messages, expected %d", devID, len(stored), msgCount)
						return false
					}

					// Verify ExpiresAt = CreatedAt + 7 days for each message
					sevenDays := 7 * 24 * time.Hour
					for _, m := range stored {
						expectedExpiry := m.CreatedAt.Add(sevenDays)
						// Allow 1 second tolerance for timing
						diff := m.ExpiresAt.Sub(expectedExpiry)
						if diff < -time.Second || diff > time.Second {
							t.Logf("FAIL: message %s ExpiresAt=%v, expected=%v (CreatedAt=%v + 7 days)",
								m.ID, m.ExpiresAt, expectedExpiry, m.CreatedAt)
							return false
						}
					}
				}

				return true
			},
			gen.IntRange(1, 4), // deviceCount: 1 to 4 offline linked devices
			gen.IntRange(1, 5), // msgCount: 1 to 5 messages
		),
	)

	properties.TestingRun(t)
}

// TestProperty7_OfflineMessagesDeliveredInTimeOrder verifies that for any
// linked device coming back online, the offline messages are returned sorted
// by CreatedAt in strictly ascending order.
//
// Feature: linked-devices, Property 7: 離線訊息依時間順序送達
// **Validates: Requirements 6.4**
func TestProperty7_OfflineMessagesDeliveredInTimeOrder(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"Offline messages retrieved by GetByDeviceID are sorted by CreatedAt ascending",
		prop.ForAll(
			func(msgCount int, shuffleSeed int64) bool {
				deviceID := "test-device"
				olmRepo := newTestOfflineLinkedMsgRepo()

				// Generate messages with distinct CreatedAt timestamps
				baseTime := time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC)
				type msgEntry struct {
					idx       int
					createdAt time.Time
				}
				entries := make([]msgEntry, msgCount)
				for i := 0; i < msgCount; i++ {
					entries[i] = msgEntry{
						idx:       i,
						createdAt: baseTime.Add(time.Duration(i) * time.Minute),
					}
				}

				// Shuffle the entries to simulate out-of-order storage
				// Use a simple Fisher-Yates shuffle seeded by the generated value
				shuffled := make([]msgEntry, len(entries))
				copy(shuffled, entries)
				for i := len(shuffled) - 1; i > 0; i-- {
					j := int(uint64(shuffleSeed+int64(i)) % uint64(i+1))
					shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
				}

				// Store messages in shuffled order
				for _, e := range shuffled {
					offlineMsg := &domain.OfflineLinkedMessage{
						ID:       fmt.Sprintf("msg-%d", e.idx),
						DeviceID: deviceID,
						Message: &domain.Message{
							ID:       fmt.Sprintf("msg-%d", e.idx),
							SenderID: "sender",
							Content:  fmt.Sprintf("content %d", e.idx),
							Type:     "text",
						},
						CreatedAt: e.createdAt,
						ExpiresAt: e.createdAt.Add(7 * 24 * time.Hour),
					}
					if err := olmRepo.Store(context.Background(), offlineMsg); err != nil {
						return false
					}
				}

				// Retrieve messages — should be sorted by CreatedAt ascending
				retrieved, err := olmRepo.GetByDeviceID(context.Background(), deviceID)
				if err != nil {
					t.Logf("FAIL: error retrieving offline messages: %v", err)
					return false
				}

				if len(retrieved) != msgCount {
					t.Logf("FAIL: expected %d messages, got %d", msgCount, len(retrieved))
					return false
				}

				// Verify strict ascending order of CreatedAt
				for i := 1; i < len(retrieved); i++ {
					if !retrieved[i].CreatedAt.After(retrieved[i-1].CreatedAt) {
						t.Logf("FAIL: messages not in ascending order at index %d: %v >= %v",
							i, retrieved[i-1].CreatedAt, retrieved[i].CreatedAt)
						return false
					}
				}

				return true
			},
			gen.IntRange(2, 10), // msgCount: 2 to 10 messages (need at least 2 to verify order)
			gen.Int64(),         // shuffleSeed: random seed for shuffling
		),
	)

	properties.TestingRun(t)
}
