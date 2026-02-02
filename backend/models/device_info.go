package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// DeviceInfo 設備信息模型
type DeviceInfo struct {
	ID          primitive.ObjectID `bson:"_id,omitempty" json:"id,omitempty"`
	UserID      primitive.ObjectID `bson:"user_id" json:"user_id"`
	IPAddress   string             `bson:"ip_address" json:"ip_address"`
	UserAgent   string             `bson:"user_agent" json:"user_agent"`
	DeviceType  string             `bson:"device_type" json:"device_type"`   // mobile, desktop, tablet
	OS          string             `bson:"os" json:"os"`                     // iOS, Android, Windows, macOS, Linux
	Browser     string             `bson:"browser" json:"browser"`           // Chrome, Safari, Firefox, etc.
	DeviceModel string             `bson:"device_model" json:"device_model"` // iPhone 13, Samsung Galaxy S21, etc.
	ScreenSize  string             `bson:"screen_size" json:"screen_size"`   // 1920x1080, 375x667, etc.
	Language    string             `bson:"language" json:"language"`         // zh-TW, en-US, etc.
	Timezone    string             `bson:"timezone" json:"timezone"`         // Asia/Taipei, America/New_York, etc.
	IsMobile    bool               `bson:"is_mobile" json:"is_mobile"`
	IsTablet    bool               `bson:"is_tablet" json:"is_tablet"`
	IsDesktop   bool               `bson:"is_desktop" json:"is_desktop"`
	LoginTime   time.Time          `bson:"login_time" json:"login_time"`
	LastActive  time.Time          `bson:"last_active" json:"last_active"`
	CreatedAt   time.Time          `bson:"created_at" json:"created_at"`
	UpdatedAt   time.Time          `bson:"updated_at" json:"updated_at"`
}

// LoginSession 登入會話模型
type LoginSession struct {
	ID           primitive.ObjectID `bson:"_id,omitempty" json:"id,omitempty"`
	UserID       primitive.ObjectID `bson:"user_id" json:"user_id"`
	DeviceInfo   DeviceInfo         `bson:"device_info" json:"device_info"`
	SessionToken string             `bson:"session_token" json:"session_token"`
	IsActive     bool               `bson:"is_active" json:"is_active"`
	LoginTime    time.Time          `bson:"login_time" json:"login_time"`
	LastActive   time.Time          `bson:"last_active" json:"last_active"`
	LogoutTime   *time.Time         `bson:"logout_time,omitempty" json:"logout_time,omitempty"`
	CreatedAt    time.Time          `bson:"created_at" json:"created_at"`
	UpdatedAt    time.Time          `bson:"updated_at" json:"updated_at"`
}
