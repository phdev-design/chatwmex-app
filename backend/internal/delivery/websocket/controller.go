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
	hub            *Hub
	messageUsecase domain.MessageUsecase
	friendRepo     domain.FriendRepository
}

// NewSocketController creates a new SocketController.
func NewSocketController(hub *Hub, mu domain.MessageUsecase, fr domain.FriendRepository) *SocketController {
	return &SocketController{
		hub:            hub,
		messageUsecase: mu,
		friendRepo:     fr,
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
	default:
		log.Printf("Unknown event: %s", req.Event)
		c.respondError(client, "error", "Unknown event type")
	}
}

// OnChatMessage handles chat messages (text, image, voice, video).
func (c *SocketController) OnChatMessage(client *Client, data []byte) {
	var msg domain.Message
	if err := json.Unmarshal(data, &msg); err != nil {
		c.respondError(client, "error", "Invalid message format")
		return
	}

	// Validate common fields
	if msg.Content == "" && msg.Type == "text" {
		c.respondError(client, "error", "Content is required")
		return
	}

	// Set system fields
	msg.SenderID = client.userID
	msg.CreatedAt = time.Now()

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
	// 1. Validate specific media fields (if any)
	// For example, we might expect 'metadata' in content or separate fields.
	// Since domain.Message is simple, we assume Content contains the URL/ID.
	if msg.Content == "" {
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

	c.respondSuccess(client, "read_receipt", map[string]interface{}{
		"conversation_id": payload.ConversationID,
		"is_room":         payload.IsRoom,
		"reader_id":       client.userID,
		"read_at":         time.Now().Format(time.RFC3339),
	})
	if !payload.IsRoom && payload.ConversationID != "" {
		c.hub.SendReadReceiptToUser(payload.ConversationID, client.userID)
	}
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
