package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// User 表示用戶模型
type User struct {
	ID        primitive.ObjectID `bson:"_id,omitempty" json:"id,omitempty"`
	Username  string             `bson:"username" json:"username"`
	Email     string             `bson:"email" json:"email"`
	Password  string             `bson:"password" json:"-"` // json:"-" 表示在序列化時不包含此欄位
	Language  string             `bson:"language" json:"language"`
	AvatarURL *string            `bson:"avatar_url,omitempty" json:"avatar_url,omitempty"`
	IsOnline  bool               `bson:"is_online" json:"is_online"`
	LastSeen  *time.Time         `bson:"last_seen,omitempty" json:"last_seen,omitempty"`
	// 帳號狀態相關字段
	IsActive       bool       `bson:"is_active" json:"is_active"`                                 // 帳號是否活躍
	IsDeleted      bool       `bson:"is_deleted" json:"is_deleted"`                               // 帳號是否已刪除
	DeletedAt      *time.Time `bson:"deleted_at,omitempty" json:"deleted_at,omitempty"`           // 刪除時間
	DeletionReason *string    `bson:"deletion_reason,omitempty" json:"deletion_reason,omitempty"` // 刪除原因
	CreatedAt      time.Time  `bson:"created_at" json:"created_at"`
	UpdatedAt      time.Time  `bson:"updated_at" json:"updated_at"`
}
