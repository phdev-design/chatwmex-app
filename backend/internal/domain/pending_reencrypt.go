package domain

import (
	"context"
	"time"
)

// PendingReEncryptRequest represents a re-encrypt request that needs to be delivered
// when the sender comes back online. This is used to persist re_encrypt_request
// messages when the sender is offline, ensuring they are not lost.
type PendingReEncryptRequest struct {
	ID         string    `json:"id"`
	MessageID  string    `json:"message_id"`  // The original message ID that needs re-encryption
	SenderID   string    `json:"sender_id"`   // The user who sent the original message (currently offline)
	ReceiverID string    `json:"receiver_id"` // The user requesting re-encryption
	RoomID     string    `json:"room_id"`     // The chat room ID
	CreatedAt  time.Time `json:"created_at"`  // Timestamp when request was created
	ExpiresAt  time.Time `json:"expires_at"`  // Expiration timestamp (7 days from creation)
}

// PendingReEncryptRepository defines the interface for pending re-encrypt request persistence.
type PendingReEncryptRepository interface {
	// Store saves a pending re-encrypt request to the repository.
	Store(ctx context.Context, req *PendingReEncryptRequest) error

	// GetBySenderID retrieves all pending requests for a specific sender, sorted by creation time.
	GetBySenderID(ctx context.Context, senderID string) ([]*PendingReEncryptRequest, error)

	// Delete removes a pending request by its ID.
	Delete(ctx context.Context, id string) error

	// DeleteByMessageID removes a pending request by message ID and receiver ID.
	// This is useful when a request is successfully delivered.
	DeleteByMessageID(ctx context.Context, messageID, receiverID string) error
}
