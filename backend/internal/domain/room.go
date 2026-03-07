package domain

import (
	"context"
	"time"
)

// Room represents a chat room (group) or a DM conversation.
type Room struct {
	ID              string    `json:"id"`
	Name            string    `json:"name"`
	AvatarURL       string    `json:"avatar_url,omitempty"`
	OwnerID         string    `json:"owner_id,omitempty"`
	Members         []string  `json:"members,omitempty"` // List of UserIDs
	Type            string    `json:"type"`              // "group" or "dm"
	LastMessage     string    `json:"last_message,omitempty"`
	LastMessageType string    `json:"last_message_type,omitempty"` // 👉 新增這個欄位
	LastMessageTime time.Time `json:"last_message_time,omitempty"`
	UnreadCount     int       `json:"unread_count"`
	LastReadAt      time.Time `json:"last_read_at,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// RoomRepository defines the interface for room data persistence.
type RoomRepository interface {
	Create(ctx context.Context, room *Room) error
	GetByID(ctx context.Context, id string) (*Room, error)
	AddMember(ctx context.Context, roomID string, userID string) error
	RemoveMember(ctx context.Context, roomID string, userID string) error
	DeleteRoom(ctx context.Context, roomID string) error
	GetMembers(ctx context.Context, roomID string) ([]string, error)
	// GetUserRooms retrieves all rooms a user is a member of.
	GetUserRooms(ctx context.Context, userID string) ([]*Room, error)
	UpdateRoom(ctx context.Context, roomID string, update map[string]interface{}) error
	UpdateOwner(ctx context.Context, roomID string, newOwnerID string) error
}

// RoomUsecase defines the interface for room business logic.
type RoomUsecase interface {
	CreateRoom(ctx context.Context, name string, ownerID string, memberIDs []string) (*Room, error)
	JoinRoom(ctx context.Context, roomID string, userID string) error
	LeaveRoom(ctx context.Context, roomID string, userID string) error
	KickMember(ctx context.Context, roomID string, ownerID string, memberID string) error
	DeleteRoom(ctx context.Context, roomID string, ownerID string) error
	GetRoomMembers(ctx context.Context, roomID string) ([]string, error)
	GetUserRooms(ctx context.Context, userID string, keyword string) ([]*Room, error)
	GetRoomMedia(ctx context.Context, userID, roomID, reqType, cursor string, limit int) ([]Message, bool, error)
	UpdateRoom(ctx context.Context, roomID string, ownerID string, name *string, avatarURL *string) error
	TransferOwnership(ctx context.Context, roomID string, currentOwnerID string, newOwnerID string) error
}
