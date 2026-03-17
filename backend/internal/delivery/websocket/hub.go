package websocket

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"chatwmex_backend/internal/domain"
	"chatwmex_backend/internal/infrastructure/rabbitmq"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

// Hub maintains the set of active clients and broadcasts messages to the
// clients.
type Hub struct {
	// Registered clients.
	clients map[*Client]bool

	// Mapping from UserID to Client (for 1-on-1 routing)
	// Note: This simple map assumes one connection per user.
	// For multiple devices, use map[string][]*Client or similar.
	userClients map[string]*Client

	// Inbound messages from the clients.
	broadcast chan *domain.Message

	// Register requests from the clients.
	register chan *Client

	// Unregister requests from clients.
	unregister chan *Client

	// Message Usecase for persistence
	messageUsecase domain.MessageUsecase
	// Room Usecase for fetching room members
	roomUsecase domain.RoomUsecase
	// Online Repository for tracking online status
	onlineRepo domain.OnlineRepository
	// Pending ReEncrypt Repository for offline re-encrypt request persistence
	pendingReEncryptRepo domain.PendingReEncryptRepository

	// LinkedDevice Repository for looking up user's linked devices
	linkedDeviceRepo domain.LinkedDeviceRepository

	// OfflineLinkedMessage Repository for buffering messages for offline linked devices
	offlineLinkedMsgRepo domain.OfflineLinkedMessageRepository

	// Friend Repository for presence broadcast
	friendRepo domain.FriendRepository

	// PrivacySetting Usecase for read receipt privacy filtering
	privacySettingUsecase domain.PrivacySettingUsecase

	// RabbitMQ Client for cross-server broadcast
	rabbitMQ *rabbitmq.RabbitMQClient

	// RabbitMQ Ingress Channel
	rabbitIngress      <-chan *domain.Message
	rabbitEventIngress <-chan []byte

	// Notification Service for Push Notifications
	notificationService domain.NotificationService

	// NotificationProducer for retrying failed push notifications
	notificationProducer domain.NotificationProducer

	// Redis client for notify_retry queue
	redisClient *redis.Client
}

// GetActiveConnectionCount returns the number of active clients.
func (h *Hub) GetActiveConnectionCount() int {
	return len(h.clients)
}

// IsUserOnline checks if a user is currently connected to this Hub instance.
func (h *Hub) IsUserOnline(userID string) bool {
	_, ok := h.userClients[userID]
	return ok
}

// NewHub creates a new Hub instance.
func NewHub(mu domain.MessageUsecase, ru domain.RoomUsecase, or domain.OnlineRepository, rabbit *rabbitmq.RabbitMQClient, rabbitIngress <-chan *domain.Message, rabbitEventIngress <-chan []byte, ns domain.NotificationService, pr domain.PendingReEncryptRepository, ldr domain.LinkedDeviceRepository, olmr domain.OfflineLinkedMessageRepository, fr domain.FriendRepository, psu domain.PrivacySettingUsecase) *Hub {
	return &Hub{
		broadcast:             make(chan *domain.Message),
		register:              make(chan *Client),
		unregister:            make(chan *Client),
		clients:               make(map[*Client]bool),
		userClients:           make(map[string]*Client),
		messageUsecase:        mu,
		roomUsecase:           ru,
		onlineRepo:            or,
		rabbitMQ:              rabbit,
		rabbitIngress:         rabbitIngress,
		rabbitEventIngress:    rabbitEventIngress,
		notificationService:   ns,
		pendingReEncryptRepo:  pr,
		linkedDeviceRepo:      ldr,
		offlineLinkedMsgRepo:  olmr,
		friendRepo:            fr,
		privacySettingUsecase: psu,
	}
}

// SetNotificationRetryDeps injects the dependencies needed for the push notification
// retry worker. Call this after NewHub, before hub.Run().
func (h *Hub) SetNotificationRetryDeps(producer domain.NotificationProducer, rc *redis.Client) {
	h.notificationProducer = producer
	h.redisClient = rc
}

// Run starts the hub loop.
func (h *Hub) Run() {
	// 🔧 啟動時清空 Redis 的 online_users set，避免伺服器重啟後殘留舊的在線狀態
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if err := h.onlineRepo.ClearAllOnline(ctx); err != nil {
			log.Printf("[Presence] Warning: failed to clear online_users on startup: %v", err)
		} else {
			log.Printf("[Presence] Cleared stale online_users set on startup")
		}
	}()

	for {
		select {
		case client := <-h.register:
			h.clients[client] = true
			h.userClients[client.userID] = client
			// Mark user as online in Redis and broadcast presence
			go func(uid string) {
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				defer cancel()
				if err := h.onlineRepo.SetUserOnline(ctx, uid); err != nil {
					log.Printf("Error setting user %s online: %v", uid, err)
				}
				log.Printf("[Presence] user %s connected, broadcasting online presence", uid)
				h.broadcastPresenceToFriends(uid, true, nil)

				// Fetch and deliver offline messages
				msgs, err := h.messageUsecase.FetchOfflineMessages(ctx, uid)
				if err != nil {
					log.Printf("Error fetching offline messages for %s: %v", uid, err)
					return
				}
				for _, msg := range msgs {
					// Send as chat_message event
					// We construct a WSResponse manually or use a helper
					// Since we are in Hub, we don't have SocketController helper easily accessible
					// We can reuse routeMessage? No, routeMessage broadcasts.
					// We just send to this client.
					resp := map[string]interface{}{
						"event": "chat_message",
						"data":  msg,
					}
					bytes, _ := json.Marshal(resp)
					client.send <- bytes
				}

				// 推送所有待通知的 delivered receipts
				receipts, err := h.messageUsecase.FetchAndClearDeliveredReceiptNotifications(ctx, uid)
				if err == nil {
					for _, receipt := range receipts {
						resp := map[string]interface{}{
							"event": "messages_delivered_receipt",
							"data": map[string]interface{}{
								"room_id":              receipt.ConversationID,
								"message_ids":          receipt.MessageIDs,
								"delivered_by_user_id": receipt.DeliveredByUserID,
							},
						}
						bytes, _ := json.Marshal(resp)
						client.send <- bytes
					}
				}

				// Deliver offline messages for linked devices
				if h.offlineLinkedMsgRepo != nil && h.linkedDeviceRepo != nil {
					device, err := h.linkedDeviceRepo.GetByID(ctx, uid)
					if err != nil {
						log.Printf("Error checking linked device status for %s: %v", uid, err)
					} else if device != nil {
						offlineMsgs, err := h.offlineLinkedMsgRepo.GetByDeviceID(ctx, uid)
						if err != nil {
							log.Printf("Error fetching offline linked messages for device %s: %v", uid, err)
						} else if len(offlineMsgs) > 0 {
							for _, offlineMsg := range offlineMsgs {
								resp := map[string]interface{}{
									"event": "chat_message",
									"data":  offlineMsg.Message,
								}
								bytes, _ := json.Marshal(resp)
								client.send <- bytes
							}
							if err := h.offlineLinkedMsgRepo.DeleteByDeviceID(ctx, uid); err != nil {
								log.Printf("Error deleting offline linked messages for device %s: %v", uid, err)
							}
						}
					}
				}

				// Deliver pending re-encrypt requests
				if h.pendingReEncryptRepo != nil {
					h.deliverPendingReEncryptRequests(ctx, uid, client)
				}

				// Retry any failed push notifications for this user
				if h.notificationProducer != nil && h.redisClient != nil {
					h.retryPendingNotifications(uid)
				}
			}(client.userID)
			log.Printf("Client connected: %s", client.userID)

		case client := <-h.unregister:
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				// Only remove from userClients if it matches (handle potential race/overwrite)
				if h.userClients[client.userID] == client {
					delete(h.userClients, client.userID)

					// Mark user as offline in Redis ONLY if no other connections exist (simplified for now: just remove)
					// In a multi-device scenario, we should check if other clients exist or use ref counting.
					// But since h.userClients only stores one, we assume removing it means offline.
					go func(uid string) {
						ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
						defer cancel()
						now := time.Now()
						if err := h.onlineRepo.SetUserOffline(ctx, uid); err != nil {
							log.Printf("Error setting user %s offline: %v", uid, err)
						}
						if err := h.onlineRepo.SetUserLastSeen(ctx, uid, now); err != nil {
							log.Printf("Error setting last seen for user %s: %v", uid, err)
						}
						log.Printf("[Presence] user %s disconnected, broadcasting offline presence", uid)
						h.broadcastPresenceToFriends(uid, false, &now)
					}(client.userID)				}
				close(client.send)
				log.Printf("Client disconnected: %s", client.userID)
			}

		case msg := <-h.broadcast:
			// Route the message
			h.routeMessage(msg)

		case msg := <-h.rabbitIngress:
			if h.rabbitIngress != nil {
				// Message from RabbitMQ. Treat it as local broadcast.
				// It has already been saved to DB by the original sender server.
				// We just need to route it to local connected clients.
				h.routeMessage(msg)
			}
		case eventBytes := <-h.rabbitEventIngress:
			if h.rabbitEventIngress != nil {
				h.handleChatEvent(eventBytes)
			}
		}
	}
}

// routeMessage handles the delivery of a message to connected clients.
func (h *Hub) routeMessage(msg *domain.Message) {
	// 2. Room Logic (Group Chat)
	if msg.RoomID != "" {
		// Fetch members of the room
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		members, err := h.roomUsecase.GetRoomMembers(ctx, msg.RoomID)
		cancel()

		if err != nil {
			log.Printf("Error fetching room members for broadcast: %v", err)
			return
		}

		// 🔐 E2EE Group Messages: 為每個成員裁切 payload
		// 如果訊息包含 EncryptedContentsFanout，為每個接收方只發送其專屬密文
		hasFanout := msg.EncryptedContentsFanout != nil && len(msg.EncryptedContentsFanout) > 0

		// 1. 先發送給發送方（完整副本，包含 EncryptedContentsFanout）
		if sourceClient, ok := h.userClients[msg.SenderID]; ok {
			fullPayload := map[string]interface{}{
				"event": "chat_message",
				"data":  msg,
			}
			fullMessageBytes, err := json.Marshal(fullPayload)
			if err == nil {
				select {
				case sourceClient.send <- fullMessageBytes:
				default:
					close(sourceClient.send)
					delete(h.clients, sourceClient)
					delete(h.userClients, sourceClient.userID)
				}

				// 📱 Linked Devices: 扇出給發送者的所有已連結裝置（排除發送者本身）
				h.fanoutToLinkedDevices(msg.SenderID, fullMessageBytes, map[string]bool{msg.SenderID: true}, msg)
			}
		}

		// 2. 廣播給其他成員（裁切後的版本）
		for _, memberID := range members {
			// 跳過發送者（已在上面處理）
			if memberID == msg.SenderID {
				continue
			}

			// 🔐 Bug #2 防呆：跳過 roomID（不應出現在成員列表中，但作為安全防護）
			if memberID == msg.RoomID {
				log.Printf("[WARN] memberID == roomID, skipping: %s", memberID)
				continue
			}

			destClient, ok := h.userClients[memberID]
			if !ok {
				continue
			}

			// 為每個接收方建立個人化訊息
			personalMsg := *msg // 複製訊息結構

			// 🔍 DEBUG: 檢查複製後的 SenderID
			log.Printf("[DEBUG] routeMessage: original msg.SenderID=%s, personalMsg.SenderID=%s, memberID=%s, roomID=%s",
				msg.SenderID, personalMsg.SenderID, memberID, msg.RoomID)

			if hasFanout {
				// 從 fanout map 中取出該成員的專屬密文
				if ciphertext, exists := msg.EncryptedContentsFanout[memberID]; exists {
					personalMsg.Content = ciphertext
				} else {
					// 如果該成員沒有對應的密文，跳過（可能是加密時該成員不在線）
					log.Printf("⚠️ [E2EE] Member %s has no ciphertext in fanout for message %s", memberID, msg.ID)
					continue
				}
				// 移除 EncryptedContentsFanout，不把整個 fanout map 傳給每個人
				personalMsg.EncryptedContentsFanout = nil
			}

			// 序列化個人化訊息
			personalPayload := map[string]interface{}{
				"event": "chat_message",
				"data":  personalMsg,
			}

			// 🔍 DEBUG: 檢查序列化前的 personalMsg
			log.Printf("[DEBUG] Before marshal: personalMsg.SenderID=%s, personalMsg.RoomID=%s, personalMsg.Type=%s",
				personalMsg.SenderID, personalMsg.RoomID, personalMsg.Type)

			personalMessageBytes, err := json.Marshal(personalPayload)
			if err != nil {
				log.Printf("Error encoding personal message for member %s: %v", memberID, err)
				continue
			}

			// 發送給該成員
			select {
			case destClient.send <- personalMessageBytes:
			default:
				close(destClient.send)
				delete(h.clients, destClient)
				delete(h.userClients, destClient.userID)
			}

			// 📱 Linked Devices: 扇出給該成員的所有已連結裝置
			h.fanoutToLinkedDevices(memberID, personalMessageBytes, map[string]bool{memberID: true}, &personalMsg)
		}

		return
	}

	// 1-on-1 DM Logic (保持原有邏輯)
	payload := map[string]interface{}{
		"event": "chat_message",
		"data":  msg,
	}
	messageBytes, err := json.Marshal(payload)
	if err != nil {
		log.Printf("Error encoding message for broadcast: %v", err)
		return
	}

	// 1. Send back to Sender (Confirmation)
	if sourceClient, ok := h.userClients[msg.SenderID]; ok {
		select {
		case sourceClient.send <- messageBytes:
		default:
			close(sourceClient.send)
			delete(h.clients, sourceClient)
			delete(h.userClients, sourceClient.userID)
		}
	}

	// 📱 Linked Devices: 扇出給發送者的所有已連結裝置（排除發送者本身）
	h.fanoutToLinkedDevices(msg.SenderID, messageBytes, map[string]bool{msg.SenderID: true}, msg)

	// 2. Send to Receiver
	if msg.ReceiverID != "" {
		if destClient, ok := h.userClients[msg.ReceiverID]; ok {
			select {
			case destClient.send <- messageBytes:
			default:
				close(destClient.send)
				delete(h.clients, destClient)
				delete(h.userClients, destClient.userID)
			}
			if sourceClient, ok := h.userClients[msg.SenderID]; ok {
				resp := map[string]interface{}{
					"event": "message_delivered",
					"data": map[string]interface{}{
						"message_id":    msg.ID,
						"client_msg_id": msg.ClientMsgID,
					},
				}
				bytes, _ := json.Marshal(resp)
				sourceClient.send <- bytes
			}
		}

		// 📱 Linked Devices: 扇出給接收者的所有已連結裝置
		h.fanoutToLinkedDevices(msg.ReceiverID, messageBytes, map[string]bool{msg.ReceiverID: true}, msg)
	}
}
// fanoutToLinkedDevices sends a message payload to all linked devices of a user,
// excluding the specified originID (to avoid sending back to the originating device).
// originID can be either a userID (primary device) or a deviceID (linked device).
func (h *Hub) fanoutToLinkedDevices(userID string, messageBytes []byte, excludeIDs map[string]bool, msg *domain.Message) {
	if h.linkedDeviceRepo == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	devices, err := h.linkedDeviceRepo.GetByUserID(ctx, userID)
	cancel()

	if err != nil {
		log.Printf("Error fetching linked devices for message fanout (user %s): %v", userID, err)
		return
	}

	for _, device := range devices {
		if excludeIDs[device.ID] {
			continue
		}
		if client, ok := h.userClients[device.ID]; ok {
			select {
			case client.send <- messageBytes:
				// Update LastActiveAt when linked device receives a message
				h.updateLinkedDeviceActivity(device.ID)
			default:
				close(client.send)
				delete(h.clients, client)
				delete(h.userClients, client.userID)
			}
		} else if h.offlineLinkedMsgRepo != nil && msg != nil {
			// Device is offline — buffer the message for later delivery
			now := time.Now()
			offlineMsg := &domain.OfflineLinkedMessage{
				ID:        uuid.New().String(),
				DeviceID:  device.ID,
				Message:   msg,
				CreatedAt: now,
				ExpiresAt: now.Add(7 * 24 * time.Hour),
			}
			storeCtx, storeCancel := context.WithTimeout(context.Background(), 2*time.Second)
			if err := h.offlineLinkedMsgRepo.Store(storeCtx, offlineMsg); err != nil {
				log.Printf("Error storing offline message for linked device %s: %v", device.ID, err)
			}
			storeCancel()
		}
	}
}

// updateLinkedDeviceActivity asynchronously updates the LastActiveAt timestamp
// for a linked device. This is called when a linked device sends or receives
// a message via WebSocket, fulfilling Requirement 4.2.
func (h *Hub) updateLinkedDeviceActivity(deviceID string) {
	if h.linkedDeviceRepo == nil {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if err := h.linkedDeviceRepo.UpdateLastActive(ctx, deviceID); err != nil {
			log.Printf("Error updating last active for linked device %s: %v", deviceID, err)
		}
	}()
}


// SendNotification sends a system notification to a user.
func (h *Hub) SendNotification(userID, event string, data interface{}) {
	if client, ok := h.userClients[userID]; ok {
		resp := map[string]interface{}{
			"event": event,
			"data":  data,
		}
		bytes, _ := json.Marshal(resp)
		client.send <- bytes
	}

	// Also send Push Notification if it's a critical event (like Friend Request)
	// Or maybe only if client is NOT found?
	// The requirement "User B must immediately... receive" implies WS if online.
	// But Push is good backup.
	// For "Friend Request", we usually want Push regardless of Online status (so they see banner).
	if h.notificationService != nil {
		h.notificationService.SendNotification(userID, event, data)
	}
}

// SendSessionKey sends an encrypted session key to a specific linked device via WebSocket.
// The deviceID is used as the lookup key in userClients since linked devices register
// with their device ID as the connection identifier.
func (h *Hub) SendSessionKey(deviceID, encryptedKey, senderPublicKey string) {
	if client, ok := h.userClients[deviceID]; ok {
		resp := map[string]interface{}{
			"event": "session_key_delivery",
			"data": map[string]interface{}{
				"device_id":         deviceID,
				"encrypted_key":     encryptedKey,
				"sender_public_key": senderPublicKey,
			},
		}
		bytes, _ := json.Marshal(resp)
		client.send <- bytes
	}
}

// SendDeviceUnlinked notifies a linked device that it has been unlinked.
// The device should clear its local session data and navigate to the login page.
func (h *Hub) SendDeviceUnlinked(deviceID string) {
	if client, ok := h.userClients[deviceID]; ok {
		resp := map[string]interface{}{
			"event": "device_unlinked",
			"data": map[string]interface{}{
				"device_id": deviceID,
			},
		}
		bytes, _ := json.Marshal(resp)
		client.send <- bytes
	}
}

// BroadcastReadStatusSync broadcasts read status to all of a user's linked devices.
// This ensures read status is synced across the primary device and all linked devices.
func (h *Hub) BroadcastReadStatusSync(userID, roomID string, lastReadAt time.Time) {
	data := map[string]interface{}{
		"room_id":      roomID,
		"user_id":      userID,
		"last_read_at": lastReadAt.Format(time.RFC3339),
	}
	resp := map[string]interface{}{
		"event": "read_status_sync",
		"data":  data,
	}
	bytes, err := json.Marshal(resp)
	if err != nil {
		log.Printf("Error encoding read_status_sync event: %v", err)
		return
	}

	// Send to the user's primary device
	if client, ok := h.userClients[userID]; ok {
		select {
		case client.send <- bytes:
		default:
			close(client.send)
			delete(h.clients, client)
			delete(h.userClients, client.userID)
		}
	}

	// Send to all linked devices
	if h.linkedDeviceRepo != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		devices, err := h.linkedDeviceRepo.GetByUserID(ctx, userID)
		cancel()
		if err != nil {
			log.Printf("Error fetching linked devices for read_status_sync: %v", err)
			return
		}
		for _, device := range devices {
			if client, ok := h.userClients[device.ID]; ok {
				select {
				case client.send <- bytes:
				default:
					close(client.send)
					delete(h.clients, client)
					delete(h.userClients, client.userID)
				}
			}
		}
	}
}

func (h *Hub) SendReadReceiptToUser(senderID, readerID string) {
	// Check privacy setting: skip broadcast if reader has disabled read receipts
	// or if sender has disabled read receipts (mutual suppression for DMs)
	if h.privacySettingUsecase != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		show, err := h.privacySettingUsecase.ShouldShowReadReceipt(ctx, readerID, senderID, false)
		cancel()
		if err != nil {
			log.Printf("[ReadReceipt] ShouldShowReadReceipt error (fail-open): %v", err)
		} else if !show {
			log.Printf("[ReadReceipt] Skipping DM read receipt: readerID=%s senderID=%s (privacy setting)", readerID, senderID)
			return
		}
	}

	resp := map[string]interface{}{
		"event": "read_receipt",
		"data": map[string]interface{}{
			"conversation_id": senderID,
			"reader_id":       readerID,
			"is_room":         false,
			"read_at":         time.Now().Format(time.RFC3339),
		},
	}
	bytes, _ := json.Marshal(resp)

	if client, ok := h.userClients[senderID]; ok {
		client.send <- bytes
	}

	// Fan out read receipt to linked devices of the sender
	h.fanoutReadReceiptToLinkedDevices(senderID, bytes)
}

// fanoutReadReceiptToLinkedDevices sends a read receipt payload to all linked devices of a user.
func (h *Hub) fanoutReadReceiptToLinkedDevices(userID string, messageBytes []byte) {
	if h.linkedDeviceRepo == nil {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	devices, err := h.linkedDeviceRepo.GetByUserID(ctx, userID)
	cancel()

	if err != nil {
		log.Printf("Error fetching linked devices for read receipt fanout (user %s): %v", userID, err)
		return
	}

	for _, device := range devices {
		if client, ok := h.userClients[device.ID]; ok {
			select {
			case client.send <- messageBytes:
				// Update LastActiveAt when linked device receives a read receipt
				h.updateLinkedDeviceActivity(device.ID)
			default:
				close(client.send)
				delete(h.clients, client)
				delete(h.userClients, client.userID)
			}
		}
	}
}

type chatEvent struct {
	Type         string              `json:"type"`
	RoomID       string              `json:"room_id"`
	MessageIDs   []string            `json:"message_ids"`
	ReadByUserID string              `json:"read_by_user_id"`
	MessageID    string              `json:"message_id"`
	Reactions    map[string][]string `json:"reactions"`
	SenderID     string              `json:"sender_id"`
	ReceiverID   string              `json:"receiver_id"`
	UserID       string              `json:"user_id"`
	AvatarURL    string              `json:"avatar_url"`
	Name         string              `json:"name"`
	FirstName    string              `json:"first_name,omitempty"`
	LastName     string              `json:"last_name,omitempty"`
	Bio          string              `json:"bio,omitempty"`
}

func (h *Hub) BroadcastRoomReadReceipt(roomID string, messageIDs []string, readerID string) {
	event := chatEvent{
		Type:         "messages_read_receipt",
		RoomID:       roomID,
		MessageIDs:   messageIDs,
		ReadByUserID: readerID,
	}
	if h.rabbitMQ != nil {
		if err := h.rabbitMQ.PublishEvent(event); err == nil {
			return
		}
	}
	h.broadcastRoomReadReceiptLocal(event)
}

func (h *Hub) handleChatEvent(eventBytes []byte) {
	var event chatEvent
	if err := json.Unmarshal(eventBytes, &event); err != nil {
		return
	}
	if event.Type == "messages_read_receipt" {
		h.broadcastRoomReadReceiptLocal(event)
		return
	}
	if event.Type == "messages_delivered_receipt" {
		h.broadcastRoomDeliveredReceiptLocal(event)
		return
	}
	if event.Type == "message_reaction" {
		h.broadcastMessageReactionLocal(event)
		return
	}
	if event.Type == "message_unsent" {
		h.broadcastMessageUnsentLocal(event)
		return
	}
	if event.Type == "user_profile_updated" {
		h.broadcastUserProfileUpdatedLocal(event)
		return
	}
	if event.Type == "user_info_updated" {
		h.broadcastUserInfoUpdatedLocal(event)
		return
	}
	if event.Type == "room_updated" {
		h.broadcastRoomUpdatedLocal(event)
	}
}

func (h *Hub) BroadcastRoomDeliveredReceipt(roomID string, messageIDs []string, readerID string) {
	event := chatEvent{
		Type:         "messages_delivered_receipt",
		RoomID:       roomID,
		MessageIDs:   messageIDs,
		ReadByUserID: readerID,
	}
	if h.rabbitMQ != nil {
		if err := h.rabbitMQ.PublishEvent(event); err == nil {
			return
		}
	}
	h.broadcastRoomDeliveredReceiptLocal(event)
}

func (h *Hub) broadcastRoomDeliveredReceiptLocal(event chatEvent) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	members, err := h.roomUsecase.GetRoomMembers(ctx, event.RoomID)
	cancel()

	// 如果 err != nil 或者 members 為空，表示這是一個私訊。
	// 在 message_handler.go 配合 GetRoomMessageMap，傳進來的 event.RoomID 實際上是【發送者(B)】的 UserID。
	// 而 event.ReadByUserID 是【接收者(A)】的 UserID。
	isPrivateMsg := err != nil || len(members) == 0

	// 決定傳給前端的 room_id。
	// 如果是群組，就是原來的 RoomID。
	// 如果是私訊，對於發送者(B)來說，這個對話的 ID 就是接收者(A)的 ID。
	frontendRoomID := event.RoomID
	if isPrivateMsg {
		frontendRoomID = event.ReadByUserID
	}

	payload := map[string]interface{}{
		"event": "messages_delivered_receipt",
		"data": map[string]interface{}{
			"room_id":              frontendRoomID, // 修正：給前端對方(A)的 ID，而不是自己的 ID
			"message_ids":          event.MessageIDs,
			"delivered_by_user_id": event.ReadByUserID,
		},
	}
	messageBytes, errMarshal := json.Marshal(payload)
	if errMarshal != nil {
		return
	}

	if isPrivateMsg {
		// 發送給發送者(B)
		if destClient, ok := h.userClients[event.RoomID]; ok {
			select {
			case destClient.send <- messageBytes:
			default:
				close(destClient.send)
				delete(h.clients, destClient)
				delete(h.userClients, destClient.userID)
			}
		} else {
			// sender 不在線，把這個 receipt 存入離線佇列
			go func() {
				notification := &domain.DeliveredReceiptNotification{
					SenderID:          event.RoomID,
					MessageIDs:        event.MessageIDs,
					DeliveredByUserID: event.ReadByUserID,
					ConversationID:    event.ReadByUserID,
					CreatedAt:         time.Now(),
				}
				ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
				defer cancel()
				if err := h.messageUsecase.StoreDeliveredReceiptNotification(ctx, notification); err != nil {
					log.Printf("failed to store delivered receipt notification: %v", err)
				}
			}()
		}
		return
	}

	for _, memberID := range members {
		if memberID == event.ReadByUserID {
			continue
		}
		if destClient, ok := h.userClients[memberID]; ok {
			select {
			case destClient.send <- messageBytes:
			default:
				close(destClient.send)
				delete(h.clients, destClient)
				delete(h.userClients, destClient.userID)
			}
		}
	}
}

func (h *Hub) broadcastRoomReadReceiptLocal(event chatEvent) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	members, err := h.roomUsecase.GetRoomMembers(ctx, event.RoomID)
	cancel()

	isPrivateMsg := err != nil || len(members) == 0

	frontendRoomID := event.RoomID
	if isPrivateMsg {
		frontendRoomID = event.ReadByUserID
	}

	payload := map[string]interface{}{
		"event": "messages_read_receipt",
		"data": map[string]interface{}{
			"room_id":         frontendRoomID, // 修正：給前端對方(A)的 ID
			"message_ids":     event.MessageIDs,
			"read_by_user_id": event.ReadByUserID,
		},
	}
	messageBytes, errMarshal := json.Marshal(payload)
	if errMarshal != nil {
		return
	}

	// Sync read status to all linked devices of the reader
	h.BroadcastReadStatusSync(event.ReadByUserID, event.RoomID, time.Now())

	if isPrivateMsg {
		// 發送給發送者(B)
		if destClient, ok := h.userClients[event.RoomID]; ok {
			select {
			case destClient.send <- messageBytes:
			default:
				close(destClient.send)
				delete(h.clients, destClient)
				delete(h.userClients, destClient.userID)
			}
		}

		// Fan out read receipt to linked devices of the sender(B)
		h.fanoutReadReceiptToLinkedDevices(event.RoomID, messageBytes)
		return
	}

	for _, memberID := range members {
		if memberID == event.ReadByUserID {
			continue
		}
		if destClient, ok := h.userClients[memberID]; ok {
			select {
			case destClient.send <- messageBytes:
			default:
				close(destClient.send)
				delete(h.clients, destClient)
				delete(h.userClients, destClient.userID)
			}
		}

		// Fan out read receipt to linked devices of each member
		h.fanoutReadReceiptToLinkedDevices(memberID, messageBytes)
	}
}

func (h *Hub) BroadcastMessageReaction(msg *domain.Message) {
	if msg == nil {
		return
	}
	event := chatEvent{
		Type:      "message_reaction",
		RoomID:    msg.RoomID,
		MessageID: msg.ID,
		Reactions: msg.Reactions,
	}
	if h.rabbitMQ != nil {
		if err := h.rabbitMQ.PublishEvent(event); err == nil {
			return
		}
	}
	h.broadcastMessageReactionLocal(event)
}

func (h *Hub) broadcastMessageReactionLocal(event chatEvent) {
	if event.RoomID == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	members, err := h.roomUsecase.GetRoomMembers(ctx, event.RoomID)
	cancel()
	if err != nil {
		return
	}

	payload := map[string]interface{}{
		"event": "message_reaction",
		"data": map[string]interface{}{
			"room_id":    event.RoomID,
			"message_id": event.MessageID,
			"reactions":  event.Reactions,
		},
	}
	messageBytes, err := json.Marshal(payload)
	if err != nil {
		return
	}

	for _, memberID := range members {
		if destClient, ok := h.userClients[memberID]; ok {
			select {
			case destClient.send <- messageBytes:
			default:
				close(destClient.send)
				delete(h.clients, destClient)
				delete(h.userClients, destClient.userID)
			}
		}
	}
}

func (h *Hub) BroadcastMessageUnsent(msg *domain.Message) {
	if msg == nil {
		return
	}
	event := chatEvent{
		Type:       "message_unsent",
		RoomID:     msg.RoomID,
		MessageID:  msg.ID,
		SenderID:   msg.SenderID,
		ReceiverID: msg.ReceiverID,
	}
	if h.rabbitMQ != nil {
		if err := h.rabbitMQ.PublishEvent(event); err == nil {
			return
		}
	}
	h.broadcastMessageUnsentLocal(event)
}

func (h *Hub) broadcastMessageUnsentLocal(event chatEvent) {
	payload := map[string]interface{}{
		"event": "message_unsent",
		"data": map[string]interface{}{
			"room_id":    event.RoomID,
			"message_id": event.MessageID,
		},
	}
	messageBytes, err := json.Marshal(payload)
	if err != nil {
		return
	}

	if event.RoomID != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		members, err := h.roomUsecase.GetRoomMembers(ctx, event.RoomID)
		cancel()
		if err != nil {
			return
		}
		for _, memberID := range members {
			if destClient, ok := h.userClients[memberID]; ok {
				select {
				case destClient.send <- messageBytes:
				default:
					close(destClient.send)
					delete(h.clients, destClient)
					delete(h.userClients, destClient.userID)
				}
			}
		}
		return
	}

	if event.SenderID != "" {
		if client, ok := h.userClients[event.SenderID]; ok {
			client.send <- messageBytes
		}
	}
	if event.ReceiverID != "" {
		if client, ok := h.userClients[event.ReceiverID]; ok {
			client.send <- messageBytes
		}
	}
}

func (h *Hub) SendTypingToUser(senderID, receiverID, event string) {
	if client, ok := h.userClients[receiverID]; ok {
		resp := map[string]interface{}{
			"event": event,
			"data": map[string]interface{}{
				"room_id": senderID,
				"user_id": senderID,
			},
		}
		bytes, _ := json.Marshal(resp)
		client.send <- bytes
	}
}

func (h *Hub) BroadcastUserProfileUpdated(userID, avatarURL string) {
	if userID == "" {
		return
	}
	event := chatEvent{
		Type:      "user_profile_updated",
		UserID:    userID,
		AvatarURL: avatarURL,
	}
	if h.rabbitMQ != nil {
		if err := h.rabbitMQ.PublishEvent(event); err == nil {
			return
		}
	}
	h.broadcastUserProfileUpdatedLocal(event)
}

func (h *Hub) broadcastUserProfileUpdatedLocal(event chatEvent) {
	payload := map[string]interface{}{
		"event": "user_profile_updated",
		"data": map[string]interface{}{
			"user_id":    event.UserID,
			"avatar_url": event.AvatarURL,
		},
	}
	messageBytes, err := json.Marshal(payload)
	if err != nil {
		return
	}
	for client := range h.clients {
		select {
		case client.send <- messageBytes:
		default:
			close(client.send)
			delete(h.clients, client)
			delete(h.userClients, client.userID)
		}
	}
}

func (h *Hub) BroadcastUserInfoUpdated(userID, firstName, lastName, bio string) {
	if userID == "" {
		return
	}
	event := chatEvent{
		Type:      "user_info_updated",
		UserID:    userID,
		FirstName: firstName,
		LastName:  lastName,
		Bio:       bio,
	}
	if h.rabbitMQ != nil {
		if err := h.rabbitMQ.PublishEvent(event); err == nil {
			return
		}
	}
	h.broadcastUserInfoUpdatedLocal(event)
}

func (h *Hub) broadcastUserInfoUpdatedLocal(event chatEvent) {
	payload := map[string]interface{}{
		"event": "user_info_updated",
		"data": map[string]interface{}{
			"user_id":    event.UserID,
			"first_name": event.FirstName,
			"last_name":  event.LastName,
			"bio":        event.Bio,
		},
	}
	messageBytes, err := json.Marshal(payload)
	if err != nil {
		return
	}
	for client := range h.clients {
		select {
		case client.send <- messageBytes:
		default:
			close(client.send)
			delete(h.clients, client)
			delete(h.userClients, client.userID)
		}
	}
}

func (h *Hub) BroadcastRoomEvent(roomID, eventType string, data interface{}) {
	if roomID == "" {
		return
	}

	payloadMap, ok := data.(map[string]interface{})
	if !ok {
		return
	}

	name, _ := payloadMap["name"].(string)
	avatarUrl, _ := payloadMap["avatar_url"].(string)

	event := chatEvent{
		Type:      eventType,
		RoomID:    roomID,
		Name:      name,
		AvatarURL: avatarUrl,
	}

	if h.rabbitMQ != nil {
		if err := h.rabbitMQ.PublishEvent(event); err == nil {
			return
		}
	}
	h.broadcastRoomUpdatedLocal(event)
}

func (h *Hub) broadcastRoomUpdatedLocal(event chatEvent) {
	if event.RoomID == "" {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	members, err := h.roomUsecase.GetRoomMembers(ctx, event.RoomID)
	cancel()
	if err != nil {
		return
	}

	payload := map[string]interface{}{
		"event": event.Type,
		"data": map[string]interface{}{
			"room_id":    event.RoomID,
			"name":       event.Name,
			"avatar_url": event.AvatarURL,
		},
	}

	messageBytes, err := json.Marshal(payload)
	if err != nil {
		return
	}

	for _, memberID := range members {
		if destClient, ok := h.userClients[memberID]; ok {
			select {
			case destClient.send <- messageBytes:
			default:
				close(destClient.send)
				delete(h.clients, destClient)
				delete(h.userClients, destClient.userID)
			}
		}
	}
}

func (h *Hub) SendTypingToRoom(senderID, roomID, event string) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	members, err := h.roomUsecase.GetRoomMembers(ctx, roomID)
	cancel()
	if err != nil {
		log.Printf("Error fetching room members for typing: %v", err)
		return
	}
	for _, memberID := range members {
		if memberID == senderID {
			continue
		}
		if client, ok := h.userClients[memberID]; ok {
			resp := map[string]interface{}{
				"event": event,
				"data": map[string]interface{}{
					"room_id": roomID,
					"user_id": senderID,
				},
			}
			bytes, _ := json.Marshal(resp)
			client.send <- bytes
		}
	}
}

// deliverPendingReEncryptRequests fetches and delivers all pending re-encrypt requests
// for a reconnected user. This ensures that requests sent while the user was offline
// are delivered when they come back online.
func (h *Hub) deliverPendingReEncryptRequests(ctx context.Context, userID string, client *Client) {
	// Query all pending re-encrypt requests for this sender (sorted by createdAt)
	pendingRequests, err := h.pendingReEncryptRepo.GetBySenderID(ctx, userID)
	if err != nil {
		log.Printf("Error fetching pending re-encrypt requests for user %s: %v", userID, err)
		return
	}

	if len(pendingRequests) == 0 {
		log.Printf("No pending re-encrypt requests for user %s", userID)
		return
	}

	log.Printf("Delivering %d pending re-encrypt request(s) to user %s", len(pendingRequests), userID)

	// Deliver each request via WebSocket
	for _, req := range pendingRequests {
		// Construct the re_encrypt_request event
		resp := map[string]interface{}{
			"event": "re_encrypt_request",
			"data": map[string]interface{}{
				"message_id":  req.MessageID,
				"receiver_id": req.ReceiverID,
				"room_id":     req.RoomID,
			},
		}

		bytes, err := json.Marshal(resp)
		if err != nil {
			log.Printf("Error marshaling re-encrypt request for message %s: %v", req.MessageID, err)
			continue
		}

		// Attempt to send to the client with retry mechanism
		select {
		case client.send <- bytes:
			// Successfully sent, delete from database
			deleteCtx, deleteCancel := context.WithTimeout(context.Background(), 2*time.Second)
			if err := h.pendingReEncryptRepo.Delete(deleteCtx, req.ID); err != nil {
				log.Printf("Error deleting pending re-encrypt request %s: %v", req.ID, err)
			} else {
				log.Printf("Successfully delivered and deleted pending re-encrypt request %s for message %s", req.ID, req.MessageID)
			}
			deleteCancel()
		default:
			// Client send channel is full or closed, user might have disconnected
			log.Printf("Failed to deliver pending re-encrypt request %s to user %s (send channel blocked)", req.ID, userID)
			// Don't delete from database - will retry on next connection
			break
		}
	}
}

// broadcastPresenceToFriends notifies all online friends of a user's presence change.
func (h *Hub) broadcastPresenceToFriends(userID string, isOnline bool, lastSeen *time.Time) {
	if h.friendRepo == nil {
		log.Printf("[Presence] broadcastPresenceToFriends: friendRepo is nil, skipping for user %s", userID)
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	friends, err := h.friendRepo.GetFriends(ctx, userID)
	if err != nil {
		log.Printf("[Presence] Error fetching friends for presence broadcast (user %s): %v", userID, err)
		return
	}

	log.Printf("[Presence] user=%s isOnline=%v friends_count=%d", userID, isOnline, len(friends))

	data := map[string]interface{}{
		"user_id":   userID,
		"is_online": isOnline,
	}
	if lastSeen != nil {
		data["last_seen"] = lastSeen.UTC().Format(time.RFC3339)
	}

	payload := map[string]interface{}{
		"event": "presence_update",
		"data":  data,
	}
	bytes, err := json.Marshal(payload)
	if err != nil {
		return
	}

	delivered := 0
	for _, friend := range friends {
		if client, ok := h.userClients[friend.ID]; ok {
			select {
			case client.send <- bytes:
				delivered++
			default:
				// Non-blocking: skip if channel full
			}
		}
	}
	log.Printf("[Presence] presence_update sent to %d/%d online friends of user %s", delivered, len(friends), userID)
}

// retryPendingNotifications scans Redis for failed push notifications targeting
// the given userID and retries publishing them to RabbitMQ.
// Keys are stored as "notify_retry:{userID}:{msgID}" with a 24h TTL.
func (h *Hub) retryPendingNotifications(userID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pattern := fmt.Sprintf("notify_retry:%s:*", userID)
	keys, err := h.redisClient.Keys(ctx, pattern).Result()
	if err != nil || len(keys) == 0 {
		return
	}

	log.Printf("[NotifyRetry] Found %d pending notification(s) for user %s", len(keys), userID)

	for _, key := range keys {
		val, err := h.redisClient.Get(ctx, key).Bytes()
		if err != nil {
			continue
		}

		var msg domain.PushNotificationMessage
		if err := json.Unmarshal(val, &msg); err != nil {
			log.Printf("[NotifyRetry] Failed to unmarshal retry payload for key %s: %v", key, err)
			h.redisClient.Del(ctx, key) // remove corrupt entry
			continue
		}

		if err := h.notificationProducer.Publish(ctx, &msg); err != nil {
			log.Printf("[NotifyRetry] Retry publish failed for key %s: %v", key, err)
			continue
		}

		h.redisClient.Del(ctx, key)
		log.Printf("[NotifyRetry] Successfully retried notification for key %s", key)
	}
}
