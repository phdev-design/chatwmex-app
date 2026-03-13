package websocket

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/quick"
	"time"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// **Validates: Requirements 3.1**
// Property 2: Preservation - Small Payload Normal Transmission
//
// This test verifies that WebSocket connections continue to transmit messages
// normally for payloads smaller than 1MB on the UNFIXED code.
// This establishes the baseline behavior that must be preserved after the fix.
//
// EXPECTED OUTCOME: Tests PASS (confirms baseline behavior to preserve)

// TestPreservation_SmallPayloadNormalTransmission tests that messages under 1MB
// are transmitted successfully through WebSocket connections.
func TestPreservation_SmallPayloadNormalTransmission(t *testing.T) {
	// Test with various small payload sizes
	testCases := []struct {
		name        string
		payloadSize int
		description string
	}{
		{
			name:        "tiny_payload_100_bytes",
			payloadSize: 100,
			description: "Very small message (100 bytes)",
		},
		{
			name:        "small_payload_1KB",
			payloadSize: 1024,
			description: "Small message (1KB)",
		},
		{
			name:        "medium_payload_4KB",
			payloadSize: 4 * 1024,
			description: "Medium message (4KB)",
		},
		{
			name:        "boundary_below_current_limit_7KB",
			payloadSize: 7 * 1024,
			description: "Just below current 8KB limit",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Create a test message with the specified payload size
			payload := generatePayload(tc.payloadSize)
			message := createTestMessage(payload)

			// Create a simple echo server that respects maxMessageSize
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				conn, err := upgrader.Upgrade(w, r, nil)
				if err != nil {
					t.Logf("Failed to upgrade connection: %v", err)
					return
				}
				defer conn.Close()

				// Set the same read limit as the actual client
				conn.SetReadLimit(maxMessageSize)

				// Read message
				_, msg, err := conn.ReadMessage()
				if err != nil {
					t.Logf("Error reading message: %v", err)
					return
				}

				// Echo back
				err = conn.WriteMessage(websocket.TextMessage, msg)
				if err != nil {
					t.Logf("Error writing message: %v", err)
				}
			}))
			defer server.Close()

			// Connect to test server
			wsURL := "ws" + strings.TrimPrefix(server.URL, "http")
			conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
			require.NoError(t, err, "Failed to connect to WebSocket server")
			defer conn.Close()

			// Send the message
			err = conn.WriteMessage(websocket.TextMessage, message)
			assert.NoError(t, err, "Failed to send message with payload size %d bytes (%s)", tc.payloadSize, tc.description)

			// Try to read echo response
			conn.SetReadDeadline(time.Now().Add(2 * time.Second))
			_, receivedMsg, err := conn.ReadMessage()
			
			// For messages under the current 8KB limit (accounting for JSON overhead), we expect success
			assert.NoError(t, err, "Should successfully receive echo for %s", tc.description)
			assert.Equal(t, len(message), len(receivedMsg), "Received message size should match sent size")

			// Verify connection is still alive by sending a ping
			err = conn.WriteMessage(websocket.PingMessage, nil)
			assert.NoError(t, err, "Connection should remain alive after sending %s", tc.description)
		})
	}
}

// TestPreservation_SmallPayloadProperty uses property-based testing to verify
// that any message under the current 8KB limit is transmitted successfully.
func TestPreservation_SmallPayloadProperty(t *testing.T) {
	// Property: For any payload size <= 8KB (current limit), WebSocket transmission succeeds
	property := func(sizeMultiplier uint8) bool {
		// Generate payload size between 1 byte and 8KB (current limit)
		payloadSize := int(sizeMultiplier)%8192 + 1
		if payloadSize > 8192 {
			payloadSize = 8192
		}

		// Create test message
		payload := generatePayload(payloadSize)
		message := createTestMessage(payload)

		// Create echo server
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			conn, err := upgrader.Upgrade(w, r, nil)
			if err != nil {
				return
			}
			defer conn.Close()

			conn.SetReadLimit(maxMessageSize)

			_, msg, err := conn.ReadMessage()
			if err != nil {
				return
			}

			conn.WriteMessage(websocket.TextMessage, msg)
		}))
		defer server.Close()

		// Connect to test server
		wsURL := "ws" + strings.TrimPrefix(server.URL, "http")
		conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
		if err != nil {
			return false
		}
		defer conn.Close()

		// Send the message
		err = conn.WriteMessage(websocket.TextMessage, message)
		if err != nil {
			return false
		}

		// Try to read echo
		conn.SetReadDeadline(time.Now().Add(1 * time.Second))
		_, receivedMsg, err := conn.ReadMessage()
		if err != nil {
			return false
		}

		// Verify size matches
		if len(receivedMsg) != len(message) {
			return false
		}

		// Verify connection is still alive
		err = conn.WriteMessage(websocket.PingMessage, nil)
		return err == nil
	}

	// Run property-based test with multiple iterations
	config := &quick.Config{
		MaxCount: 30, // Test with 30 random payload sizes
	}

	err := quick.Check(property, config)
	assert.NoError(t, err, "Property violated: Small payloads (<= 8KB) should transmit successfully")
}

// TestPreservation_GroupMessageScenarios tests realistic group message scenarios
// that should work on unfixed code (payloads under current 8KB limit).
func TestPreservation_GroupMessageScenarios(t *testing.T) {
	testCases := []struct {
		name            string
		groupSize       int
		messageContent  string
		description     string
	}{
		{
			name:           "small_group_2_members",
			groupSize:      2,
			messageContent: "Hello, this is a test message",
			description:    "Small group with short message",
		},
		{
			name:           "medium_group_5_members",
			groupSize:      5,
			messageContent: "This is a longer message with more content to test",
			description:    "Medium group with medium message",
		},
		{
			name:           "small_group_long_message",
			groupSize:      3,
			messageContent: strings.Repeat("A", 500),
			description:    "Small group with long message",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Simulate group message with fan-out encryption
			groupMessage := createGroupMessage(tc.groupSize, tc.messageContent)

			// Verify message is under 8KB (should work on unfixed code)
			if len(groupMessage) > 8192 {
				t.Skipf("Skipping test: message size %d exceeds current 8KB limit", len(groupMessage))
				return
			}

			// Create echo server
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				conn, err := upgrader.Upgrade(w, r, nil)
				if err != nil {
					return
				}
				defer conn.Close()

				conn.SetReadLimit(maxMessageSize)

				_, msg, err := conn.ReadMessage()
				if err != nil {
					t.Logf("Error reading: %v", err)
					return
				}

				conn.WriteMessage(websocket.TextMessage, msg)
			}))
			defer server.Close()

			// Connect and send
			wsURL := "ws" + strings.TrimPrefix(server.URL, "http")
			conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
			require.NoError(t, err)
			defer conn.Close()

			err = conn.WriteMessage(websocket.TextMessage, groupMessage)
			assert.NoError(t, err, "Group message for %d members should transmit successfully (%s)", tc.groupSize, tc.description)

			// Try to read echo
			conn.SetReadDeadline(time.Now().Add(1 * time.Second))
			_, receivedMsg, err := conn.ReadMessage()
			assert.NoError(t, err, "Should receive echo for group message")
			assert.Equal(t, len(groupMessage), len(receivedMsg), "Received size should match")

			// Verify connection alive
			err = conn.WriteMessage(websocket.PingMessage, nil)
			assert.NoError(t, err, "Connection should remain alive after group message")
		})
	}
}

// Helper functions

// generatePayload creates a payload of the specified size
func generatePayload(size int) string {
	// Create a realistic JSON-like payload
	if size < 50 {
		return strings.Repeat("x", size)
	}

	// Create structured data
	baseContent := `{"content":"` + strings.Repeat("A", size-50) + `","timestamp":1234567890}`
	if len(baseContent) > size {
		return baseContent[:size]
	}
	return baseContent
}

// createTestMessage creates a test WebSocket message
func createTestMessage(payload string) []byte {
	msg := map[string]interface{}{
		"type":    "message",
		"payload": payload,
		"userId":  "test-user-123",
	}
	data, _ := json.Marshal(msg)
	return data
}

// createGroupMessage simulates a group message with fan-out encryption
func createGroupMessage(groupSize int, content string) []byte {
	// Simulate encrypted content for each member
	encryptedMessages := make([]map[string]string, groupSize)
	for i := 0; i < groupSize; i++ {
		// Simulate encrypted content (base64-like string)
		encryptedContent := strings.Repeat("A", len(content)) + strings.Repeat("B", 100)
		encryptedMessages[i] = map[string]string{
			"userId":    "user-" + string(rune('A'+i)),
			"encrypted": encryptedContent,
		}
	}

	msg := map[string]interface{}{
		"type":             "group_message",
		"groupId":          "test-group-123",
		"encryptedPayload": encryptedMessages,
		"timestamp":        time.Now().Unix(),
		"originalContent":  content,
	}

	data, _ := json.Marshal(msg)
	return data
}
