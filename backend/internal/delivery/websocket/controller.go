package websocket

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"chatwmex_backend/internal/domain"
)

// SocketController handles WebSocket events.
type SocketController struct {
	hub                      *Hub
	messageUsecase           domain.MessageUsecase
	friendRepo               domain.FriendRepository
	pendingReEncryptRepo     domain.PendingReEncryptRepository
}

// NewSocketController creates a new SocketController.
func NewSocketController(hub *Hub, mu domain.MessageUsecase, fr domain.FriendRepository, prr domain.PendingReEncryptRepository) *SocketController {
	return &SocketController{
		hub:                  hub,
		messageUsecase:       mu,
		friendRepo:           fr,
		pendingReEncryptRepo: prr,
	}
}

// WSRequest represents the standard structure for WebSocket messages.
type WSRequest struct {
	Event string          `json:"event"`
	Data  json.RawMessage `json:"data"`
}

// WSResponse represents the standard structure for WebSocket responses.
type WSResponse struct {
	Event string      `json:"event"`
	Data  interface{} `json:"data"`
}

// HandleMessage dispatches the incoming message to the appropriate handler.
func (c *SocketController) HandleMessage(client *Client, message []byte) {
	var req WSRequest
	if err := json.Unmarshal(message, &req); err != nil {
		log.Printf("❌ [WebSocket] JSON parse error from user %s: %v | Raw message (first 200 chars): %s", 
			client.userID, err, string(message[:min(200, len(message))]))
		c.respondError(client, "error", "Invalid JSON format")
		return
	}

	switch req.Event {
	case "chat_message":
		c.OnChatMessage(client, req.Data)
	case "mark_read":
		c.OnMarkRead(client, req.Data)
	case "typing_start":
		c.OnTyping(client, req.Data, "typing_start")
	case "typing_stop":
		c.OnTyping(client, req.Data, "typing_stop")
	case "message_delivered", "message_read":
		c.OnMessageReceipt(client, req.Event, req.Data)
	// 🔐 E2EE Auto-Resend Control Messages (不寫入資料庫，僅轉發)
	case "re_encrypt_request":
		c.OnReEncryptRequest(client, req.Data)
	case "re_encrypt_response":
		c.OnReEncryptResponse(client, req.Data)
	default:
		log.Printf("Unknown event: %s", req.Event)
		c.respondError(client, "error", "Unknown event type")
	}
}

// min returns the minimum of two integers
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// OnChatMessage handles chat messages (text, image, voice, video).
func (c *SocketController) OnChatMessage(client *Client, data []byte) {
	var msg domain.Message
	if err := json.Unmarshal(data, &msg); err != nil {
		log.Printf("❌ [WebSocket] Message parse error from user %s: %v | Raw data (first 200 chars): %s", 
			client.userID, err, string(data[:min(200, len(data))]))
		c.respondError(client, "error", "Invalid message format")
		return
	}

	// 🔥 新增：記錄收到的訊息資訊
	if msg.LinkPreview != nil {
		log.Printf("📎 [WebSocket] 收到訊息附帶 Link Preview: URL=%s, Title=%s", msg.LinkPreview.URL, msg.LinkPreview.Title)
	} else {
		log.Printf("📝 [WebSocket] 收到純文字訊息，無 Link Preview")
	}

	// Validate common fields
	// 🔐 E2EE: 允許使用 EncryptedContentsFanout 的訊息 content 為空
	if msg.Content == "" && msg.Type == "text" && len(msg.EncryptedContentsFanout) == 0 {
		c.respondError(client, "error", "Content is required")
		return
	}

	// Set system fields
	msg.SenderID = client.userID
	msg.CreatedAt = time.Now()
	
	// 🔍 DEBUG: 檢查訊息創建時的 SenderID
	log.Printf("[DEBUG] OnChatMessage: client.userID=%s, msg.SenderID=%s, msg.RoomID=%s, msg.Type=%s", 
		client.userID, msg.SenderID, msg.RoomID, msg.Type)

	// Block Validation for DMs
	if msg.RoomID == "" && msg.ReceiverID != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		blocked, err := c.friendRepo.IsBlocked(ctx, msg.SenderID, msg.ReceiverID)
		cancel()
		if err != nil {
			log.Printf("Error checking block status: %v", err)
			c.respondError(client, "error", "Failed to check block status")
			return
		}
		if blocked {
			// Using existing respondError structure, but we can also manually send if frontend expects flat JSON
			// The frontend prompt specifies { "type": "error", "message": "cannot_send_blocked" }
			// We will send both event format and flat format data inside respondError.
			// Actually, typical respondError generates { "event": "error", "data": { "message": "..." } }
			// We'll stick to respondError and adjust frontend if necessary.
			c.respondError(client, "error", "cannot_send_blocked")
			return
		}
	}

	// Handle media types
	if msg.Type == "image" || msg.Type == "voice" || msg.Type == "video" {
		if err := c.handleMediaMessage(client, &msg); err != nil {
			return // Error already handled in helper
		}
	} else {
		// Default (text) handling
		// Persist to DB
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := c.messageUsecase.SendMessage(ctx, &msg); err != nil {
			log.Printf("Error saving message: %v", err)
			c.respondError(client, "error", "Failed to save message")
			return
		}
	}

	// Broadcast via Hub (RabbitMQ aware)
	// If RabbitMQ is configured, Publish() will handle it.
	if c.hub.rabbitMQ != nil {
		if err := c.hub.rabbitMQ.Publish(&msg); err != nil {
			log.Printf("Error publishing to RabbitMQ: %v", err)
			// Fallback to local broadcast
			c.hub.broadcast <- &msg
		}
	} else {
		c.hub.broadcast <- &msg
	}

	// Update LastActiveAt if sender is a linked device (async, no-op for regular users)
	c.hub.updateLinkedDeviceActivity(client.userID)

	// Send ACK to sender
	c.respondSuccess(client, "message_ack", map[string]string{
		"message_id":    msg.ID,
		"client_msg_id": msg.ClientMsgID,
		"status":        "sent",
	})
}

// handleMediaMessage handles validation and processing for media messages.
// This implements the DRY principle for image, voice, and video types.
func (c *SocketController) handleMediaMessage(client *Client, msg *domain.Message) error {
	// 1. Validate specific media fields
	// 🔐 E2EE: 對於群組訊息，content 可能為空（使用 encrypted_contents_fanout）
	// 只有在非 fanout 模式下才檢查 content
	hasFanout := msg.EncryptedContentsFanout != nil && len(msg.EncryptedContentsFanout) > 0
	if msg.Content == "" && !hasFanout {
		c.respondError(client, "error", "Media content (URL) is required")
		return context.DeadlineExceeded // Just a placeholder error
	}

	// 2. Persist to DB
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := c.messageUsecase.SendMessage(ctx, msg); err != nil {
		log.Printf("Error saving media message: %v", err)
		c.respondError(client, "error", "Failed to save media message")
		return err
	}

	return nil
}

// OnMarkRead handles mark-as-read events.
func (c *SocketController) OnMarkRead(client *Client, data []byte) {
	type MarkReadPayload struct {
		ConversationID string `json:"conversation_id"`
		IsRoom         bool   `json:"is_room"`
	}
	var payload MarkReadPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		c.respondError(client, "error", "Invalid payload")
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := c.messageUsecase.MarkAsRead(ctx, client.userID, payload.ConversationID, payload.IsRoom); err != nil {
		log.Printf("Error marking as read: %v", err)
		c.respondError(client, "error", "Failed to mark as read")
		return
	}

	readAt := time.Now()
	c.respondSuccess(client, "read_receipt", map[string]interface{}{
		"conversation_id": payload.ConversationID,
		"is_room":         payload.IsRoom,
		"reader_id":       client.userID,
		"read_at":         readAt.Format(time.RFC3339),
	})
	if !payload.IsRoom && payload.ConversationID != "" {
		c.hub.SendReadReceiptToUser(payload.ConversationID, client.userID)
	}

	// Sync read status to all linked devices of the reader
	c.hub.BroadcastReadStatusSync(client.userID, payload.ConversationID, readAt)
}

// OnTypingStart handles typing indicators.
func (c *SocketController) OnTyping(client *Client, data []byte, event string) {
	type TypingPayload struct {
		RoomID     string `json:"room_id"`
		ReceiverID string `json:"receiver_id"`
	}
	var payload TypingPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		c.respondError(client, "error", "Invalid payload")
		return
	}

	if payload.RoomID != "" {
		c.hub.SendTypingToRoom(client.userID, payload.RoomID, event)
		return
	}
	if payload.ReceiverID != "" {
		c.hub.SendTypingToUser(client.userID, payload.ReceiverID, event)
	}
}

// OnMessageReceipt handles delivery and read receipts from the recipient.
func (c *SocketController) OnMessageReceipt(client *Client, event string, data []byte) {
	var receipt domain.MessageReceipt
	if err := json.Unmarshal(data, &receipt); err != nil {
		return
	}

	// 1. Determine status
	status := "delivered"
	if event == "message_read" {
		status = "read"
	}
	receipt.Status = status

	// 2. Update Database
	if receipt.MessageID != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if err := c.messageUsecase.UpdateMessageStatus(ctx, receipt.MessageID, status); err != nil {
			log.Printf("Error updating message status: %v", err)
		}
	}

	// 3. Notify the original sender
	if receipt.SenderID != "" {
		c.hub.SendNotification(receipt.SenderID, event, receipt)
	}
}

// respondError sends an error message back to the client.
func (c *SocketController) respondError(client *Client, event string, message string) {
	resp := WSResponse{
		Event: event,
		Data:  map[string]string{"message": message},
	}
	respBytes, _ := json.Marshal(resp)
	client.send <- respBytes
}

// respondSuccess sends a success message back to the client.
func (c *SocketController) respondSuccess(client *Client, event string, data interface{}) {
	resp := WSResponse{
		Event: event,
		Data:  data,
	}
	respBytes, _ := json.Marshal(resp)
	client.send <- respBytes
}

// 🔐 ========== E2EE Auto-Resend Control Message Handlers ==========

// OnReEncryptRequest handles re-encryption requests from receivers who failed to decrypt.
// This is an ephemeral control message that is NOT persisted to the database.
// It is only forwarded to the original sender via WebSocket.
func (c *SocketController) OnReEncryptRequest(client *Client, data []byte) {
	type ReEncryptRequestPayload struct {
		MessageID  string `json:"message_id"`   // 需要重新加密的訊息 ID
		SenderID   string `json:"sender_id"`    // 原始發送方 ID
		ReceiverID string `json:"receiver_id"`  // 請求方 ID (當前 client)
		RoomID     string `json:"room_id"`      // 聊天室 ID (可選)
	}
	
	var payload ReEncryptRequestPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		log.Printf("❌ [E2EE] Invalid re_encrypt_request payload from user %s: %v", client.userID, err)
		c.respondError(client, "error", "Invalid re_encrypt_request format")
		return
	}
	
	// 驗證必要欄位
	if payload.MessageID == "" || payload.SenderID == "" {
		log.Printf("❌ [E2EE] Missing required fields in re_encrypt_request from user %s", client.userID)
		c.respondError(client, "error", "Missing message_id or sender_id")
		return
	}
	
	// 設定請求方 ID（當前用戶）
	payload.ReceiverID = client.userID
	
	log.Printf("🔐 [E2EE] Re-encrypt request: messageID=%s, from=%s, to=%s", 
		payload.MessageID, payload.ReceiverID, payload.SenderID)
	
	// Check if sender is online
	isSenderOnline := c.hub.IsUserOnline(payload.SenderID)
	
	if isSenderOnline {
		// PRESERVATION: Sender is online, use existing direct WebSocket forwarding
		log.Printf("🔐 [E2EE] Sender %s is online, forwarding request directly via WebSocket", payload.SenderID)
		c.hub.SendNotification(payload.SenderID, "re_encrypt_request", payload)
	} else {
		// BUG FIX: Sender is offline, persist request to MongoDB
		log.Printf("🔐 [E2EE] Sender %s is offline, persisting request to database", payload.SenderID)
		
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		
		pendingReq := &domain.PendingReEncryptRequest{
			MessageID:  payload.MessageID,
			SenderID:   payload.SenderID,
			ReceiverID: payload.ReceiverID,
			RoomID:     payload.RoomID,
			CreatedAt:  time.Now(),
			ExpiresAt:  time.Now().Add(7 * 24 * time.Hour), // 7 days TTL
		}
		
		if err := c.pendingReEncryptRepo.Store(ctx, pendingReq); err != nil {
			log.Printf("❌ [E2EE] Failed to persist re_encrypt_request to database: %v", err)
			c.respondError(client, "error", "Failed to persist re_encrypt_request")
			return
		}
		
		log.Printf("✅ [E2EE] Successfully persisted re_encrypt_request to database: messageID=%s, senderID=%s, receiverID=%s", 
			payload.MessageID, payload.SenderID, payload.ReceiverID)
		
		// Send success response to receiver
		c.respondSuccess(client, "re_encrypt_request_queued", map[string]string{
			"message_id": payload.MessageID,
			"status":     "queued",
		})
	}
}

// OnReEncryptResponse handles re-encrypted message responses from senders.
// This is an ephemeral control message that is NOT persisted to the database.
// It is only forwarded to the original receiver via WebSocket.
func (c *SocketController) OnReEncryptResponse(client *Client, data []byte) {
	type ReEncryptResponsePayload struct {
		MessageID      string `json:"message_id"`       // 原始訊息 ID
		ReceiverID     string `json:"receiver_id"`      // 接收方 ID
		ReEncryptedContent string `json:"re_encrypted_content"` // 重新加密的密文
	}
	
	var payload ReEncryptResponsePayload
	if err := json.Unmarshal(data, &payload); err != nil {
		log.Printf("❌ [E2EE] Invalid re_encrypt_response payload from user %s: %v", client.userID, err)
		c.respondError(client, "error", "Invalid re_encrypt_response format")
		return
	}
	
	// 驗證必要欄位
	if payload.MessageID == "" || payload.ReceiverID == "" || payload.ReEncryptedContent == "" {
		log.Printf("❌ [E2EE] Missing required fields in re_encrypt_response from user %s", client.userID)
		c.respondError(client, "error", "Missing required fields")
		return
	}
	
	log.Printf("🔐 [E2EE] Re-encrypt response: messageID=%s, from=%s, to=%s", 
		payload.MessageID, client.userID, payload.ReceiverID)
	
	// 轉發給接收方（不寫入資料庫）
	c.hub.SendNotification(payload.ReceiverID, "re_encrypt_response", payload)
}
