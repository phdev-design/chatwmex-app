package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// BlockedUser 代表封鎖用戶的記錄
type BlockedUser struct {
	ID        primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	BlockerID string             `bson:"blocker_id" json:"blocker_id"` // 執行封鎖的用戶 ID
	BlockedID string             `bson:"blocked_id" json:"blocked_id"` // 被封鎖的用戶 ID
	CreatedAt time.Time          `bson:"created_at" json:"created_at"`
}
