package mongo_repo

import (
	"context"
	"fmt"
	"time"

	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/crypto"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const messageCollectionName = "messages"

// mongoMessage is the DTO for storing messages in MongoDB.
// It is internal to this package and should not be exposed.
type mongoMessage struct {
	ID         primitive.ObjectID `bson:"_id,omitempty"`
	SenderID   string             `bson:"sender_id"`
	ReceiverID string             `bson:"receiver_id,omitempty"`
	RoomID     string             `bson:"room_id,omitempty"`
	Content    string             `bson:"content"` // Encrypted content
	CreatedAt  time.Time          `bson:"created_at"`
}

// MessageRepository implements domain.MessageRepository for MongoDB.
type MessageRepository struct {
	collection *mongo.Collection
	cryptor    *crypto.AESCrypto
}

// NewMessageRepository creates a new instance of MessageRepository.
func NewMessageRepository(db *mongo.Database, cryptor *crypto.AESCrypto) domain.MessageRepository {
	return &MessageRepository{
		collection: db.Collection(messageCollectionName),
		cryptor:    cryptor,
	}
}

	// toDomain converts a mongoMessage to a domain.Message.
	// It decrypts the content during the conversion.
	func (r *MessageRepository) toDomain(m *mongoMessage) (*domain.Message, error) {
		decryptedContent, err := r.cryptor.Decrypt(m.Content)
		if err != nil {
			return nil, fmt.Errorf("failed to decrypt message content: %w", err)
		}
	
		return &domain.Message{
			ID:         m.ID.Hex(),
			SenderID:   m.SenderID,
			ReceiverID: m.ReceiverID,
			RoomID:     m.RoomID,
			Content:    decryptedContent,
			CreatedAt:  m.CreatedAt,
		}, nil
	}
	
	// fromDomain converts a domain.Message to a mongoMessage.
	// It encrypts the content during the conversion.
	func (r *MessageRepository) fromDomain(m *domain.Message) (*mongoMessage, error) {
		encryptedContent, err := r.cryptor.Encrypt(m.Content)
		if err != nil {
			return nil, fmt.Errorf("failed to encrypt message content: %w", err)
		}
	
		id := primitive.NilObjectID
		if m.ID != "" {
			var err error
			id, err = primitive.ObjectIDFromHex(m.ID)
			if err != nil {
				return nil, fmt.Errorf("invalid object ID: %w", err)
			}
		}
	
		return &mongoMessage{
			ID:         id,
			SenderID:   m.SenderID,
			ReceiverID: m.ReceiverID,
			RoomID:     m.RoomID,
			Content:    encryptedContent,
			CreatedAt:  m.CreatedAt,
		}, nil
	}

// StoreMessage saves a message to the repository.
// It encrypts the message content before storing it in MongoDB.
func (r *MessageRepository) StoreMessage(ctx context.Context, msg *domain.Message) error {
	mongoMsg, err := r.fromDomain(msg)
	if err != nil {
		return err
	}

	// If ID is empty, let MongoDB generate it
	if mongoMsg.ID == primitive.NilObjectID {
		mongoMsg.ID = primitive.NewObjectID()
	}

	// Ensure CreatedAt is set
	if mongoMsg.CreatedAt.IsZero() {
		mongoMsg.CreatedAt = time.Now()
	}

	_, err = r.collection.InsertOne(ctx, mongoMsg)
	if err != nil {
		return fmt.Errorf("failed to insert message into MongoDB: %w", err)
	}

	// Update the domain object with the generated ID and timestamp
	msg.ID = mongoMsg.ID.Hex()
	msg.CreatedAt = mongoMsg.CreatedAt

	return nil
}

// GetHistoryMessages retrieves message history between a user and a contact (user or room).
// It decrypts the message content after retrieving it from MongoDB.
func (r *MessageRepository) GetHistoryMessages(ctx context.Context, userID string, contactID string, limit int, offset int) ([]*domain.Message, error) {
	// Construct query based on whether it's a direct message or a group message
	// This logic assumes contactID is either a userID (for DM) or a roomID (for group)
	// A more robust implementation might require a chatType parameter or checking if contactID is a room.
	// For simplicity, we'll assume:
	// If it's a DM, we look for messages where (Sender=userID AND Receiver=contactID) OR (Sender=contactID AND Receiver=userID)
	// If it's a Room, we look for messages where RoomID=contactID (assuming userID is a member, authorization should be handled in usecase)

	// Since we don't have explicit type, let's try to query for both scenarios or rely on the caller to provide correct context.
	// However, standard chat apps usually distinguish. Let's implementing a flexible query.
	
	// Strategy: We query for both cases.
	// Case 1: Direct Message
	dmFilter := bson.M{
		"$or": []bson.M{
			{"sender_id": userID, "receiver_id": contactID},
			{"sender_id": contactID, "receiver_id": userID},
		},
	}

	// Case 2: Group Message
	// If contactID is a roomID, we just filter by room_id.
	// But we don't know if contactID is a user or room here without more info.
	// For this implementation, let's assume if ReceiverID matches contactID it's DM, if RoomID matches contactID it's Group.
	// But usually contactID IS the roomID.
	
	// IMPROVED STRATEGY based on common patterns:
	// We'll search for messages where:
	// (RoomID == contactID)  <-- Group Chat
	// OR
	// (SenderID == userID AND ReceiverID == contactID) OR (SenderID == contactID AND ReceiverID == userID) <-- DM
	
	filter := bson.M{
		"$or": []bson.M{
			{"room_id": contactID},
			{
				"$and": []bson.M{
					{"sender_id": userID},
					{"receiver_id": contactID},
				},
			},
			{
				"$and": []bson.M{
					{"sender_id": contactID},
					{"receiver_id": userID},
				},
			},
		},
	}

	findOptions := options.Find()
	findOptions.SetSort(bson.D{{Key: "created_at", Value: -1}}) // Sort by newest first
	findOptions.SetLimit(int64(limit))
	findOptions.SetSkip(int64(offset))

	cursor, err := r.collection.Find(ctx, filter, findOptions)
	if err != nil {
		return nil, fmt.Errorf("failed to query messages: %w", err)
	}
	defer cursor.Close(ctx)

	var messages []*domain.Message
	for cursor.Next(ctx) {
		var m mongoMessage
		if err := cursor.Decode(&m); err != nil {
			return nil, fmt.Errorf("failed to decode message: %w", err)
		}

		domainMsg, err := r.toDomain(&m)
		if err != nil {
			// In case of decryption failure, we might want to skip the message or return an error.
			// Returning an error stops the whole history retrieval.
			// Logging and skipping might be better for resilience, but for strict security, we return error.
			return nil, fmt.Errorf("failed to convert/decrypt message %s: %w", m.ID.Hex(), err)
		}
		messages = append(messages, domainMsg)
	}

	if err := cursor.Err(); err != nil {
		return nil, fmt.Errorf("cursor error: %w", err)
	}

	return messages, nil
}
