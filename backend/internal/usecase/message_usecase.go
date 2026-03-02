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
	roomRepo       domain.RoomRepository
	onlineRepo     domain.OnlineRepository
	contextTimeout time.Duration
}

// NewMessageUsecase creates a new instance of MessageUsecase.
func NewMessageUsecase(
	repo domain.MessageRepository,
	roomRepo domain.RoomRepository,
	onlineRepo domain.OnlineRepository,
	timeout time.Duration,
) domain.MessageUsecase {
	return &messageUsecase{
		messageRepo:    repo,
		roomRepo:       roomRepo,
		onlineRepo:     onlineRepo,
		contextTimeout: timeout,
	}
}

func (u *messageUsecase) SendMessage(c context.Context, msg *domain.Message) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// 1) Basic Validation
	if strings.TrimSpace(msg.SenderID) == "" {
		return errors.New("sender ID cannot be empty")
	}

	if strings.TrimSpace(msg.Content) == "" {
		return errors.New("message content cannot be empty")
	}

	// 2) Ensure either ReceiverID or RoomID is present.
	if strings.TrimSpace(msg.ReceiverID) == "" && strings.TrimSpace(msg.RoomID) == "" {
		return errors.New("receiver ID or room ID must be provided")
	}

	// 3) Group message routing rules:
	//    - When RoomID is set, we verify the sender is a member of the room.
	//    - For each other member, if they are offline, we store the message in their offline queue.
	if strings.TrimSpace(msg.RoomID) != "" {
		members, err := u.roomRepo.GetMembers(ctx, msg.RoomID)
		if err != nil {
			return err
		}
		isMember := false
		for _, memberID := range members {
			if memberID == msg.SenderID {
				isMember = true
				break
			}
		}
		if !isMember {
			return errors.New("unauthorized")
		}

		onlineMap, err := u.onlineRepo.GetOnlineUsers(ctx, members)
		if err != nil {
			return err
		}

		// Store offline copies for members who are not online (exclude sender).
		for _, memberID := range members {
			if memberID == msg.SenderID {
				continue
			}
			if !onlineMap[memberID] {
				if err := u.messageRepo.StoreOfflineMessage(ctx, memberID, msg); err != nil {
					return err
				}
			}
		}
	}

	// 4) Set server timestamp to ensure canonical ordering.
	msg.CreatedAt = time.Now()

	// 5) Persist the message for history (encryption handled by repository).
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

func (u *messageUsecase) MarkMessagesAsReadBy(ctx context.Context, userID string, messageIDs []string) error {
	ctx, cancel := context.WithTimeout(ctx, u.contextTimeout)
	defer cancel()

	for _, messageID := range messageIDs {
		if messageID == "" {
			continue
		}
		if err := u.messageRepo.MarkMessageAsReadBy(ctx, messageID, userID); err != nil {
			return err
		}
	}
	return nil
}
