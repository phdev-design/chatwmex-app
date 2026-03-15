package domain

import (
	"context"
	"time"
)

// 🔐 E2EE Auto-Resend Control Message Types
// 這些訊息類型不會寫入資料庫，僅用於 WebSocket 即時通訊
const (
	MessageTypeReEncryptRequest  = "re_encrypt_request"
	MessageTypeReEncryptResponse = "re_encrypt_response"
)

// MessageReceipt represents a status update for a message (delivered/read).
type MessageReceipt struct {
	MessageID string `json:"message_id"`
	RoomID    string `json:"room_id"`
	Status    string `json:"status"`    // "sent", "delivered", "read"
	SenderID  string `json:"sender_id"` // The one who needs to be notified (original sender)
}

// DeliveredReceiptNotification represents a queued delivery receipt for offline users.
type DeliveredReceiptNotification struct {
	SenderID          string    `json:"sender_id"`            // 原始訊息發送者，需要收到通知的人
	MessageIDs        []string  `json:"message_ids"`          // 已被 delivered 的訊息 IDs
	DeliveredByUserID string    `json:"delivered_by_user_id"` // 誰 delivered 了這些訊息
	ConversationID    string    `json:"conversation_id"`      // 前端用來識別對話的 ID
	CreatedAt         time.Time `json:"created_at"`
}

// Message represents a chat message.
// Content is stored encrypted in the database but decrypted in this domain model.
type Message struct {
	ID               string              `json:"id"`
	ClientMsgID      string              `json:"client_msg_id,omitempty"` // For idempotency and ACK tracking
	SenderID         string              `json:"sender_id"`
	ReceiverID       string              `json:"receiver_id,omitempty"` // For 1-on-1 chat, empty if RoomID is set
	RoomID           string              `json:"room_id,omitempty"`     // For Group chat, empty if ReceiverID is set
	ReplyToMessageID string              `json:"reply_to_message_id,omitempty"`
	Reactions        map[string][]string `json:"reactions,omitempty"`
	IsUnsent         bool                `json:"is_unsent,omitempty"`
	DeletedBy        []string            `json:"deleted_by,omitempty"`
	Content          string              `json:"content"` // Business level content (plaintext)
	Type             string              `json:"type"`    // "text", "image", "read_receipt"
	// Status 訊息传送狀態："sent" | "delivered" | "read"
	Status      string       `json:"status,omitempty" bson:"status,omitempty"`
	IsRead      bool         `json:"is_read,omitempty"` // For backwards compatibility or simple 1-on-1
	ReadBy      []string     `json:"read_by"`           // List of UserIDs who read the message
	LinkPreview *LinkPreview `json:"link_preview,omitempty" bson:"link_preview,omitempty"`
	ExpiresAt   *time.Time   `json:"expires_at,omitempty"` // For disappearing messages (MongoDB TTL)
	CreatedAt   time.Time    `json:"created_at"`
	// 🔐 E2EE Group Media: FileKeysFanout 用於群組媒體加密
	// 每個成員的 fileKey 用該成員的公鑰加密，格式：{"is_fanout": true, "keys": {userId: encryptedKey, ...}}
	FileKeysFanout map[string]interface{} `json:"file_keys_fanout,omitempty" bson:"file_keys_fanout,omitempty"`
	// 🔐 E2EE Group Text Messages: EncryptedContentsFanout 用於群組文字訊息加密
	// 每個成員的訊息內容用該成員的公鑰加密，格式：{userId: encryptedContent, ...}
	// key = userId, value = 該成員專屬的加密密文（base64 字串）
	EncryptedContentsFanout map[string]string `json:"encrypted_contents_fanout,omitempty" bson:"encrypted_contents_fanout,omitempty"`
}

type LinkPreview struct {
	URL         string `json:"url,omitempty" bson:"url,omitempty"`
	Title       string `json:"title,omitempty" bson:"title,omitempty"`
	Description string `json:"description,omitempty" bson:"description,omitempty"`
	ImageURL    string `json:"image_url,omitempty" bson:"image_url,omitempty"`
}

// MessageRepository defines the interface for message data persistence.
type MessageRepository interface {
	// StoreMessage saves a message to the repository.
	// Implementation should handle encryption before storage.
	StoreMessage(ctx context.Context, msg *Message) error

	GetHistory(ctx context.Context, userID, contactID string, limit, offset int) ([]*Message, error)
	// Offline Message Handling
	StoreOfflineMessage(ctx context.Context, userID string, msg *Message) error
	GetOfflineMessages(ctx context.Context, userID string) ([]*Message, error)

	CountUnreadInRoom(ctx context.Context, roomID, userID string) (int, error)
	GetRoomLastReadAt(ctx context.Context, roomID, userID string) (time.Time, error)
	CountUnreadInRoomAfter(ctx context.Context, roomID, userID string, lastReadAt time.Time) (int, error)
	MarkMessageAsReadBy(ctx context.Context, messageID string, userID string) error
	GetRoomMessageMap(ctx context.Context, messageIDs []string) (map[string][]string, error)
	GetRoomResources(ctx context.Context, userID, roomID, category, cursor string, limit int) ([]Message, error)
	ToggleReaction(ctx context.Context, messageID string, userID string, emoji string) (*Message, error)
	UnsendMessage(ctx context.Context, messageID string, userID string) (*Message, error)
	SoftDeleteMessage(ctx context.Context, messageID string, userID string) error

	GetConversations(ctx context.Context, userID string) ([]*Conversation, error)

	GetLastRoomMessage(ctx context.Context, roomID string) (*Message, error)

	// MarkAsRead marks all messages in a conversation (room or DM) as read by userID
	MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error

	// ClearRoomMessages 刪除指定 Room 或私訊對話的所有訊息
	ClearRoomMessages(ctx context.Context, roomID, userID string) error

	// UpdateMessageStatus 更新單筆訊息狀態
	UpdateMessageStatus(ctx context.Context, messageID string, status string) error

	// Delivered Receipt Offline Queue
	StoreDeliveredReceiptNotification(ctx context.Context, notification *DeliveredReceiptNotification) error
	FetchAndClearDeliveredReceiptNotifications(ctx context.Context, userID string) ([]*DeliveredReceiptNotification, error)
}

// Conversation represents a summary of a chat (DM).
type Conversation struct {
	OtherUserID        string    `json:"other_user_id"`
	OtherUsername      string    `json:"other_username"`
	OtherUserAvatarURL string    `json:"other_user_avatar_url,omitempty"`
	LastMessage        string    `json:"last_message"`
	LastMessageType    string    `json:"last_message_type"` // 👉 新增這個欄位
	LastMessageTime    time.Time `json:"last_message_time"`
	UnreadCount        int       `json:"unread_count"`
	LastReadAt         time.Time `json:"last_read_at,omitempty"`
}

// MessageUsecase defines the interface for message business logic.
type MessageUsecase interface {
	// SendMessage handles the business logic of sending a message.
	// It should validate the message and delegate to the repository.
	SendMessage(ctx context.Context, msg *Message) error
	GetLinkPreview(ctx context.Context, input string) (*LinkPreview, error)

	GetHistory(ctx context.Context, userID, contactID string, limit, offset int) ([]*Message, error)

	// Offline Queue
	SaveOfflineMessage(ctx context.Context, userID string, msg *Message) error
	FetchOfflineMessages(ctx context.Context, userID string) ([]*Message, error)

	MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error
	MarkMessagesAsReadBy(ctx context.Context, userID string, messageIDs []string) error
	GetRoomMessageMap(ctx context.Context, messageIDs []string) (map[string][]string, error)
	ToggleReaction(ctx context.Context, messageID string, userID string, emoji string) (*Message, error)
	UnsendMessage(ctx context.Context, messageID string, userID string) (*Message, error)
	DeleteMessage(ctx context.Context, messageID string, userID string) error

	// UpdateMessageStatus 處理訊息狀態更新邏輯
	UpdateMessageStatus(ctx context.Context, messageID string, status string) error

	// Delivered Receipt Offline Queue
	StoreDeliveredReceiptNotification(ctx context.Context, notification *DeliveredReceiptNotification) error
	FetchAndClearDeliveredReceiptNotifications(ctx context.Context, userID string) ([]*DeliveredReceiptNotification, error)
}
