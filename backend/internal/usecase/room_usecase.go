package usecase

import (
	"context"
	"errors"
	"sort"
	"strings"
	"time"

	"chatwmex_backend/internal/domain"
)

type roomUsecase struct {
	roomRepo       domain.RoomRepository
	messageRepo    domain.MessageRepository
	contextTimeout time.Duration
}

func NewRoomUsecase(roomRepo domain.RoomRepository, messageRepo domain.MessageRepository, timeout time.Duration) domain.RoomUsecase {
	return &roomUsecase{
		roomRepo:       roomRepo,
		messageRepo:    messageRepo,
		contextTimeout: timeout,
	}
}

func (u *roomUsecase) CreateRoom(c context.Context, name string, ownerID string, memberIDs []string) (*domain.Room, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	membersMap := map[string]struct{}{}
	if ownerID != "" {
		membersMap[ownerID] = struct{}{}
	}
	for _, memberID := range memberIDs {
		if memberID != "" {
			membersMap[memberID] = struct{}{}
		}
	}
	uniqueMembers := make([]string, 0, len(membersMap))
	for memberID := range membersMap {
		uniqueMembers = append(uniqueMembers, memberID)
	}

	room := &domain.Room{
		Name:    name,
		OwnerID: ownerID,
		Members: uniqueMembers,
		Type:    "group",
	}
	err := u.roomRepo.Create(ctx, room)
	return room, err
}

func (u *roomUsecase) JoinRoom(c context.Context, roomID string, userID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()
	return u.roomRepo.AddMember(ctx, roomID, userID)
}

func (u *roomUsecase) LeaveRoom(c context.Context, roomID string, userID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()
	return u.roomRepo.RemoveMember(ctx, roomID, userID)
}

func (u *roomUsecase) KickMember(c context.Context, roomID string, ownerID string, memberID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	room, err := u.roomRepo.GetByID(ctx, roomID)
	if err != nil {
		return err
	}
	if room.OwnerID != ownerID {
		return errors.New("forbidden")
	}
	if memberID == ownerID {
		return errors.New("cannot_remove_owner")
	}
	return u.roomRepo.RemoveMember(ctx, roomID, memberID)
}

func (u *roomUsecase) DeleteRoom(c context.Context, roomID string, ownerID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	room, err := u.roomRepo.GetByID(ctx, roomID)
	if err != nil {
		return err
	}
	if room.OwnerID != ownerID {
		return errors.New("forbidden")
	}
	return u.roomRepo.DeleteRoom(ctx, roomID)
}

func (u *roomUsecase) GetRoomMembers(c context.Context, roomID string) ([]string, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()
	return u.roomRepo.GetMembers(ctx, roomID)
}

func (u *roomUsecase) GetUserRooms(c context.Context, userID string, keyword string) ([]*domain.Room, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// 1. Get Group Rooms
	rooms, err := u.roomRepo.GetUserRooms(ctx, userID)
	if err != nil {
		return nil, err
	}

	for _, room := range rooms {
		room.Type = "group"
		lastReadAt, err := u.messageRepo.GetRoomLastReadAt(ctx, room.ID, userID)
		if err == nil {
			room.LastReadAt = lastReadAt
		}
		count, err := u.messageRepo.CountUnreadInRoomAfter(ctx, room.ID, userID, room.LastReadAt)
		if err == nil {
			room.UnreadCount = count
		}

		lastMsg, err := u.messageRepo.GetLastRoomMessage(ctx, room.ID)
		if err == nil && lastMsg != nil {
			content := lastMsg.Content
			if lastMsg.LinkPreview != nil && lastMsg.LinkPreview.Title != "" {
				content = lastMsg.LinkPreview.Title
			}
			room.LastMessage = content
			room.LastMessageType = string(lastMsg.Type)
			room.LastMessageTime = lastMsg.CreatedAt
		}
	}

	// 2. Get DM Conversations
	conversations, err := u.messageRepo.GetConversations(ctx, userID)
	if err != nil {
		return nil, err
	}

	for _, conv := range conversations {
		rooms = append(rooms, &domain.Room{
			ID:              conv.OtherUserID, // Use UserID as RoomID for DM
			Name:            conv.OtherUsername,
			AvatarURL:       conv.OtherUserAvatarURL,
			Type:            "dm",
			LastMessage:     conv.LastMessage,
			LastMessageType: conv.LastMessageType, // 👉 映射新欄位
			LastMessageTime: conv.LastMessageTime,
			UnreadCount:     conv.UnreadCount,
			LastReadAt:      conv.LastReadAt,
			UpdatedAt:       conv.LastMessageTime,
		})
	}

	if strings.TrimSpace(keyword) != "" {
		needle := strings.ToLower(strings.TrimSpace(keyword))
		filtered := make([]*domain.Room, 0, len(rooms))
		for _, room := range rooms {
			if strings.Contains(strings.ToLower(room.Name), needle) {
				filtered = append(filtered, room)
			}
		}
		rooms = filtered
	}

	// 3. Sort by last activity (UpdatedAt or LastMessageTime)
	sort.Slice(rooms, func(i, j int) bool {
		t1 := rooms[i].UpdatedAt
		if !rooms[i].LastMessageTime.IsZero() {
			t1 = rooms[i].LastMessageTime
		}

		t2 := rooms[j].UpdatedAt
		if !rooms[j].LastMessageTime.IsZero() {
			t2 = rooms[j].LastMessageTime
		}

		return t1.After(t2)
	})

	return rooms, nil
}

func (u *roomUsecase) GetRoomMedia(c context.Context, userID, roomID, reqType, cursor string, limit int) ([]domain.Message, bool, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	if strings.TrimSpace(roomID) == "" {
		return nil, false, errors.New("room ID is required")
	}
	if limit <= 0 {
		limit = 20
	}
	category := strings.ToLower(strings.TrimSpace(reqType))
	switch category {
	case "", "media", "link", "doc":
	default:
		return nil, false, errors.New("invalid_type")
	}

	members, err := u.roomRepo.GetMembers(ctx, roomID)
	if err != nil {
		errText := err.Error()
		switch {
		case strings.Contains(errText, "invalid object ID"):
			return nil, false, errors.New("invalid_room_id")
		case strings.Contains(errText, "room not found"):
			messages, fetchErr := u.messageRepo.GetRoomResources(ctx, userID, roomID, category, cursor, limit)
			if fetchErr != nil {
				if fetchErr.Error() == "invalid category" {
					return nil, false, errors.New("invalid_type")
				}
				return nil, false, fetchErr
			}
			hasMore := len(messages) > limit
			if hasMore {
				messages = messages[:limit]
			}
			return messages, hasMore, nil
		default:
			return nil, false, err
		}
	}

	isMember := false
	for _, memberID := range members {
		if memberID == userID {
			isMember = true
			break
		}
	}
	if !isMember {
		return nil, false, errors.New("forbidden")
	}

	messages, err := u.messageRepo.GetRoomResources(ctx, userID, roomID, category, cursor, limit)
	if err != nil {
		if err.Error() == "invalid category" {
			return nil, false, errors.New("invalid_type")
		}
		return nil, false, err
	}

	hasMore := len(messages) > limit
	if hasMore {
		messages = messages[:limit]
	}
	return messages, hasMore, nil
}

func (u *roomUsecase) UpdateRoom(c context.Context, roomID string, ownerID string, name *string, avatarURL *string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	room, err := u.roomRepo.GetByID(ctx, roomID)
	if err != nil {
		return err
	}
	if room.OwnerID != ownerID {
		return errors.New("forbidden")
	}

	update := make(map[string]interface{})
	if name != nil {
		update["name"] = *name
	}
	if avatarURL != nil {
		update["avatar_url"] = *avatarURL
	}

	if len(update) == 0 {
		return nil
	}

	return u.roomRepo.UpdateRoom(ctx, roomID, update)
}
