package notification

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"chatwmex_backend/internal/domain"
)

type OneSignalService struct {
	AppID  string
	APIKey string
	Client *http.Client
}

func NewOneSignalService(appID, apiKey string) domain.NotificationService {
	return &OneSignalService{
		AppID:  appID,
		APIKey: apiKey,
		Client: &http.Client{},
	}
}

func (s *OneSignalService) SendNotification(userID, event string, data interface{}) {
	// If UserID is provided, target that user.
	// OneSignal uses "external_user_id" to map to our DB IDs.

	// Payload construction
	// We map "event" to a title or subtitle?
	// Or just send data payload?
	// For chat apps, we usually want: Title: "New Message", Body: "User: Content"

	var heading, content string

	switch event {
	case "chat_message":
		if msg, ok := data.(*domain.Message); ok {
			heading = "New Message"
			// Decrypt? We might not want to decrypt here or send encrypted.
			// Ideally we send "You have a new message" for privacy.
			content = "You received a new message"
			if msg.Type == "text" {
				// If we had the sender name, we'd include it.
				// For now, generic.
			}
		} else {
			heading = "New Message"
			content = "Check your app"
		}
	case "friend_request":
		heading = "Friend Request"
		content = "You have a new friend request"
	case "friend_accepted":
		heading = "Friend Request Accepted"
		content = "Your friend request was accepted"
	default:
		heading = "Notification"
		content = "You have a new notification"
	}

	payload := map[string]interface{}{
		"app_id":                    s.AppID,
		"include_external_user_ids": []string{userID},
		"headings":                  map[string]string{"en": heading},
		"contents":                  map[string]string{"en": content},
		"data":                      map[string]interface{}{"event": event, "payload": data},
		// "ios_badgeType": "Increase",
		// "ios_badgeCount": 1,
	}

	body, _ := json.Marshal(payload)
	req, _ := http.NewRequest("POST", "https://onesignal.com/api/v1/notifications", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	req.Header.Set("Authorization", "Basic "+s.APIKey)

	go func() {
		resp, err := s.Client.Do(req)
		if err != nil {
			log.Printf("Error sending push notification: %v", err)
			return
		}
		defer resp.Body.Close()

		if resp.StatusCode >= 400 {
			log.Printf("OneSignal Error: %s", resp.Status)
		}
	}()
}

func (s *OneSignalService) SendNotificationToDevices(playerIDs []string, title string, content string, data map[string]interface{}) error {
	if len(playerIDs) == 0 {
		return nil
	}

	payload := map[string]interface{}{
		"app_id":             s.AppID,
		"include_player_ids": playerIDs,
		"headings":           map[string]string{"en": title},
		"contents":           map[string]string{"en": content},
		"data":               data,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequest("POST", "https://onesignal.com/api/v1/notifications", bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	req.Header.Set("Authorization", "Basic "+s.APIKey)

	resp, err := s.Client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("onesignal error: %s", resp.Status)
	}
	return nil
}
