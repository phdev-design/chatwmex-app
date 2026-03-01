package domain

import (
	"context"
	"time"
)

// Message represents a chat message.
// Content is stored encrypted in the database but decrypted in this domain model.
type Message struct {
	ID         string    `json:"id"`
	SenderID   string    `json:"sender_id"`
	ReceiverID string    `json:"receiver_id,omitempty"` // For 1-on-1 chat, empty if RoomID is set
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
	// MarkAsRead marks all messages in a conversation (room or DM) as read by userID
	MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error
}

// MessageUsecase defines the interface for message business logic.
type MessageUsecase interface {
	// SendMessage handles the business logic of sending a message.
	// It should validate the message and delegate to the repository.
	SendMessage(ctx context.Context, msg *Message) error
	
	GetHistory(ctx context.Context, userID, contactID string, limit, offset int) ([]*Message, error)
	MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error
}
