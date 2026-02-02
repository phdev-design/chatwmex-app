package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// ChatRoom 代表一個聊天室
type ChatRoom struct {
	ID              primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	Name            string             `bson:"name" json:"name"`
	Description     string             `bson:"description,omitempty" json:"description,omitempty"` // 群組描述
	IsGroup         bool               `bson:"is_group" json:"is_group"`
	GroupType       string             `bson:"group_type" json:"group_type"`   // public, private, invite_only
	MaxMembers      int                `bson:"max_members" json:"max_members"` // 最大成員數，預設 1000
	Participants    []string           `bson:"participants" json:"participants"`
	Admins          []string           `bson:"admins" json:"admins"` // 群組管理員
	CreatedBy       string             `bson:"created_by" json:"created_by"`
	LastMessage     string             `bson:"last_message" json:"last_message"`
	LastMessageTime time.Time          `bson:"last_message_time" json:"last_message_time"`
	UnreadCount     int                `bson:"unread_count" json:"unread_count"`
	AvatarURL       string             `bson:"avatar_url,omitempty" json:"avatar_url,omitempty"`
	IsActive        bool               `bson:"is_active" json:"is_active"` // 群組是否活躍
	CreatedAt       time.Time          `bson:"created_at" json:"created_at"`
	UpdatedAt       time.Time          `bson:"updated_at" json:"updated_at"`
}

// GroupInvitation 群組邀請模型
type GroupInvitation struct {
	ID           primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	GroupID      primitive.ObjectID `bson:"group_id" json:"group_id"`
	InviterID    string             `bson:"inviter_id" json:"inviter_id"`
	InviteeID    string             `bson:"invitee_id" json:"invitee_id"`
	InviteeEmail string             `bson:"invitee_email,omitempty" json:"invitee_email,omitempty"`
	Status       string             `bson:"status" json:"status"`                       // pending, accepted, rejected, expired
	Message      string             `bson:"message,omitempty" json:"message,omitempty"` // 邀請消息
	ExpiresAt    time.Time          `bson:"expires_at" json:"expires_at"`
	CreatedAt    time.Time          `bson:"created_at" json:"created_at"`
	UpdatedAt    time.Time          `bson:"updated_at" json:"updated_at"`
}

// GroupMember 群組成員模型
type GroupMember struct {
	UserID   string    `bson:"user_id" json:"user_id"`
	Username string    `bson:"username" json:"username"`
	Role     string    `bson:"role" json:"role"` // owner, admin, member
	JoinedAt time.Time `bson:"joined_at" json:"joined_at"`
	IsActive bool      `bson:"is_active" json:"is_active"`
	LastSeen time.Time `bson:"last_seen,omitempty" json:"last_seen,omitempty"`
}
