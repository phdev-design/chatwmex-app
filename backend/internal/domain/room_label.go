package domain

import (
	"context"
	"time"
)

type RoomLabel struct {
	ID        string    `json:"id" bson:"_id,omitempty"`
	UserID    string    `json:"user_id" bson:"user_id"`
	Name      string    `json:"name" bson:"name"`
	SortOrder int       `json:"sort_order" bson:"sort_order"`
	RoomIDs   []string  `json:"room_ids" bson:"room_ids"`
	IsEnabled bool      `json:"is_enabled" bson:"is_enabled"`
	CreatedAt time.Time `json:"created_at" bson:"created_at"`
	UpdatedAt time.Time `json:"updated_at" bson:"updated_at"`
}

type RoomLabelRepository interface {
	Create(ctx context.Context, label *RoomLabel) error
	GetByUserID(ctx context.Context, userID string) ([]*RoomLabel, error)
	GetByID(ctx context.Context, id string) (*RoomLabel, error)
	Update(ctx context.Context, label *RoomLabel) error
	Delete(ctx context.Context, id string, userID string) error
	ReorderLabels(ctx context.Context, userID string, orderedIDs []string) error
}

type RoomLabelUsecase interface {
	CreateLabel(ctx context.Context, userID, name string) (*RoomLabel, error)
	GetUserLabels(ctx context.Context, userID string) ([]*RoomLabel, error)
	UpdateLabel(ctx context.Context, userID, labelID, name string, isEnabled bool) (*RoomLabel, error)
	DeleteLabel(ctx context.Context, userID, labelID string) error
	ReorderLabels(ctx context.Context, userID string, orderedIDs []string) error
	AddRoomToLabel(ctx context.Context, userID, labelID, roomID string) error
	RemoveRoomFromLabel(ctx context.Context, userID, labelID, roomID string) error
}
