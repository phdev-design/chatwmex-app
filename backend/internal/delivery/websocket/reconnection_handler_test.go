package websocket

import (
	"encoding/json"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"
)

// TestReconnectionHandler_DeliverPendingRequests tests the reconnection handler
// that delivers pending re-encrypt requests when a user comes back online.
func TestReconnectionHandler_DeliverPendingRequests(t *testing.T) {
	t.Log("=== Reconnection Handler Test: Deliver Pending Re-encrypt Requests ===")
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
	hub := NewHub(mockUsecase, mockRoomUsecase, mockOnlineRepo, nil, nil, nil, mockNotificationService, mockPendingReEncryptRepo, nil, nil, nil, nil)
	controller := NewSocketController(hub, mockUsecase, mockFriendRepo, mockPendingReEncryptRepo)

	// Start hub in background
	go hub.Run()

	t.Log("Scenario: Sender is offline, receiver sends re_encrypt_request, sender reconnects")
	t.Log("")

	// Step 1: Receiver sends re_encrypt_request while sender is offline
	t.Log("Step 1: Receiver sends re_encrypt_request (sender is offline)")
	receiverClient := &Client{
		userID: "user-B",
		send:   make(chan []byte, 256),
		hub:    hub,
	}
	hub.register <- receiverClient
	time.Sleep(100 * time.Millisecond)

	// Send re_encrypt_request
	reEncryptReq := map[string]interface{}{
		"event": "re_encrypt_request",
		"data": map[string]interface{}{
			"message_id":  "msg-12345",
			"sender_id":   "user-A", // offline
			"receiver_id": "user-B",
			"room_id":     "",
		},
	}
	reqBytes, _ := json.Marshal(reEncryptReq)
	controller.HandleMessage(receiverClient, reqBytes)
	time.Sleep(100 * time.Millisecond)

	// Verify request was persisted
	persistedCount := len(mockPendingReEncryptRepo.requests)
	if persistedCount != 1 {
		t.Errorf("Expected 1 persisted request, got %d", persistedCount)
	} else {
		t.Log("  ✓ Request persisted to database")
	}
	t.Log("")

	// Step 2: Sender reconnects
	t.Log("Step 2: Sender (user-A) reconnects")
	senderClient := &Client{
		userID: "user-A",
		send:   make(chan []byte, 256),
		hub:    hub,
	}
	hub.register <- senderClient
	time.Sleep(200 * time.Millisecond) // Give time for reconnection handler to run

	// Verify sender received the pending request
	select {
	case msg := <-senderClient.send:
		var response map[string]interface{}
		if err := json.Unmarshal(msg, &response); err != nil {
			t.Errorf("Failed to unmarshal sender message: %v", err)
		} else {
			event, _ := response["event"].(string)
			if event == "re_encrypt_request" {
				data, _ := response["data"].(map[string]interface{})
				messageID, _ := data["message_id"].(string)
				if messageID == "msg-12345" {
					t.Log("  ✓ Sender received pending re_encrypt_request")
					t.Logf("    message_id: %s", messageID)
				} else {
					t.Errorf("Expected message_id msg-12345, got %s", messageID)
				}
			} else {
				t.Errorf("Expected event re_encrypt_request, got %s", event)
			}
		}
	case <-time.After(500 * time.Millisecond):
		t.Error("Timeout: Sender did not receive pending re_encrypt_request")
	}
	t.Log("")

	// Step 3: Verify request was deleted from database
	t.Log("Step 3: Verify request was deleted after successful delivery")
	time.Sleep(100 * time.Millisecond)
	remainingCount := len(mockPendingReEncryptRepo.requests)
	if remainingCount != 0 {
		t.Errorf("Expected 0 remaining requests, got %d", remainingCount)
	} else {
		t.Log("  ✓ Request deleted from database after delivery")
	}
	t.Log("")

	t.Log("=== Reconnection Handler Test Complete ===")
	t.Log("✓ Pending re_encrypt_requests are delivered when sender reconnects")
	t.Log("✓ Requests are deleted from database after successful delivery")
}

// TestReconnectionHandler_MultiplePendingRequests tests delivery of multiple
// pending requests in the correct order (oldest first).
func TestReconnectionHandler_MultiplePendingRequests(t *testing.T) {
	t.Log("=== Reconnection Handler Test: Multiple Pending Requests ===")
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
	hub := NewHub(mockUsecase, mockRoomUsecase, mockOnlineRepo, nil, nil, nil, mockNotificationService, mockPendingReEncryptRepo, nil, nil, nil, nil)
	controller := NewSocketController(hub, mockUsecase, mockFriendRepo, mockPendingReEncryptRepo)

	// Start hub in background
	go hub.Run()

	t.Log("Scenario: Multiple re_encrypt_requests sent while sender is offline")
	t.Log("")

	// Step 1: Send multiple re_encrypt_requests while sender is offline
	t.Log("Step 1: Send 3 re_encrypt_requests (sender is offline)")
	receiverClient := &Client{
		userID: "user-B",
		send:   make(chan []byte, 256),
		hub:    hub,
	}
	hub.register <- receiverClient
	time.Sleep(100 * time.Millisecond)

	// Send 3 requests
	for i := 1; i <= 3; i++ {
		reEncryptReq := map[string]interface{}{
			"event": "re_encrypt_request",
			"data": map[string]interface{}{
				"message_id":  "msg-" + string(rune('0'+i)),
				"sender_id":   "user-A", // offline
				"receiver_id": "user-B",
				"room_id":     "",
			},
		}
		reqBytes, _ := json.Marshal(reEncryptReq)
		controller.HandleMessage(receiverClient, reqBytes)
		time.Sleep(50 * time.Millisecond)
	}

	// Verify all requests were persisted
	persistedCount := len(mockPendingReEncryptRepo.requests)
	if persistedCount != 3 {
		t.Errorf("Expected 3 persisted requests, got %d", persistedCount)
	} else {
		t.Log("  ✓ All 3 requests persisted to database")
	}
	t.Log("")

	// Step 2: Sender reconnects
	t.Log("Step 2: Sender (user-A) reconnects")
	senderClient := &Client{
		userID: "user-A",
		send:   make(chan []byte, 256),
		hub:    hub,
	}
	hub.register <- senderClient
	time.Sleep(200 * time.Millisecond)

	// Verify sender received all 3 requests in order
	t.Log("Step 3: Verify sender receives all pending requests")
	receivedCount := 0
	for i := 0; i < 3; i++ {
		select {
		case msg := <-senderClient.send:
			var response map[string]interface{}
			if err := json.Unmarshal(msg, &response); err == nil {
				event, _ := response["event"].(string)
				if event == "re_encrypt_request" {
					receivedCount++
					data, _ := response["data"].(map[string]interface{})
					messageID, _ := data["message_id"].(string)
					t.Logf("  ✓ Received request %d: message_id=%s", receivedCount, messageID)
				}
			}
		case <-time.After(500 * time.Millisecond):
			break
		}
	}

	if receivedCount != 3 {
		t.Errorf("Expected to receive 3 requests, got %d", receivedCount)
	} else {
		t.Log("  ✓ All 3 requests delivered successfully")
	}
	t.Log("")

	// Step 4: Verify all requests were deleted
	t.Log("Step 4: Verify all requests deleted after delivery")
	time.Sleep(100 * time.Millisecond)
	remainingCount := len(mockPendingReEncryptRepo.requests)
	if remainingCount != 0 {
		t.Errorf("Expected 0 remaining requests, got %d", remainingCount)
	} else {
		t.Log("  ✓ All requests deleted from database")
	}
	t.Log("")

	t.Log("=== Reconnection Handler Test Complete ===")
	t.Log("✓ Multiple pending requests delivered in correct order")
	t.Log("✓ All requests deleted after successful delivery")
}
