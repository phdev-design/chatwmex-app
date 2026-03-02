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
	userRepo       domain.UserRepository
	deviceRepo     domain.DeviceRepository
	pushService    domain.PushNotificationService
	contextTimeout time.Duration
}

// NewMessageUsecase creates a new instance of MessageUsecase.
func NewMessageUsecase(
	repo domain.MessageRepository,
	roomRepo domain.RoomRepository,
	onlineRepo domain.OnlineRepository,
	userRepo domain.UserRepository,
	deviceRepo domain.DeviceRepository,
	pushService domain.PushNotificationService,
	timeout time.Duration,
) domain.MessageUsecase {
	return &messageUsecase{
		messageRepo:    repo,
		roomRepo:       roomRepo,
		onlineRepo:     onlineRepo,
		userRepo:       userRepo,
		deviceRepo:     deviceRepo,
		pushService:    pushService,
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

	offlineUserIDs := make([]string, 0)

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
				offlineUserIDs = append(offlineUserIDs, memberID)
			}
		}
	} else if strings.TrimSpace(msg.ReceiverID) != "" {
		isOnline, err := u.onlineRepo.IsUserOnline(ctx, msg.ReceiverID)
		if err == nil && !isOnline {
			if err := u.messageRepo.StoreOfflineMessage(ctx, msg.ReceiverID, msg); err != nil {
				return err
			}
			offlineUserIDs = append(offlineUserIDs, msg.ReceiverID)
		}
	}

	// 4) Set server timestamp to ensure canonical ordering.
	msg.CreatedAt = time.Now()

	// 5) Persist the message for history (encryption handled by repository).
	if err := u.messageRepo.StoreMessage(ctx, msg); err != nil {
		return err
	}

	if u.pushService != nil && len(offlineUserIDs) > 0 {
		offlineUsers := append([]string(nil), offlineUserIDs...)
		messageCopy := *msg
		go u.pushToOfflineUsers(offlineUsers, &messageCopy)
	}
	return nil
}

func (u *messageUsecase) pushToOfflineUsers(userIDs []string, msg *domain.Message) {
	ctx, cancel := context.WithTimeout(context.Background(), u.contextTimeout)
	defer cancel()

	title, content := u.buildPushContent(ctx, msg)
	roomID := msg.RoomID
	if roomID == "" {
		roomID = msg.SenderID
	}
	data := map[string]interface{}{
		"room_id":   roomID,
		"is_room":   msg.RoomID != "",
		"room_name": title,
	}

	for _, userID := range userIDs {
		devices, err := u.deviceRepo.GetByUserID(ctx, userID)
		if err != nil || len(devices) == 0 {
			continue
		}
		playerIDs := make([]string, 0, len(devices))
		for _, device := range devices {
			if device != nil && device.ID != "" {
				playerIDs = append(playerIDs, device.ID)
			}
		}
		if len(playerIDs) == 0 {
			continue
		}
		_ = u.pushService.SendNotificationToDevices(playerIDs, title, content, data)
	}
}

func (u *messageUsecase) buildPushContent(ctx context.Context, msg *domain.Message) (string, string) {
	title := "新訊息"
	if msg.RoomID != "" {
		if room, err := u.roomRepo.GetByID(ctx, msg.RoomID); err == nil && room != nil && room.Name != "" {
			title = room.Name
		}
	} else if msg.SenderID != "" {
		if user, err := u.userRepo.GetByID(ctx, msg.SenderID); err == nil && user != nil && user.Username != "" {
			title = user.Username
		}
	}

	content := msg.Content
	if msg.Type == "image" {
		content = "傳送了一張圖片"
	}
	return title, content
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

func (u *messageUsecase) GetRoomMessageMap(ctx context.Context, messageIDs []string) (map[string][]string, error) {
	ctx, cancel := context.WithTimeout(ctx, u.contextTimeout)
	defer cancel()

	return u.messageRepo.GetRoomMessageMap(ctx, messageIDs)
}
