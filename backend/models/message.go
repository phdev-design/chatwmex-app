package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// Message 代表一条聊天讯息
type Message struct {
	ID         primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	SenderID   string             `bson:"sender_id" json:"sender_id"`
	SenderName string             `bson:"sender_name" json:"sender_name"` // 新增：发送者用户名
	Room       string             `bson:"room" json:"room"`
	Content    string             `bson:"content" json:"content"`
	Timestamp  time.Time          `bson:"timestamp" json:"timestamp"`
	Type       string             `bson:"type" json:"type"`                                 // 新增：消息类型
	IsDeleted  bool               `bson:"is_deleted" json:"is_deleted"`                     // 新增：是否已刪除
	DeletedAt  *time.Time         `bson:"deleted_at,omitempty" json:"deleted_at,omitempty"` // 新增：刪除時間
	DeletedBy  *string            `bson:"deleted_by,omitempty" json:"deleted_by,omitempty"` // 新增：刪除者ID
}
