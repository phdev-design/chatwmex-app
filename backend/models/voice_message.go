package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// VoiceMessage 代表一條語音消息
type VoiceMessage struct {
	ID         primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	SenderID   string             `bson:"sender_id" json:"sender_id"`
	SenderName string             `bson:"sender_name" json:"sender_name"`
	Room       string             `bson:"room" json:"room"`
	FilePath   string             `bson:"file_path" json:"file_path"` // 加密後的文件路徑
	Duration   int                `bson:"duration" json:"duration"`   // 語音時長（秒）
	FileSize   int64              `bson:"file_size" json:"file_size"` // 文件大小（字節）
	Timestamp  time.Time          `bson:"timestamp" json:"timestamp"`
	Type       string             `bson:"type" json:"type"` // 消息類型，固定為 "voice"
}