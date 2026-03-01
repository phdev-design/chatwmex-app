package usecase

import (
	"context"
	"time"

	"chatwmex_backend/internal/domain"
)

type roomUsecase struct {
	roomRepo       domain.RoomRepository
	contextTimeout time.Duration
}

func NewRoomUsecase(repo domain.RoomRepository, timeout time.Duration) domain.RoomUsecase {
	return &roomUsecase{
		roomRepo:       repo,
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
	return u.roomRepo.GetUserRooms(ctx, userID)
}
