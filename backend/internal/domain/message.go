package domain

import (
	"context"
	"time"
)

// Message represents a chat message.
// Content is stored encrypted in the database but decrypted in this domain model.
type Message struct {
	ID          string    `json:"id"`
	ClientMsgID string    `json:"client_msg_id,omitempty"` // For idempotency and ACK tracking
	SenderID    string    `json:"sender_id"`
	ReceiverID  string    `json:"receiver_id,omitempty"` // For 1-on-1 chat, empty if RoomID is set
	RoomID     string    `json:"room_id,omitempty"`     // For Group chat, empty if ReceiverID is set
	Content    string    `json:"content"`               // Business level content (plaintext)
	Type       string    `json:"type"`              // "text", "image", "read_receipt"
	IsRead     bool      `json:"is_read,omitempty"` // For backwards compatibility or simple 1-on-1
	ReadBy     []string  `json:"read_by"`           // List of UserIDs who read the message
	CreatedAt  time.Time `json:"created_at"`
}

// MessageRepository defines the interface for message data persistence.
type MessageRepository interface {
	// StoreMessage saves a message to the repository.
	// Implementation should handle encryption before storage.
	StoreMessage(ctx context.Context, msg *Message) error
	
	GetHistory(ctx context.Context, userID, contactID string, limit, offset int) ([]*Message, error)
	// Offline Message Handling
	StoreOfflineMessage(ctx context.Context, userID string, msg *Message) error
	GetOfflineMessages(ctx context.Context, userID string) ([]*Message, error)
	
	CountUnreadInRoom(ctx context.Context, roomID, userID string) (int, error)
	GetRoomLastReadAt(ctx context.Context, roomID, userID string) (time.Time, error)
	CountUnreadInRoomAfter(ctx context.Context, roomID, userID string, lastReadAt time.Time) (int, error)
	MarkMessageAsReadBy(ctx context.Context, messageID string, userID string) error
	
	// GetConversations retrieves DM conversations for a user.
	GetConversations(ctx context.Context, userID string) ([]*Conversation, error)

	// MarkAsRead marks all messages in a conversation (room or DM) as read by userID
	MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error
}

// Conversation represents a summary of a chat (DM).
type Conversation struct {
	OtherUserID     string    `json:"other_user_id"`
	OtherUsername   string    `json:"other_username"`
	LastMessage     string    `json:"last_message"`
	LastMessageTime time.Time `json:"last_message_time"`
	UnreadCount     int       `json:"unread_count"`
	LastReadAt      time.Time `json:"last_read_at,omitempty"`
}

// MessageUsecase defines the interface for message business logic.
type MessageUsecase interface {
	// SendMessage handles the business logic of sending a message.
	// It should validate the message and delegate to the repository.
	SendMessage(ctx context.Context, msg *Message) error
	
	GetHistory(ctx context.Context, userID, contactID string, limit, offset int) ([]*Message, error)
	
	// Offline Queue
	SaveOfflineMessage(ctx context.Context, userID string, msg *Message) error
	FetchOfflineMessages(ctx context.Context, userID string) ([]*Message, error)
	
	MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error
	MarkMessagesAsReadBy(ctx context.Context, userID string, messageIDs []string) error
}
