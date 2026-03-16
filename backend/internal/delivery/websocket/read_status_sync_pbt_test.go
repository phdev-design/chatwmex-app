package websocket

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
)

// Feature: linked-devices, Property 9: 已讀狀態同步至所有裝置
//
// **Validates: Requirements 6.6**
//
// Property 9: For any user marking a message as read on any device,
// all other linked devices should receive the read status.

// TestProperty9_ReadStatusSyncToAllDevices verifies that when a user marks a
// message as read on any device, the read_status_sync event is broadcast to
// the primary device and all linked devices.
//
// Feature: linked-devices, Property 9: 已讀狀態同步至所有裝置
// **Validates: Requirements 6.6**
func TestProperty9_ReadStatusSyncToAllDevices(t *testing.T) {
	parameters := gopter.DefaultTestParameters()
	parameters.MinSuccessfulTests = 100
	parameters.Rng.Seed(time.Now().UnixNano())
	properties := gopter.NewProperties(parameters)

	properties.Property(
		"Read status sync is broadcast to primary device and all linked devices",
		prop.ForAll(
			func(linkedDeviceCount int, roomIdx int) bool {
				userID := "test-user"
				roomID := fmt.Sprintf("room-%d", roomIdx)
				lastReadAt := time.Now().UTC().Truncate(time.Second)

				repo := newTestLinkedDeviceRepo()
				hub := newTestHub(repo)

				// Register the primary device client
				primarySend := make(chan []byte, 16)
				primaryClient := &Client{
					hub:    hub,
					send:   primarySend,
					userID: userID,
				}
				hub.clients[primaryClient] = true
				hub.userClients[userID] = primaryClient

				// Create linked devices and register clients for each
				type deviceInfo struct {
					id     string
					client *Client
					send   chan []byte
				}
				linkedDevices := make([]deviceInfo, linkedDeviceCount)

				for i := 0; i < linkedDeviceCount; i++ {
					devID := fmt.Sprintf("linked-device-%d", i)
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

					linkedDevices[i] = deviceInfo{
						id:     devID,
						client: client,
						send:   sendCh,
					}
				}

				// Call BroadcastReadStatusSync
				hub.BroadcastReadStatusSync(userID, roomID, lastReadAt)

				// Build expected payload for comparison
				expectedData := map[string]interface{}{
					"room_id":      roomID,
					"user_id":      userID,
					"last_read_at": lastReadAt.Format(time.RFC3339),
				}
				expectedResp := map[string]interface{}{
					"event": "read_status_sync",
					"data":  expectedData,
				}
				expectedBytes, err := json.Marshal(expectedResp)
				if err != nil {
					return false
				}

				// Verify: primary device should receive the read status sync
				primaryMsgs := collectFromChannel(primarySend)
				if len(primaryMsgs) != 1 {
					t.Logf("FAIL: primary device received %d messages, expected 1", len(primaryMsgs))
					return false
				}
				if string(primaryMsgs[0]) != string(expectedBytes) {
					t.Logf("FAIL: primary device received different content")
					return false
				}

				// Verify: all linked devices should receive the read status sync
				for _, dev := range linkedDevices {
					received := collectFromChannel(dev.send)
					if len(received) != 1 {
						t.Logf("FAIL: linked device %s received %d messages, expected 1", dev.id, len(received))
						return false
					}
					if string(received[0]) != string(expectedBytes) {
						t.Logf("FAIL: linked device %s received different content", dev.id)
						return false
					}
				}

				return true
			},
			gen.IntRange(1, 4), // linkedDeviceCount: 1 to 4 linked devices
			gen.IntRange(1, 100), // roomIdx: generates different room IDs
		),
	)

	properties.TestingRun(t)
}
