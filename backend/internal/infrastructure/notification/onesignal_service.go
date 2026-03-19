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
	var heading, content string
	var messageID string // ✅ 新增：用來提取 Message ID 給 iOS Extension 使用

	switch event {
	case "chat_message":
		if msg, ok := data.(*domain.Message); ok {
			heading = "New Message"
			content = "You received a new message"
			messageID = msg.ID // ✅ 成功提取 Message ID
		} else {
			heading = "New Message"
			content = "Check your app"
		}
	case "friend_request":
		heading = "Friend Request"
		senderName := "Someone"
		if reqMap, ok := data.(map[string]interface{}); ok {
			firstName, _ := reqMap["first_name"].(string)
			lastName, _ := reqMap["last_name"].(string)
			username, _ := reqMap["sender_username"].(string)

			if firstName != "" || lastName != "" {
				if firstName != "" && lastName != "" {
					senderName = firstName + " " + lastName
				} else if firstName != "" {
					senderName = firstName
				} else {
					senderName = lastName
				}
			} else if username != "" {
				senderName = username
			}
		}
		content = fmt.Sprintf("%s sent you a friend request", senderName)
	case "friend_accepted":
		heading = "Friend Request Accepted"
		content = "Your friend request was accepted"
	default:
		heading = "Notification"
		content = "You have a new notification"
	}

	// ✅ 重新整理要傳給手機的 Data Payload，讓 Swift 好抓
	customData := map[string]interface{}{
		"event":   event,
		"payload": data,
	}
	if messageID != "" {
		customData["message_id"] = messageID // ✅ 確保 message_id 放在第一層
	}

	payload := map[string]interface{}{
		"app_id":                    s.AppID,
		"include_external_user_ids": []string{userID},
		"headings":                  map[string]string{"en": heading},
		"contents":                  map[string]string{"en": content},
		"data":                      customData, // ✅ 放進剛整理好的 customData
		"content_available":         true,       // ✅ 新增：喚醒背景
		"mutable_content":           true,       // ✅ 新增：觸發 NotificationExtension 的關鍵
	}

	body, _ := json.Marshal(payload)
	req, _ := http.NewRequest("POST", "https://onesignal.com/api/v1/notifications", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	req.Header.Set("Authorization", "Key "+s.APIKey)

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
		"content_available":  true,
		"mutable_content":    true, // ✅ 這裡原本就有設定，很好！
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
	req.Header.Set("Authorization", "Key "+s.APIKey)

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