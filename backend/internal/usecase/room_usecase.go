package usecase

import (
	"context"
	"sort"
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

func (u *roomUsecase) CreateRoom(c context.Context, name string, ownerID string) (*domain.Room, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	room := &domain.Room{
		Name:    name,
		OwnerID: ownerID,
		Members: []string{ownerID}, // Owner is the first member
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

func (u *roomUsecase) GetRoomMembers(c context.Context, roomID string) ([]string, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()
	return u.roomRepo.GetMembers(ctx, roomID)
}

func (u *roomUsecase) GetUserRooms(c context.Context, userID string) ([]*domain.Room, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// 1. Get Group Rooms
	rooms, err := u.roomRepo.GetUserRooms(ctx, userID)
	if err != nil {
		return nil, err
	}

	for _, room := range rooms {
		room.Type = "group"
		// If needed, fetch last message for group rooms here
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
			Type:            "dm",
			LastMessage:     conv.LastMessage,
			LastMessageTime: conv.LastMessageTime,
			UnreadCount:     conv.UnreadCount,
			UpdatedAt:       conv.LastMessageTime,
		})
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
