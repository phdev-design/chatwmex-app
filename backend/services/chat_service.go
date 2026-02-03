package services

import (
	"context"
	"time"

	"chatwme/backend/database"
	"chatwme/backend/models"
	"chatwme/backend/utils"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

type ChatService struct {
	store         database.Store
	encryptionKey []byte
}

func NewChatService(store database.Store, encryptionKey []byte) *ChatService {
	return &ChatService{
		store:         store,
		encryptionKey: encryptionKey,
	}
}

func (s *ChatService) SaveMessage(ctx context.Context, senderID, senderName, roomID, content, messageType string) (models.Message, error) {
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
		Timestamp:  time.Now(),
		Type:       messageType,
	}

	collection := s.store.Collection("messages")
	if _, err := collection.InsertOne(ctx, message); err != nil {
		return models.Message{}, err
	}

	return message, nil
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
	collection := s.store.Collection("chat_rooms")
	filter := bson.M{
		"_id": roomID,
		"$or": []bson.M{
			{"participants": userID},
			{"created_by": userID},
		},
	}

	err := collection.FindOne(ctx, filter).Err()
	if err == nil {
		return true, nil
	}
	if err == mongo.ErrNoDocuments {
		return false, nil
	}
	return false, err
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
