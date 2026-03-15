package websocket

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"chatwmex_backend/internal/domain"
	"chatwmex_backend/internal/infrastructure/rabbitmq"
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

	// RabbitMQ Client for cross-server broadcast
	rabbitMQ *rabbitmq.RabbitMQClient

	// RabbitMQ Ingress Channel
	rabbitIngress      <-chan *domain.Message
	rabbitEventIngress <-chan []byte

	// Notification Service for Push Notifications
	notificationService domain.NotificationService
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
func NewHub(mu domain.MessageUsecase, ru domain.RoomUsecase, or domain.OnlineRepository, rabbit *rabbitmq.RabbitMQClient, rabbitIngress <-chan *domain.Message, rabbitEventIngress <-chan []byte, ns domain.NotificationService, pr domain.PendingReEncryptRepository) *Hub {
	return &Hub{
		broadcast:            make(chan *domain.Message),
		register:             make(chan *Client),
		unregister:           make(chan *Client),
		clients:              make(map[*Client]bool),
		userClients:          make(map[string]*Client),
		messageUsecase:       mu,
		roomUsecase:          ru,
		onlineRepo:           or,
		rabbitMQ:             rabbit,
		rabbitIngress:        rabbitIngress,
		rabbitEventIngress:   rabbitEventIngress,
		notificationService:  ns,
		pendingReEncryptRepo: pr,
	}
}

// Run starts the hub loop.
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.clients[client] = true
			h.userClients[client.userID] = client
			// Mark user as online in Redis
			go func(uid string) {
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				defer cancel()
				if err := h.onlineRepo.SetUserOnline(ctx, uid); err != nil {
					log.Printf("Error setting user %s online: %v", uid, err)
				}

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

				// Deliver pending re-encrypt requests
				if h.pendingReEncryptRepo != nil {
					h.deliverPendingReEncryptRequests(ctx, uid, client)
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
						if err := h.onlineRepo.SetUserOffline(ctx, uid); err != nil {
							log.Printf("Error setting user %s offline: %v", uid, err)
						}
					}(client.userID)
				}
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
			}
		}

		// 2. 廣播給其他成員（裁切後的版本）
		for _, memberID := range members {
			// 跳過發送者（已在上面處理）
			if memberID == msg.SenderID {
				continue
			}

			destClient, ok := h.userClients[memberID]
			if !ok {
				continue
			}

			// 為每個接收方建立個人化訊息
			personalMsg := *msg // 複製訊息結構

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
	}
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

func (h *Hub) SendReadReceiptToUser(senderID, readerID string) {
	if client, ok := h.userClients[senderID]; ok {
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
		client.send <- bytes
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
