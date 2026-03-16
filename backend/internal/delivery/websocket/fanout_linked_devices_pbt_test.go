package websocket

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

// Feature: linked-devices, Property 5: 訊息扇出至所有使用者裝置
//
// **Validates: Requirements 6.1, 6.2**
//
// Property 5: For any message sent by any device of a user, the message
// should be forwarded to all other devices of that user.

// testLinkedDeviceRepo is an in-memory LinkedDeviceRepository for testing.
type testLinkedDeviceRepo struct {
	mu      sync.Mutex
	devices map[string]*domain.LinkedDevice
}

func newTestLinkedDeviceRepo() *testLinkedDeviceRepo {
	return &testLinkedDeviceRepo{
		devices: make(map[string]*domain.LinkedDevice),
	}
}

func (r *testLinkedDeviceRepo) Create(_ context.Context, device *domain.LinkedDevice) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.devices[device.ID] = device
	return nil
}

func (r *testLinkedDeviceRepo) Delete(_ context.Context, deviceID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.devices, deviceID)
	return nil
}

func (r *testLinkedDeviceRepo) DeleteByUserID(_ context.Context, userID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for id, d := range r.devices {
		if d.UserID == userID {
			delete(r.devices, id)
		}
	}
	return nil
}

func (r *testLinkedDeviceRepo) GetByID(_ context.Context, deviceID string) (*domain.LinkedDevice, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	d, ok := r.devices[deviceID]
	if !ok {
		return nil, nil
	}
	return d, nil
}

func (r *testLinkedDeviceRepo) GetByUserID(_ context.Context, userID string) ([]*domain.LinkedDevice, error) {
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

func (r *testLinkedDeviceRepo) CountByUserID(_ context.Context, userID string) (int, error) {
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

func (r *testLinkedDeviceRepo) UpdateLastActive(_ context.Context, _ string) error {
	return nil
}

// newTestHub creates a minimal Hub with the given linked device repo and
// pre-registered clients in userClients.
func newTestHub(repo domain.LinkedDeviceRepository) *Hub {
	return &Hub{
		clients:          make(map[*Client]bool),
		userClients:      make(map[string]*Client),
		broadcast:        make(chan *domain.Message, 1),
		register:         make(chan *Client, 1),
		unregister:       make(chan *Client, 1),
		linkedDeviceRepo: repo,
	}
}

// collectFromChannel drains all messages from a buffered channel within a short window.
func collectFromChannel(ch chan []byte) [][]byte {
	var msgs [][]byte
	for {
		select {
		case m := <-ch:
			msgs = append(msgs, m)
		default:
			return msgs
		}
	}
}

// TestProperty5_MessageFanoutToAllUserDevices verifies that for any message
// sent by any device of a user, the message is forwarded to all other devices
// of that user (and NOT to the sending device).
//
// Feature: linked-devices, Property 5: 訊息扇出至所有使用者裝置
// **Validates: Requirements 6.1, 6.2**
func TestProperty5_MessageFanoutToAllUserDevices(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"Message sent by any device is forwarded to all other devices of the same user",
		prop.ForAll(
			func(deviceCount int, senderIdx int) bool {
				// Ensure senderIdx is within range
				senderIdx = senderIdx % deviceCount

				userID := "test-user"
				repo := newTestLinkedDeviceRepo()
				hub := newTestHub(repo)

				// Create linked devices and register clients for each
				type deviceInfo struct {
					id     string
					client *Client
					send   chan []byte
				}
				devices := make([]deviceInfo, deviceCount)

				for i := 0; i < deviceCount; i++ {
					devID := fmt.Sprintf("device-%d", i)
					_ = repo.Create(context.Background(), &domain.LinkedDevice{
						ID:       devID,
						UserID:   userID,
						Platform: "web",
					})

					sendCh := make(chan []byte, 16)
					client := &Client{
						hub:    hub,
						send:   sendCh,
						userID: devID,
					}
					hub.clients[client] = true
					hub.userClients[devID] = client

					devices[i] = deviceInfo{
						id:     devID,
						client: client,
						send:   sendCh,
					}
				}

				// Build the message payload
				msg := &domain.Message{
					ID:       "msg-1",
					SenderID: devices[senderIdx].id,
					Content:  "hello from device",
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

				// Call fanoutToLinkedDevices excluding the sender
				excludeIDs := map[string]bool{devices[senderIdx].id: true}
				hub.fanoutToLinkedDevices(userID, messageBytes, excludeIDs, msg)

				// Verify: all devices except the sender should have received the message
				for i, dev := range devices {
					received := collectFromChannel(dev.send)
					if i == senderIdx {
						// Sender should NOT receive the fanout
						if len(received) != 0 {
							t.Logf("FAIL: sender device %s received %d messages, expected 0", dev.id, len(received))
							return false
						}
					} else {
						// All other devices should receive exactly 1 message
						if len(received) != 1 {
							t.Logf("FAIL: device %s received %d messages, expected 1", dev.id, len(received))
							return false
						}
						// Verify the content matches
						if string(received[0]) != string(messageBytes) {
							t.Logf("FAIL: device %s received different message content", dev.id)
							return false
						}
					}
				}

				return true
			},
			gen.IntRange(1, 4), // deviceCount: 1 to 4 linked devices
			gen.IntRange(0, 3), // senderIdx: index of the sending device
		),
	)

	properties.TestingRun(t)
}
