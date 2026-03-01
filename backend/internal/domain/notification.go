package domain

type NotificationService interface {
	SendNotification(userID, event string, data interface{})
}
