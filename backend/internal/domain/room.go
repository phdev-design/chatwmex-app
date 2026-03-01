package domain

import (
	"context"
	"time"
)

// Room represents a chat room (group).
type Room struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	OwnerID   string    `json:"owner_id"`
	Members   []string  `json:"members"` // List of UserIDs
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// RoomRepository defines the interface for room data persistence.
type RoomRepository interface {
	Create(ctx context.Context, room *Room) error
	GetByID(ctx context.Context, id string) (*Room, error)
	AddMember(ctx context.Context, roomID string, userID string) error
	RemoveMember(ctx context.Context, roomID string, userID string) error
	GetMembers(ctx context.Context, roomID string) ([]string, error)
	// GetUserRooms retrieves all rooms a user is a member of.
	GetUserRooms(ctx context.Context, userID string) ([]*Room, error)
}

// RoomUsecase defines the interface for room business logic.
type RoomUsecase interface {
	CreateRoom(ctx context.Context, name string, ownerID string) (*Room, error)
	JoinRoom(ctx context.Context, roomID string, userID string) error
	LeaveRoom(ctx context.Context, roomID string, userID string) error
	GetRoomMembers(ctx context.Context, roomID string) ([]string, error)
	GetUserRooms(ctx context.Context, userID string) ([]*Room, error)
}
