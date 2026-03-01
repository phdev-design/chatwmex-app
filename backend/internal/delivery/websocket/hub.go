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
}

// NewHub creates a new Hub instance.
func NewHub(mu domain.MessageUsecase, ru domain.RoomUsecase, or domain.OnlineRepository, rabbit *rabbitmq.RabbitMQClient, rabbitIngress <-chan *domain.Message) *Hub {
	return &Hub{
		broadcast:      make(chan *domain.Message),
		register:       make(chan *Client),
		unregister:     make(chan *Client),
		clients:        make(map[*Client]bool),
		userClients:    make(map[string]*Client),
		messageUsecase: mu,
		roomUsecase:    ru,
		onlineRepo:     or,
		rabbitMQ:       rabbit,
		rabbitIngress:  rabbitIngress,
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
		}
	}
}

// routeMessage handles the delivery of a message to connected clients.
func (h *Hub) routeMessage(msg *domain.Message) {
	messageBytes, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Error encoding message for broadcast: %v", err)
		return
	}

	// 1. Send to Receiver (1-on-1)
	if msg.ReceiverID != "" {
		if destClient, ok := h.userClients[msg.ReceiverID]; ok {
			select {
			case destClient.send <- messageBytes:
			default:
				close(destClient.send)
				delete(h.clients, destClient)
				delete(h.userClients, destClient.userID)
			}
		}
	}

	// 2. Send back to Sender (Confirmation)
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

	// 3. Room Logic (Group Chat)
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
	}
}
