package services

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"chatwme/backend/database"
	"chatwme/backend/messaging"
	"chatwme/backend/models"
	"chatwme/backend/utils"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

type ChatService struct {
	store         database.Store
	encryptionKey []byte
	cache         *CacheService
	mq            *messaging.RabbitMQClient
}

func NewChatService(store database.Store, encryptionKey []byte, cache *CacheService, mq *messaging.RabbitMQClient) *ChatService {
	return &ChatService{
		store:         store,
		encryptionKey: encryptionKey,
		cache:         cache,
		mq:            mq,
	}
}

func (s *ChatService) SaveMessage(ctx context.Context, senderID, senderName, roomID, content, messageType, fileURL string, duration int, fileSize int64) (models.Message, error) {
	encryptedContent, err := utils.Encrypt(content, s.encryptionKey)
	if err != nil {
		return models.Message{}, err
	}

	message := models.Message{
		ID:         primitive.NewObjectID(),
		SenderID:   senderID,
		SenderName: senderName,
		Room:       roomID,
		Content:    encryptedContent,
		FileURL:    fileURL,
		Duration:   duration,
		FileSize:   fileSize,
		Timestamp:  time.Now(),
		Type:       messageType,
	}

	collection := s.store.Collection("messages")
	if _, err := collection.InsertOne(ctx, message); err != nil {
		return models.Message{}, err
	}

	// Publish to RabbitMQ (Fire and Forget)
	if s.mq != nil {
		go func() {
			payload, _ := json.Marshal(message)
			mqCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			// Routing key: chat.room.{roomID}
			routingKey := fmt.Sprintf("chat.room.%s", roomID)
			s.mq.PublishMessage(mqCtx, routingKey, payload)
		}()
	}

	return message, nil
}

func (s *ChatService) SaveMessageWithID(ctx context.Context, messageIDHex, senderID, senderName, roomID, content, messageType, fileURL string, duration int, fileSize int64) (models.Message, bool, error) {
	encryptedContent, err := utils.Encrypt(content, s.encryptionKey)
	if err != nil {
		return models.Message{}, false, err
	}

	messageID, err := primitive.ObjectIDFromHex(messageIDHex)
	if err != nil {
		messageID = primitive.NewObjectID()
	}

	message := models.Message{
		ID:         messageID,
		SenderID:   senderID,
		SenderName: senderName,
		Room:       roomID,
		Content:    encryptedContent,
		FileURL:    fileURL,
		Duration:   duration,
		FileSize:   fileSize,
		Timestamp:  time.Now(),
		Type:       messageType,
	}

	collection := s.store.Collection("messages")
	if _, err := collection.InsertOne(ctx, message); err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return message, false, nil
		}
		return models.Message{}, false, err
	}

	// Publish to RabbitMQ (Fire and Forget)
	if s.mq != nil {
		go func() {
			payload, _ := json.Marshal(message)
			mqCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			// Routing key: chat.room.{roomID}
			routingKey := fmt.Sprintf("chat.room.%s", roomID)
			s.mq.PublishMessage(mqCtx, routingKey, payload)
		}()
	}

	return message, true, nil
}

func (s *ChatService) UpdateRoomLastMessage(ctx context.Context, roomID primitive.ObjectID, lastMessage string, lastMessageTime time.Time) error {
	collection := s.store.Collection("chat_rooms")
	update := bson.M{
		"$set": bson.M{
			"last_message":      lastMessage,
			"last_message_time": lastMessageTime,
			"updated_at":        time.Now(),
		},
	}

	_, err := collection.UpdateOne(ctx, bson.M{"_id": roomID}, update)
	return err
}

func (s *ChatService) IsUserInRoom(ctx context.Context, roomID primitive.ObjectID, userID string) (bool, error) {
	// 1. Check Cache
	if s.cache != nil {
		isInRoom, found, err := s.cache.IsUserInRoom(ctx, userID, roomID.Hex())
		if err == nil && found {
			return isInRoom, nil
		}
	}

	// 2. Check Database
	collection := s.store.Collection("chat_rooms")
	filter := bson.M{
		"_id": roomID,
		"$or": []bson.M{
			{"participants": userID},
			{"created_by": userID},
		},
	}

	err := collection.FindOne(ctx, filter).Err()
	var result bool
	if err == nil {
		result = true
	} else if err == mongo.ErrNoDocuments {
		result = false
		err = nil // Reset error for return
	} else {
		return false, err
	}

	// 3. Update Cache (Async)
	if s.cache != nil {
		go func() {
			// Create a new context for cache update to avoid cancellation
			cacheCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			s.cache.SetUserInRoom(cacheCtx, userID, roomID.Hex(), result)
		}()
	}

	return result, nil
}

// MarkMessagesAsRead 标记房间内的消息为已读
func (s *ChatService) MarkMessagesAsRead(ctx context.Context, roomID primitive.ObjectID, userID string) error {
	collection := s.store.Collection("messages")

	// 更新该房间内所有非自己发送且未读的消息
	filter := bson.M{
		"room":      roomID.Hex(),
		"sender_id": bson.M{"$ne": userID},
		"read_by":   bson.M{"$ne": userID},
	}

	update := bson.M{
		"$addToSet": bson.M{
			"read_by": userID,
		},
	}

	_, err := collection.UpdateMany(ctx, filter, update)
	return err
}

// IsUserBlocked 檢查 blockedID 是否被 blockerID 封鎖
func (s *ChatService) IsUserBlocked(ctx context.Context, blockerID, blockedID string) (bool, error) {
	// 1. Check Cache
	if s.cache != nil {
		isBlocked, found, err := s.cache.IsUserBlocked(ctx, blockerID, blockedID)
		if err == nil && found {
			return isBlocked, nil
		}
	}

	// 2. Check Database
	collection := s.store.Collection("blocked_users")
	count, err := collection.CountDocuments(ctx, bson.M{
		"blocker_id": blockerID,
		"blocked_id": blockedID,
	})
	if err != nil {
		return false, err
	}
	result := count > 0

	// 3. Update Cache (Async)
	if s.cache != nil {
		go func() {
			cacheCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			s.cache.SetUserBlocked(cacheCtx, blockerID, blockedID, result)
		}()
	}

	return result, nil
}

func (s *ChatService) IsUserBlockedByAny(ctx context.Context, blockerIDs []string, blockedID string) (bool, error) {
	if len(blockerIDs) == 0 {
		return false, nil
	}
	collection := s.store.Collection("blocked_users")
	count, err := collection.CountDocuments(ctx, bson.M{
		"blocker_id": bson.M{"$in": blockerIDs},
		"blocked_id": blockedID,
	})
	return count > 0, err
}

// GetRoomParticipants 獲取聊天室的所有參與者 ID
func (s *ChatService) GetRoomParticipants(ctx context.Context, roomID primitive.ObjectID) ([]string, error) {
	// 1. Check Cache
	if s.cache != nil {
		participants, found, err := s.cache.GetRoomParticipants(ctx, roomID.Hex())
		if err == nil && found {
			return participants, nil
		}
	}

	// 2. Check Database
	collection := s.store.Collection("chat_rooms")
	var room models.ChatRoom
	err := collection.FindOne(ctx, bson.M{"_id": roomID}).Decode(&room)
	if err != nil {
		return nil, err
	}

	// 3. Update Cache (Async)
	if s.cache != nil {
		go func() {
			cacheCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			s.cache.SetRoomParticipants(cacheCtx, roomID.Hex(), room.Participants)
		}()
	}

	return room.Participants, nil
}

// CheckRateLimit checks if user is sending too many messages
func (s *ChatService) CheckRateLimit(ctx context.Context, userID string) (bool, error) {
	if s.cache == nil {
		return true, nil // No cache, no rate limit (or use memory?)
	}
	// Limit: 5 messages per second
	return s.cache.CheckRateLimit(ctx, userID, 5, 1*time.Second)
}
