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
func (u *messageUsecase) GetHistory(ctx context.Context, userID, contactID string, limit, offset int) ([]*domain.Message, error) {
	ctx, cancel := context.WithTimeout(ctx, u.contextTimeout)
	defer cancel()

	return u.messageRepo.GetHistory(ctx, userID, contactID, limit, offset)
}

// SaveOfflineMessage stores a message for offline delivery.
func (u *messageUsecase) SaveOfflineMessage(c context.Context, userID string, msg *domain.Message) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.messageRepo.StoreOfflineMessage(ctx, userID, msg)
}

// FetchOfflineMessages retrieves and clears offline messages for a user.
func (u *messageUsecase) FetchOfflineMessages(c context.Context, userID string) ([]*domain.Message, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.messageRepo.GetOfflineMessages(ctx, userID)
}

func (u *messageUsecase) MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error {
	ctx, cancel := context.WithTimeout(ctx, u.contextTimeout)
	defer cancel()

	return u.messageRepo.MarkAsRead(ctx, userID, conversationID, isRoom)
}
