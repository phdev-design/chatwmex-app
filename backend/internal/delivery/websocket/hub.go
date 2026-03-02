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

	// RabbitMQ Client for cross-server broadcast
	rabbitMQ *rabbitmq.RabbitMQClient
	
	// RabbitMQ Ingress Channel
	rabbitIngress <-chan *domain.Message
	rabbitEventIngress <-chan []byte
	
	// Notification Service for Push Notifications
	notificationService domain.NotificationService
}

// GetActiveConnectionCount returns the number of active clients.
func (h *Hub) GetActiveConnectionCount() int {
	return len(h.clients)
}

// NewHub creates a new Hub instance.
func NewHub(mu domain.MessageUsecase, ru domain.RoomUsecase, or domain.OnlineRepository, rabbit *rabbitmq.RabbitMQClient, rabbitIngress <-chan *domain.Message, rabbitEventIngress <-chan []byte, ns domain.NotificationService) *Hub {
	return &Hub{
		broadcast:           make(chan *domain.Message),
		register:            make(chan *Client),
		unregister:          make(chan *Client),
		clients:             make(map[*Client]bool),
		userClients:         make(map[string]*Client),
		messageUsecase:      mu,
		roomUsecase:         ru,
		onlineRepo:          or,
		rabbitMQ:            rabbit,
		rabbitIngress:       rabbitIngress,
		rabbitEventIngress:  rabbitEventIngress,
		notificationService: ns,
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
	// Even if it came from RabbitMQ (another server), if the sender is somehow connected here 
	// (e.g. multi-device), they get it.
	if sourceClient, ok := h.userClients[msg.SenderID]; ok {
		select {
		case sourceClient.send <- messageBytes:
		default:
			close(sourceClient.send)
			delete(h.clients, sourceClient)
			delete(h.userClients, sourceClient.userID)
		}
	}

	// 2. Room Logic (Group Chat)
	if msg.RoomID != "" {
		// Fetch members of the room
		// Use a short timeout
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		members, err := h.roomUsecase.GetRoomMembers(ctx, msg.RoomID)
		cancel()
		
		if err != nil {
			log.Printf("Error fetching room members for broadcast: %v", err)
			return
		}

		// Broadcast to all online members
		for _, memberID := range members {
			// Skip sender if desired
			if memberID == msg.SenderID {
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
	} else if msg.ReceiverID != "" {
		// 1-on-1
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
		} else {
			// User offline locally.
			// Check global status if needed, or just store.
			isOnline, _ := h.onlineRepo.IsUserOnline(context.Background(), msg.ReceiverID)
			if !isOnline {
				go h.messageUsecase.SaveOfflineMessage(context.Background(), msg.ReceiverID, msg)
				
				// Send Push Notification
				if h.notificationService != nil {
					h.notificationService.SendNotification(msg.ReceiverID, "chat_message", msg)
				}
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
	Type          string   `json:"type"`
	RoomID        string   `json:"room_id"`
	MessageIDs    []string `json:"message_ids"`
	ReadByUserID  string   `json:"read_by_user_id"`
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
	}
}

func (h *Hub) broadcastRoomReadReceiptLocal(event chatEvent) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	members, err := h.roomUsecase.GetRoomMembers(ctx, event.RoomID)
	cancel()
	if err != nil {
		return
	}

	payload := map[string]interface{}{
		"event": "messages_read_receipt",
		"data": map[string]interface{}{
			"room_id":         event.RoomID,
			"message_ids":     event.MessageIDs,
			"read_by_user_id": event.ReadByUserID,
		},
	}
	messageBytes, err := json.Marshal(payload)
	if err != nil {
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
