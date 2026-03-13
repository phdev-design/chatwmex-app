package websocket

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// **Validates: Requirements 1.1**
// Property 1: Bug Condition - Large Payload WebSocket Disconnection
//
// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
// DO NOT attempt to fix the test or the code when it fails
//
// This test encodes the expected behavior - it will validate the fix when it passes after implementation
// GOAL: Surface counterexamples that demonstrate the bug exists
//
// Scoped PBT Approach: Scope the property to payloads > 8KB (e.g., 10KB, 50KB, 100KB)
// Test that WebSocket connection crashes when receiving group message with Fan-out E2EE payload > 8KB
// The test assertions verify connection remains alive after receiving large payload
//
// EXPECTED OUTCOME: Test FAILS (this is correct - it proves the bug exists)

// FanOutE2EEMessage simulates a group message with Fan-out E2EE encryption
// where each member has their own encrypted content
type FanOutE2EEMessage struct {
	Event string                 `json:"event"`
	Data  map[string]interface{} `json:"data"`
}

// generateFanOutPayload creates a simulated Fan-out E2EE group message payload
// memberCount: number of group members
// contentSizePerMember: approximate encrypted content size per member in bytes
func generateFanOutPayload(memberCount int, contentSizePerMember int) []byte {
	// Simulate encrypted content for each member
	memberEncryptedData := make(map[string]string)
	
	// Generate encrypted content for each member (simulated as base64-like strings)
	for i := 0; i < memberCount; i++ {
		memberID := fmt.Sprintf("user_%d", i)
		// Create encrypted content of specified size
		encryptedContent := strings.Repeat("A", contentSizePerMember)
		memberEncryptedData[memberID] = encryptedContent
	}
	
	// Create the message structure
	message := FanOutE2EEMessage{
		Event: "chat_message",
		Data: map[string]interface{}{
			"id":                fmt.Sprintf("msg_%d", time.Now().UnixNano()),
			"client_msg_id":     fmt.Sprintf("client_msg_%d", time.Now().UnixNano()),
			"sender_id":         "user_0",
			"room_id":           "test_room_123",
			"content":           "Group message with Fan-out E2EE",
			"type":              "text",
			"member_encrypted":  memberEncryptedData, // Fan-out E2EE data
			"created_at":        time.Now().Format(time.RFC3339),
		},
	}
	
	payload, _ := json.Marshal(message)
	return payload
}

// TestProperty_LargePayloadWebSocketConnection tests the bug condition:
// WebSocket connection should handle large payloads from group messages with Fan-out E2EE
//
// This is a scoped property-based test that generates payloads > 8KB
func TestProperty_LargePayloadWebSocketConnection(t *testing.T) {
	// Test cases representing different group sizes and message scenarios
	testCases := []struct {
		name                  string
		memberCount           int
		contentSizePerMember  int
		expectedPayloadSize   int // approximate
	}{
		{
			name:                 "10_members_1KB_each_~10KB_total",
			memberCount:          10,
			contentSizePerMember: 1024,
			expectedPayloadSize:  10 * 1024, // ~10KB
		},
		{
			name:                 "20_members_1KB_each_~20KB_total",
			memberCount:          20,
			contentSizePerMember: 1024,
			expectedPayloadSize:  20 * 1024, // ~20KB
		},
		{
			name:                 "50_members_1KB_each_~50KB_total",
			memberCount:          50,
			contentSizePerMember: 1024,
			expectedPayloadSize:  50 * 1024, // ~50KB
		},
		{
			name:                 "100_members_1KB_each_~100KB_total",
			memberCount:          100,
			contentSizePerMember: 1024,
			expectedPayloadSize:  100 * 1024, // ~100KB
		},
		{
			name:                 "10_members_with_link_preview_~12KB_total",
			memberCount:          10,
			contentSizePerMember: 1200, // Slightly larger to simulate link preview data
			expectedPayloadSize:  12 * 1024, // ~12KB
		},
	}
	
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Generate the large payload
			payload := generateFanOutPayload(tc.memberCount, tc.contentSizePerMember)
			actualSize := len(payload)
			
			t.Logf("Generated payload size: %d bytes (%.2f KB)", actualSize, float64(actualSize)/1024)
			
			// Verify payload is indeed > 8KB (the current limit)
			require.Greater(t, actualSize, 8192, 
				"Payload must be > 8KB to trigger the bug condition")
			
			// Create a test WebSocket server with current maxMessageSize (8KB)
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				upgrader := websocket.Upgrader{
					ReadBufferSize:  1024,
					WriteBufferSize: 1024,
					CheckOrigin: func(r *http.Request) bool {
						return true
					},
				}
				
				conn, err := upgrader.Upgrade(w, r, nil)
				if err != nil {
					t.Logf("Upgrade error: %v", err)
					return
				}
				defer conn.Close()
				
				// Set the current read limit (8KB) - this is the bug condition
				conn.SetReadLimit(maxMessageSize)
				
				// Try to read the message
				_, message, err := conn.ReadMessage()
				if err != nil {
					// This is expected with current code - connection will fail
					t.Logf("Read error (expected with unfixed code): %v", err)
					return
				}
				
				// If we successfully read the message, echo it back
				t.Logf("Successfully read message of size: %d bytes", len(message))
				err = conn.WriteMessage(websocket.TextMessage, []byte(`{"status":"ok"}`))
				if err != nil {
					t.Logf("Write error: %v", err)
				}
			}))
			defer server.Close()
			
			// Connect to the test server
			wsURL := "ws" + strings.TrimPrefix(server.URL, "http")
			conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
			require.NoError(t, err, "Failed to connect to WebSocket server")
			defer conn.Close()
			
			// Send the large payload
			err = conn.WriteMessage(websocket.TextMessage, payload)
			require.NoError(t, err, "Failed to send message")
			
			// Try to read response with timeout
			conn.SetReadDeadline(time.Now().Add(2 * time.Second))
			_, response, err := conn.ReadMessage()
			
			// CRITICAL ASSERTION:
			// With unfixed code (maxMessageSize = 8KB), this will FAIL
			// The connection will be closed due to "read limit exceeded"
			// 
			// After the fix (maxMessageSize = 1MB), this should PASS
			// The connection should remain alive and we should receive a response
			if err != nil {
				t.Logf("❌ Connection failed after sending %d byte payload: %v", actualSize, err)
				t.Logf("This confirms the bug exists: WebSocket disconnects on large payloads > 8KB")
				
				// Document the counterexample
				t.Errorf("COUNTEREXAMPLE FOUND: Payload size=%d bytes (%.2f KB), Members=%d, Error=%v",
					actualSize, float64(actualSize)/1024, tc.memberCount, err)
			} else {
				t.Logf("✅ Connection remained alive after sending %d byte payload", actualSize)
				t.Logf("Response: %s", string(response))
				
				assert.NotNil(t, response, "Should receive response from server")
			}
			
			// Additional assertion: verify connection is still usable
			// Send a small follow-up message
			followUpMsg := []byte(`{"event":"ping","data":{}}`)
			err = conn.WriteMessage(websocket.TextMessage, followUpMsg)
			
			if err != nil {
				t.Logf("❌ Connection is broken, cannot send follow-up message: %v", err)
				t.Fail() // Connection should remain alive
			} else {
				t.Logf("✅ Connection is still alive, follow-up message sent successfully")
			}
		})
	}
}

// TestProperty_PayloadSizeRange tests the property across a range of payload sizes
// This is a more comprehensive property-based test
func TestProperty_PayloadSizeRange(t *testing.T) {
	// Test various payload sizes from 9KB to 200KB
	payloadSizes := []int{
		9 * 1024,    // 9KB - just above current limit
		10 * 1024,   // 10KB
		20 * 1024,   // 20KB
		50 * 1024,   // 50KB
		100 * 1024,  // 100KB
		200 * 1024,  // 200KB
	}
	
	for _, targetSize := range payloadSizes {
		t.Run(fmt.Sprintf("payload_%dKB", targetSize/1024), func(t *testing.T) {
			// Calculate member count and content size to achieve target payload size
			// Assuming ~1KB per member
			memberCount := targetSize / 1024
			if memberCount < 1 {
				memberCount = 1
			}
			contentSizePerMember := 1024
			
			payload := generateFanOutPayload(memberCount, contentSizePerMember)
			actualSize := len(payload)
			
			t.Logf("Target: %d KB, Actual: %d bytes (%.2f KB)", 
				targetSize/1024, actualSize, float64(actualSize)/1024)
			
			// Verify payload is > 8KB
			if actualSize <= 8192 {
				t.Skip("Payload not large enough to trigger bug condition")
			}
			
			// Create test server
			connectionClosed := false
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				upgrader := websocket.Upgrader{
					CheckOrigin: func(r *http.Request) bool { return true },
				}
				
				conn, err := upgrader.Upgrade(w, r, nil)
				if err != nil {
					return
				}
				defer conn.Close()
				
				conn.SetReadLimit(maxMessageSize) // Current 8KB limit
				
				_, _, err = conn.ReadMessage()
				if err != nil {
					connectionClosed = true
					t.Logf("Connection closed on %d byte payload: %v", actualSize, err)
					return
				}
				
				conn.WriteMessage(websocket.TextMessage, []byte(`{"status":"ok"}`))
			}))
			defer server.Close()
			
			// Connect and send
			wsURL := "ws" + strings.TrimPrefix(server.URL, "http")
			conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
			require.NoError(t, err)
			defer conn.Close()
			
			err = conn.WriteMessage(websocket.TextMessage, payload)
			require.NoError(t, err)
			
			// Try to read response
			conn.SetReadDeadline(time.Now().Add(2 * time.Second))
			_, _, err = conn.ReadMessage()
			
			// EXPECTED: With unfixed code, this should fail for payloads > 8KB
			if err != nil || connectionClosed {
				t.Errorf("COUNTEREXAMPLE: Payload %d bytes (%.2f KB) caused connection failure",
					actualSize, float64(actualSize)/1024)
			}
		})
	}
}
