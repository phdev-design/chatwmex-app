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
	CreatedAt  time.Time `json:"created_at"`
}

// MessageRepository defines the interface for message data persistence.
type MessageRepository interface {
	// StoreMessage saves a message to the repository.
	// Implementation should handle encryption before storage.
	StoreMessage(ctx context.Context, msg *Message) error
	
	// GetHistoryMessages retrieves message history between a user and a contact (user or room).
	// contactID can be another userID (for 1-on-1) or a roomID (for group chat).
	GetHistoryMessages(ctx context.Context, userID string, contactID string, limit int, offset int) ([]*Message, error)
}

// MessageUsecase defines the interface for message business logic.
type MessageUsecase interface {
	// SendMessage handles the business logic of sending a message.
	// It should validate the message and delegate to the repository.
	SendMessage(ctx context.Context, msg *Message) error
	
	// GetChatHistory retrieves the chat history for a user.
	GetChatHistory(ctx context.Context, userID string, contactID string, limit int, offset int) ([]*Message, error)
}
