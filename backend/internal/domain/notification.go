package domain

import "context"

// PushNotificationMessage represents a push notification to be sent via the queue
type PushNotificationMessage struct {
	PlayerIDs []string               `json:"player_ids"` // OneSignal device IDs
	Title     string                 `json:"title"`      // Notification heading
	Content   string                 `json:"content"`    // Notification body
	Data      map[string]interface{} `json:"data"`       // Custom payload
}

// NotificationProducer defines the interface for publishing notification messages to the queue
type NotificationProducer interface {
	// Publish sends a notification message to the queue
	// Returns error if publishing fails, but does not wait for delivery
	Publish(ctx context.Context, msg *PushNotificationMessage) error

	// Close gracefully shuts down the producer
	Close() error
}

// NotificationService defines the interface for sending notifications
type NotificationService interface {
	// SendNotification sends a notification to a user
	SendNotification(userID, event string, data interface{})
}

// PushNotificationService defines the interface for sending push notifications to devices
type PushNotificationService interface {
	// SendNotificationToDevices sends a push notification to specific devices
	SendNotificationToDevices(playerIDs []string, title string, content string, data map[string]interface{}) error
}
