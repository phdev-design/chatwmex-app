package domain

type NotificationService interface {
	SendNotification(userID, event string, data interface{})
}

type PushNotificationService interface {
	SendNotificationToDevices(playerIDs []string, title string, content string, data map[string]interface{}) error
}
