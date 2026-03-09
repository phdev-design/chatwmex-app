package usecase

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"strings"
	"time"

	"chatwmex_backend/internal/domain"
	"chatwmex_backend/internal/utils"

	"github.com/redis/go-redis/v9"
)

type messageUsecase struct {
	messageRepo    domain.MessageRepository
	roomRepo       domain.RoomRepository
	onlineRepo     domain.OnlineRepository
	userRepo       domain.UserRepository
	deviceRepo     domain.DeviceRepository
	pushService    domain.PushNotificationService
	settingUsecase domain.ChatSettingUsecase // 👉 新增設定的 Usecase
	redisClient    *redis.Client
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
	settingUsecase domain.ChatSettingUsecase, // 👉 加入參數
	redisClient *redis.Client,
	timeout time.Duration,
) domain.MessageUsecase {
	return &messageUsecase{
		messageRepo:    repo,
		roomRepo:       roomRepo,
		onlineRepo:     onlineRepo,
		userRepo:       userRepo,
		deviceRepo:     deviceRepo,
		pushService:    pushService,
		settingUsecase: settingUsecase, // 👉 設定依賴
		redisClient:    redisClient,
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

	pushTargets := make([]string, 0)

	// 👉 自動刪除訊息：判斷此對話是否開啟計時器
	var chatID string
	if msg.RoomID != "" {
		chatID = msg.RoomID
	} else {
		// DM 的 ChatID 組合規則，必須確保 A->B 和 B->A 的 ID 一致
		if msg.SenderID < msg.ReceiverID {
			chatID = msg.SenderID + "_" + msg.ReceiverID
		} else {
			chatID = msg.ReceiverID + "_" + msg.SenderID
		}
	}

	if chatID != "" && u.settingUsecase != nil {
		setting, err := u.settingUsecase.GetChatSetting(ctx, chatID)
		if err == nil && setting != nil && setting.DisappearingTimer > 0 {
			expiresAt := time.Now().Add(time.Duration(setting.DisappearingTimer) * time.Second)
			msg.ExpiresAt = &expiresAt
		}
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
			// 👉 ALWAYS include in push notification targets to ensure background delivery
			pushTargets = append(pushTargets, memberID)
		}
	} else if strings.TrimSpace(msg.ReceiverID) != "" {
		isOnline, err := u.onlineRepo.IsUserOnline(ctx, msg.ReceiverID)
		if err == nil && !isOnline {
			if err := u.messageRepo.StoreOfflineMessage(ctx, msg.ReceiverID, msg); err != nil {
				return err
			}
		}
		// 👉 ALWAYS include in push notification targets to ensure background delivery
		pushTargets = append(pushTargets, msg.ReceiverID)
	}

	// 4) Set server timestamp to ensure canonical ordering.
	msg.CreatedAt = time.Now()

	// 👉 E2EE 架構下，msg.Content 已經是密文，後端無法再做 URL 解析。
	// 改為：如果前端有傳 LinkPreview 且含有 URL，就將訊息類型設為 "link"
	if msg.LinkPreview != nil && msg.LinkPreview.URL != "" {
		msg.Type = "link"
	} else {
		msg.LinkPreview = nil // 清除無效的預覽資料
	}

	// 5) Persist the message for history (encryption handled by repository).
	if err := u.messageRepo.StoreMessage(ctx, msg); err != nil {
		return err
	}

	if u.pushService != nil && len(pushTargets) > 0 {
		targetsCopy := append([]string(nil), pushTargets...)
		messageCopy := *msg
		go u.pushToOfflineUsers(targetsCopy, &messageCopy)
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
		// 👉 將原始加密內容與發送者 ID 放進隱藏資料中，供前端本地解密
		"encrypted_content": msg.Content,
		"sender_id":         msg.SenderID,
		"message_id":        msg.ID,
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
        
        // 👉 加入了錯誤處理與日誌記錄
		if err := u.pushService.SendNotificationToDevices(playerIDs, title, content, data); err != nil {
			log.Printf("❌ 推播發送失敗 (針對 user %s): %v\n", userID, err)
		} else {
			log.Printf("✅ 推播發送成功 (針對 user %s)\n", userID)
		}
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
	// 👉 判斷如果是 E2EE 密文（通常大於一定長度，且不含一般中英文字型特徵，或者簡單的長度/Base64判斷）
	// 在後端由於不負責解密，最安全的做法是：如果是 text，全部統一顯示「您收到了一則新訊息」或「🔒 一則加密訊息」。
	if msg.Type == "text" {
		content = "🔒 一則加密訊息"
	} else if msg.Type == "image" {
		content = "傳送了一張圖片"
	} else if msg.Type == "audio" || msg.Type == "voice" {
		content = "傳送了一則語音訊息"
	} else if msg.Type == "file" || msg.Type == "document" {
		content = "傳送了一個檔案"
	}

	return title, content
}

func (u *messageUsecase) GetLinkPreview(ctx context.Context, input string) (*domain.LinkPreview, error) {
	url := utils.ExtractFirstURL(input)
	if strings.TrimSpace(url) == "" {
		return nil, errors.New("no url found")
	}
	cacheKey := "link_preview:" + url

	if u.redisClient != nil {
		cached, err := u.redisClient.Get(ctx, cacheKey).Result()
		if err == nil && cached != "" {
			var cachedPreview domain.LinkPreview
			if unmarshalErr := json.Unmarshal([]byte(cached), &cachedPreview); unmarshalErr == nil {
				return &cachedPreview, nil
			}
		}
		if err != nil && err != redis.Nil {
			log.Printf("link preview cache read failed: %v", err)
		}
	}

	preview, err := utils.FetchLinkPreview(input)
	if err != nil || preview == nil || preview.URL == "" {
		if err != nil {
			return nil, err
		}
		return nil, errors.New("no preview found")
	}
	if u.redisClient == nil {
		return preview, nil
	}
	payload, marshalErr := json.Marshal(preview)
	if marshalErr == nil {
		if setErr := u.redisClient.Set(ctx, cacheKey, payload, 24*time.Hour).Err(); setErr != nil {
			log.Printf("link preview cache write failed: %v", setErr)
		}
	}
	return preview, nil
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

func (u *messageUsecase) ToggleReaction(ctx context.Context, messageID string, userID string, emoji string) (*domain.Message, error) {
	ctx, cancel := context.WithTimeout(ctx, u.contextTimeout)
	defer cancel()

	return u.messageRepo.ToggleReaction(ctx, messageID, userID, emoji)
}

func (u *messageUsecase) UnsendMessage(ctx context.Context, messageID string, userID string) (*domain.Message, error) {
	ctx, cancel := context.WithTimeout(ctx, u.contextTimeout)
	defer cancel()

	return u.messageRepo.UnsendMessage(ctx, messageID, userID)
}

func (u *messageUsecase) DeleteMessage(ctx context.Context, messageID string, userID string) error {
	if strings.TrimSpace(messageID) == "" {
		return errors.New("message ID cannot be empty")
	}
	if strings.TrimSpace(userID) == "" {
		return errors.New("user ID cannot be empty")
	}
	ctx, cancel := context.WithTimeout(ctx, u.contextTimeout)
	defer cancel()
	return u.messageRepo.SoftDeleteMessage(ctx, messageID, userID)
}

func (u *messageUsecase) UpdateMessageStatus(c context.Context, messageID string, status string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.messageRepo.UpdateMessageStatus(ctx, messageID, status)
}