package usecase

import (
	"context"
	"errors"
	"strings"
	"time"

	"chatwmex_backend/internal/domain"
)

type messageUsecase struct {
	messageRepo    domain.MessageRepository
	contextTimeout time.Duration
}

// NewMessageUsecase creates a new instance of MessageUsecase.
func NewMessageUsecase(repo domain.MessageRepository, timeout time.Duration) domain.MessageUsecase {
	return &messageUsecase{
		messageRepo:    repo,
		contextTimeout: timeout,
	}
}

// SendMessage handles the business logic of sending a message.
func (u *messageUsecase) SendMessage(c context.Context, msg *domain.Message) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// 1. Basic Validation
	if strings.TrimSpace(msg.SenderID) == "" {
		return errors.New("sender ID cannot be empty")
	}

	if strings.TrimSpace(msg.Content) == "" {
		return errors.New("message content cannot be empty")
	}

	// Ensure either ReceiverID or RoomID is present, but validation logic depends on business rules.
	// The prompt says: "ReceiverID and RoomID cannot be BOTH empty".
	// It's usually XOR, but let's stick to the prompt: "cannot be empty simultaneously".
	if strings.TrimSpace(msg.ReceiverID) == "" && strings.TrimSpace(msg.RoomID) == "" {
		return errors.New("receiver ID or room ID must be provided")
	}

	// 2. Set Server Timestamp
	// Force the creation time to be now, controlled by the server.
	msg.CreatedAt = time.Now()

	// 3. Persistence
	// The repository handles encryption internally.
	return u.messageRepo.StoreMessage(ctx, msg)
}

// GetChatHistory retrieves the chat history for a user.
func (u *messageUsecase) GetChatHistory(c context.Context, userID string, contactID string, limit int, offset int) ([]*domain.Message, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// Pagination safety
	if limit <= 0 {
		limit = 20 // Default limit
	}
	if limit > 100 {
		limit = 100 // Max limit to prevent abuse
	}

	// Query repository
	return u.messageRepo.GetHistoryMessages(ctx, userID, contactID, limit, offset)
}
