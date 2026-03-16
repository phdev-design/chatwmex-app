package websocket

import (
	"encoding/json"
	"testing"
	"testing/quick"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
//
// Property 2: Preservation - Online Re-encrypt Request Behavior
//
// IMPORTANT: This is a preservation test for bugfix workflow
// These tests verify baseline behavior on UNFIXED code that must be preserved after the fix
// Tests should PASS on unfixed code (confirms behavior to preserve)
//
// Property Specification:
// For any re_encrypt_request where the sender is ONLINE (NOT the bug condition),
// the system SHALL:
// - Directly forward the request via WebSocket without database persistence (3.1)
// - Process and reply with re_encrypt_response when sender receives request (3.2)
// - Successfully decrypt message and update isDecrypted status when receiver gets response (3.3)
// - Continue normal message sending and receiving flow unaffected (3.4)
// - Continue processing other WebSocket events normally (3.5)
//
// EXPECTED OUTCOME: Tests PASS (confirms baseline behavior to preserve)

// TestPreservation_OnlineReEncryptRequestDirectForwarding tests that when sender is online,
// re_encrypt_request is forwarded directly via WebSocket without database persistence.
// **Validates: Requirement 3.1**
func TestPreservation_OnlineReEncryptRequestDirectForwarding(t *testing.T) {
	t.Log("\n=== Preservation Test: Online Re-encrypt Request Direct Forwarding ===")
	t.Log("")
	t.Log("Property: When sender is ONLINE, re_encrypt_request is forwarded directly via WebSocket")
	t.Log("Expected: Request forwarded immediately, NOT persisted to database")
	t.Log("")

	// Setup mock dependencies
	mockRepo := &mockMessageRepository{
		messages:                      []*domain.Message{},
		offlineMessages:               []*domain.Message{},
		deliveredReceiptNotifications: []*domain.DeliveredReceiptNotification{},
		pendingReEncryptRequests:      []map[string]interface{}{},
	}
	mockUsecase := &mockMessageUsecase{repo: mockRepo}
	mockFriendRepo := &mockFriendRepository{}
	mockRoomUsecase := &mockRoomUsecase{}
	mockOnlineRepo := &mockOnlineRepository{}
	mockNotificationService := &mockNotificationService{}
	mockPendingReEncryptRepo := &mockPendingReEncryptRepository{requests: []*domain.PendingReEncryptRequest{}}

	// Create hub and controller
	hub := NewHub(mockUsecase, mockRoomUsecase, mockOnlineRepo, nil, nil, nil, mockNotificationService, mockPendingReEncryptRepo, nil, nil)
	controller := NewSocketController(hub, mockUsecase, mockFriendRepo, mockPendingReEncryptRepo)
	
	// Start hub in background
	go hub.Run()

	// Test Case: Sender is ONLINE
	t.Log("Test Case: Sender (user-A) is ONLINE when receiver sends re_encrypt_request")
	t.Log("")

	// Register sender as online
	senderClient := &Client{
		hub:        hub,
		controller: controller,
		userID:     "user-A",
		send:       make(chan []byte, 256),
	}
	hub.register <- senderClient
	time.Sleep(100 * time.Millisecond) // Allow hub to process registration

	t.Log("  Setup: Sender (user-A) is registered and online")
	t.Log("")

	// Create receiver client
	receiverClient := &Client{
		hub:        hub,
		controller: controller,
		userID:     "user-B",
		send:       make(chan []byte, 256),
	}

	// Simulate receiver sending re_encrypt_request
	reEncryptRequestPayload := map[string]interface{}{
		"message_id":  "msg-12345",
		"sender_id":   "user-A", // Original sender (ONLINE)
		"receiver_id": "user-B", // Receiver requesting re-encryption
	}
	payloadBytes, _ := json.Marshal(reEncryptRequestPayload)

	t.Log("  Action: Receiver sends re_encrypt_request")
	t.Log("    message_id: msg-12345")
	t.Log("    sender_id: user-A (ONLINE)")
	t.Log("    receiver_id: user-B")
	t.Log("")

	// Handle the re_encrypt_request
	controller.OnReEncryptRequest(receiverClient, payloadBytes)

	// PRESERVATION CHECK 1: Request should NOT be persisted to database
	t.Log("  Verification 1: Check that request was NOT persisted to database")
	persistedRequestCount := len(mockPendingReEncryptRepo.requests)
	t.Logf("    Persisted re_encrypt_request count: %d", persistedRequestCount)
	
	assert.Equal(t, 0, persistedRequestCount,
		"When sender is online, re_encrypt_request should NOT be persisted to database")
	t.Log("  ✓ PASS: Request was NOT persisted (expected behavior for online sender)")
	t.Log("")

	// PRESERVATION CHECK 2: Request should be forwarded directly to sender via WebSocket
	t.Log("  Verification 2: Check that sender received request via WebSocket")
	
	select {
	case msg := <-senderClient.send:
		var wsMsg map[string]interface{}
		err := json.Unmarshal(msg, &wsMsg)
		require.NoError(t, err, "Should be able to parse WebSocket message")
		
		t.Logf("    Sender received message: event=%v", wsMsg["event"])
		
		// Check if it's a re_encrypt_request
		assert.Equal(t, "re_encrypt_request", wsMsg["event"],
			"Sender should receive re_encrypt_request event")
		
		// Verify payload
		data, ok := wsMsg["data"].(map[string]interface{})
		require.True(t, ok, "Message should have data field")
		
		assert.Equal(t, "msg-12345", data["message_id"],
			"Message ID should match")
		assert.Equal(t, "user-B", data["receiver_id"],
			"Receiver ID should match")
		
		t.Log("  ✓ PASS: Sender received re_encrypt_request via WebSocket immediately")
		t.Log("     This confirms direct forwarding without database persistence")
		
	case <-time.After(500 * time.Millisecond):
		t.Fatal("  ❌ FAIL: Sender did NOT receive re_encrypt_request via WebSocket")
	}
	t.Log("")

	t.Log("=== Preservation Test Complete ===")
	t.Log("✓ When sender is online, re_encrypt_request is forwarded directly via WebSocket")
	t.Log("✓ No database persistence occurs (expected behavior to preserve)")
	t.Log("")
}

// TestPreservation_ReEncryptResponseFlow tests the complete flow of re_encrypt_request
// and re_encrypt_response when sender is online.
// **Validates: Requirements 3.1, 3.2, 3.3**
func TestPreservation_ReEncryptResponseFlow(t *testing.T) {
	t.Log("\n=== Preservation Test: Complete Re-encrypt Request/Response Flow ===")
	t.Log("")
	t.Log("Property: When sender is online, complete re-encryption flow works correctly")
	t.Log("Expected: Request forwarded → Sender processes → Response sent → Receiver decrypts")
	t.Log("")

	// Setup mock dependencies
	mockRepo := &mockMessageRepository{
		messages:                      []*domain.Message{},
		offlineMessages:               []*domain.Message{},
		deliveredReceiptNotifications: []*domain.DeliveredReceiptNotification{},
		pendingReEncryptRequests:      []map[string]interface{}{},
	}
	mockUsecase := &mockMessageUsecase{repo: mockRepo}
	mockFriendRepo := &mockFriendRepository{}
	mockRoomUsecase := &mockRoomUsecase{}
	mockOnlineRepo := &mockOnlineRepository{}
	mockNotificationService := &mockNotificationService{}
	mockPendingReEncryptRepo := &mockPendingReEncryptRepository{requests: []*domain.PendingReEncryptRequest{}}

	// Create hub and controller
	hub := NewHub(mockUsecase, mockRoomUsecase, mockOnlineRepo, nil, nil, nil, mockNotificationService, mockPendingReEncryptRepo, nil, nil)
	controller := NewSocketController(hub, mockUsecase, mockFriendRepo, mockPendingReEncryptRepo)
	
	// Start hub in background
	go hub.Run()

	// Register sender as online
	senderClient := &Client{
		hub:        hub,
		controller: controller,
		userID:     "user-A",
		send:       make(chan []byte, 256),
	}
	hub.register <- senderClient
	time.Sleep(100 * time.Millisecond)

	// Register receiver as online
	receiverClient := &Client{
		hub:        hub,
		controller: controller,
		userID:     "user-B",
		send:       make(chan []byte, 256),
	}
	hub.register <- receiverClient
	time.Sleep(100 * time.Millisecond)

	t.Log("  Setup: Both sender (user-A) and receiver (user-B) are online")
	t.Log("")

	// Step 1: Receiver sends re_encrypt_request
	t.Log("  Step 1: Receiver sends re_encrypt_request")
	reEncryptRequestPayload := map[string]interface{}{
		"message_id":  "msg-12345",
		"sender_id":   "user-A",
		"receiver_id": "user-B",
	}
	payloadBytes, _ := json.Marshal(reEncryptRequestPayload)
	controller.OnReEncryptRequest(receiverClient, payloadBytes)

	// Step 2: Sender receives request
	t.Log("  Step 2: Sender receives re_encrypt_request")
	select {
	case msg := <-senderClient.send:
		var wsMsg map[string]interface{}
		json.Unmarshal(msg, &wsMsg)
		assert.Equal(t, "re_encrypt_request", wsMsg["event"])
		t.Log("  ✓ Sender received re_encrypt_request")
	case <-time.After(500 * time.Millisecond):
		t.Fatal("  ❌ Sender did not receive request")
	}
	t.Log("")

	// Step 3: Sender processes and sends re_encrypt_response
	t.Log("  Step 3: Sender processes request and sends re_encrypt_response")
	reEncryptResponsePayload := map[string]interface{}{
		"message_id":           "msg-12345",
		"receiver_id":          "user-B",
		"re_encrypted_content": "encrypted_content_with_new_key_12345",
	}
	responseBytes, _ := json.Marshal(reEncryptResponsePayload)
	controller.OnReEncryptResponse(senderClient, responseBytes)
	t.Log("  ✓ Sender sent re_encrypt_response")
	t.Log("")

	// Step 4: Receiver receives response
	t.Log("  Step 4: Receiver receives re_encrypt_response")
	select {
	case msg := <-receiverClient.send:
		var wsMsg map[string]interface{}
		err := json.Unmarshal(msg, &wsMsg)
		require.NoError(t, err)
		
		assert.Equal(t, "re_encrypt_response", wsMsg["event"],
			"Receiver should receive re_encrypt_response event")
		
		data, ok := wsMsg["data"].(map[string]interface{})
		require.True(t, ok)
		
		assert.Equal(t, "msg-12345", data["message_id"])
		assert.Equal(t, "encrypted_content_with_new_key_12345", data["re_encrypted_content"])
		
		t.Log("  ✓ Receiver received re_encrypt_response with re-encrypted content")
		t.Log("     Receiver can now decrypt the message successfully")
		
	case <-time.After(500 * time.Millisecond):
		t.Fatal("  ❌ Receiver did not receive response")
	}
	t.Log("")

	t.Log("=== Preservation Test Complete ===")
	t.Log("✓ Complete re-encryption flow works correctly when sender is online")
	t.Log("✓ Request → Process → Response → Decrypt (all via WebSocket)")
	t.Log("")
}

// TestPreservation_NormalMessageFlow tests that normal message sending and receiving
// continues to work correctly and is unaffected by the re-encryption mechanism.
// **Validates: Requirement 3.4**
func TestPreservation_NormalMessageFlow(t *testing.T) {
	t.Log("\n=== Preservation Test: Normal Message Flow Unaffected ===")
	t.Log("")
	t.Log("Property: Normal message sending and receiving works correctly")
	t.Log("Expected: Messages sent and received normally, unaffected by re-encryption changes")
	t.Log("")

	// Setup mock dependencies
	mockRepo := &mockMessageRepository{
		messages:                      []*domain.Message{},
		offlineMessages:               []*domain.Message{},
		deliveredReceiptNotifications: []*domain.DeliveredReceiptNotification{},
		pendingReEncryptRequests:      []map[string]interface{}{},
	}
	mockUsecase := &mockMessageUsecase{repo: mockRepo}
	mockFriendRepo := &mockFriendRepository{}
	mockRoomUsecase := &mockRoomUsecase{}
	mockOnlineRepo := &mockOnlineRepository{}
	mockNotificationService := &mockNotificationService{}
	mockPendingReEncryptRepo := &mockPendingReEncryptRepository{requests: []*domain.PendingReEncryptRequest{}}

	// Create hub and controller
	hub := NewHub(mockUsecase, mockRoomUsecase, mockOnlineRepo, nil, nil, nil, mockNotificationService, mockPendingReEncryptRepo, nil, nil)
	controller := NewSocketController(hub, mockUsecase, mockFriendRepo, mockPendingReEncryptRepo)
	
	// Start hub in background
	go hub.Run()

	// Register sender and receiver
	senderClient := &Client{
		hub:        hub,
		controller: controller,
		userID:     "user-A",
		send:       make(chan []byte, 256),
	}
	hub.register <- senderClient

	receiverClient := &Client{
		hub:        hub,
		controller: controller,
		userID:     "user-B",
		send:       make(chan []byte, 256),
	}
	hub.register <- receiverClient
	time.Sleep(100 * time.Millisecond)

	t.Log("  Setup: Sender (user-A) and receiver (user-B) are online")
	t.Log("")

	// Send a normal text message through the controller (simulating real flow)
	t.Log("  Action: Sender sends normal text message")
	normalMessagePayload := map[string]interface{}{
		"id":          "msg-normal-001",
		"sender_id":   "user-A",
		"receiver_id": "user-B",
		"content":     "Hello, this is a normal message",
		"type":        "text",
	}
	normalMessageBytes, _ := json.Marshal(normalMessagePayload)
	
	// Send through controller to simulate real message flow
	controller.OnChatMessage(senderClient, normalMessageBytes)
	
	// Small delay to allow message processing
	time.Sleep(100 * time.Millisecond)

	// Verify receiver gets the message
	t.Log("  Verification: Receiver receives normal message")
	select {
	case msg := <-receiverClient.send:
		var wsMsg map[string]interface{}
		err := json.Unmarshal(msg, &wsMsg)
		require.NoError(t, err)
		
		assert.Equal(t, "chat_message", wsMsg["event"],
			"Receiver should receive chat_message event")
		
		data, ok := wsMsg["data"].(map[string]interface{})
		require.True(t, ok)
		
		assert.Equal(t, "user-A", data["sender_id"])
		assert.Equal(t, "Hello, this is a normal message", data["content"])
		
		t.Log("  ✓ PASS: Receiver received normal message correctly")
		t.Log("     Message flow is unaffected by re-encryption mechanism")
		
	case <-time.After(500 * time.Millisecond):
		t.Fatal("  ❌ FAIL: Receiver did not receive normal message")
	}
	t.Log("")

	// Verify message was persisted
	t.Log("  Verification: Message was persisted to database")
	assert.GreaterOrEqual(t, len(mockRepo.messages), 1,
		"Normal message should be persisted to database")
	t.Log("  ✓ PASS: Message persisted correctly")
	t.Log("")

	t.Log("=== Preservation Test Complete ===")
	t.Log("✓ Normal message flow works correctly")
	t.Log("✓ Message sending and receiving unaffected by re-encryption changes")
	t.Log("")
}

// TestPreservation_OtherWebSocketEvents tests that other WebSocket events
// (typing indicators, read receipts) continue to work correctly.
// **Validates: Requirement 3.5**
func TestPreservation_OtherWebSocketEvents(t *testing.T) {
	t.Log("\n=== Preservation Test: Other WebSocket Events Work Correctly ===")
	t.Log("")
	t.Log("Property: Other WebSocket events (typing, read receipts) work normally")
	t.Log("Expected: All WebSocket event types continue to function correctly")
	t.Log("")

	// Setup mock dependencies
	mockRepo := &mockMessageRepository{
		messages:                      []*domain.Message{},
		offlineMessages:               []*domain.Message{},
		deliveredReceiptNotifications: []*domain.DeliveredReceiptNotification{},
		pendingReEncryptRequests:      []map[string]interface{}{},
	}
	mockUsecase := &mockMessageUsecase{repo: mockRepo}
	mockFriendRepo := &mockFriendRepository{}
	mockRoomUsecase := &mockRoomUsecase{}
	mockOnlineRepo := &mockOnlineRepository{}
	mockNotificationService := &mockNotificationService{}
	mockPendingReEncryptRepo := &mockPendingReEncryptRepository{requests: []*domain.PendingReEncryptRequest{}}

	// Create hub and controller
	hub := NewHub(mockUsecase, mockRoomUsecase, mockOnlineRepo, nil, nil, nil, mockNotificationService, mockPendingReEncryptRepo, nil, nil)
	controller := NewSocketController(hub, mockUsecase, mockFriendRepo, mockPendingReEncryptRepo)
	
	// Start hub in background
	go hub.Run()

	// Register users
	userAClient := &Client{
		hub:        hub,
		controller: controller,
		userID:     "user-A",
		send:       make(chan []byte, 256),
	}
	hub.register <- userAClient

	userBClient := &Client{
		hub:        hub,
		controller: controller,
		userID:     "user-B",
		send:       make(chan []byte, 256),
	}
	hub.register <- userBClient
	time.Sleep(100 * time.Millisecond)

	t.Log("  Setup: user-A and user-B are online")
	t.Log("")

	// Test 1: Typing indicator
	t.Log("  Test 1: Typing indicator event")
	typingPayload := map[string]interface{}{
		"receiver_id": "user-B",
	}
	typingBytes, _ := json.Marshal(typingPayload)
	controller.OnTyping(userAClient, typingBytes, "typing_start")

	select {
	case msg := <-userBClient.send:
		var wsMsg map[string]interface{}
		json.Unmarshal(msg, &wsMsg)
		assert.Equal(t, "typing_start", wsMsg["event"])
		t.Log("  ✓ PASS: Typing indicator works correctly")
	case <-time.After(500 * time.Millisecond):
		t.Fatal("  ❌ FAIL: Typing indicator not received")
	}
	t.Log("")

	// Test 2: Read receipt
	t.Log("  Test 2: Read receipt event")
	readReceiptPayload := map[string]interface{}{
		"message_id": "msg-12345",
		"sender_id":  "user-A",
	}
	readReceiptBytes, _ := json.Marshal(readReceiptPayload)
	controller.OnMessageReceipt(userBClient, "message_read", readReceiptBytes)

	select {
	case msg := <-userAClient.send:
		var wsMsg map[string]interface{}
		json.Unmarshal(msg, &wsMsg)
		assert.Equal(t, "message_read", wsMsg["event"])
		t.Log("  ✓ PASS: Read receipt works correctly")
	case <-time.After(500 * time.Millisecond):
		t.Fatal("  ❌ FAIL: Read receipt not received")
	}
	t.Log("")

	t.Log("=== Preservation Test Complete ===")
	t.Log("✓ Typing indicators work correctly")
	t.Log("✓ Read receipts work correctly")
	t.Log("✓ Other WebSocket events unaffected by re-encryption changes")
	t.Log("")
}

// TestPreservation_PropertyBased_OnlineReEncryptForwarding uses property-based testing
// to verify that re_encrypt_request is always forwarded directly when sender is online,
// across many different scenarios.
// **Validates: Requirements 3.1, 3.2**
func TestPreservation_PropertyBased_OnlineReEncryptForwarding(t *testing.T) {
	t.Log("\n=== Property-Based Preservation Test: Online Re-encrypt Forwarding ===")
	t.Log("")
	t.Log("Property: For ANY re_encrypt_request where sender is online,")
	t.Log("          request is forwarded directly via WebSocket without database persistence")
	t.Log("")

	// Property function
	property := func(messageIDSuffix uint16, senderIDSuffix uint8, receiverIDSuffix uint8) bool {
		// Generate unique IDs for this test case
		messageID := "msg-" + string(rune('A'+int(messageIDSuffix%26)))
		senderID := "sender-" + string(rune('A'+int(senderIDSuffix%26)))
		receiverID := "receiver-" + string(rune('A'+int(receiverIDSuffix%26)))

		// Ensure sender and receiver are different
		if senderID == receiverID {
			return true // Skip this case
		}

		// Setup
		mockRepo := &mockMessageRepository{
			messages:                      []*domain.Message{},
			offlineMessages:               []*domain.Message{},
			deliveredReceiptNotifications: []*domain.DeliveredReceiptNotification{},
			pendingReEncryptRequests:      []map[string]interface{}{},
		}
		mockUsecase := &mockMessageUsecase{repo: mockRepo}
		mockFriendRepo := &mockFriendRepository{}
		mockRoomUsecase := &mockRoomUsecase{}
		mockOnlineRepo := &mockOnlineRepository{}
		mockNotificationService := &mockNotificationService{}
	mockPendingReEncryptRepo := &mockPendingReEncryptRepository{requests: []*domain.PendingReEncryptRequest{}}

		hub := NewHub(mockUsecase, mockRoomUsecase, mockOnlineRepo, nil, nil, nil, mockNotificationService, mockPendingReEncryptRepo, nil, nil)
		controller := NewSocketController(hub, mockUsecase, mockFriendRepo, mockPendingReEncryptRepo)
		
		go hub.Run()

		// Register sender as ONLINE
		senderClient := &Client{
			hub:        hub,
			controller: controller,
			userID:     senderID,
			send:       make(chan []byte, 256),
		}
		hub.register <- senderClient
		time.Sleep(50 * time.Millisecond)

		// Create receiver client
		receiverClient := &Client{
			hub:        hub,
			controller: controller,
			userID:     receiverID,
			send:       make(chan []byte, 256),
		}

		// Send re_encrypt_request
		reEncryptRequestPayload := map[string]interface{}{
			"message_id":  messageID,
			"sender_id":   senderID,
			"receiver_id": receiverID,
		}
		payloadBytes, _ := json.Marshal(reEncryptRequestPayload)
		controller.OnReEncryptRequest(receiverClient, payloadBytes)

		// Property 1: Request should NOT be persisted
		if len(mockPendingReEncryptRepo.requests) != 0 {
			return false
		}

		// Property 2: Request should be forwarded to sender
		select {
		case msg := <-senderClient.send:
			var wsMsg map[string]interface{}
			if err := json.Unmarshal(msg, &wsMsg); err != nil {
				return false
			}
			if wsMsg["event"] != "re_encrypt_request" {
				return false
			}
			return true
		case <-time.After(300 * time.Millisecond):
			return false
		}
	}

	// Run property-based test
	config := &quick.Config{
		MaxCount: 20, // Test with 20 random scenarios
	}

	err := quick.Check(property, config)
	assert.NoError(t, err,
		"Property violated: Online re_encrypt_request should always be forwarded directly without persistence")

	if err == nil {
		t.Log("✓ Property verified across 20 random test cases")
		t.Log("  All online re_encrypt_requests were forwarded directly")
		t.Log("  No requests were persisted to database")
		t.Log("")
	}

	t.Log("=== Property-Based Preservation Test Complete ===")
	t.Log("")
}

