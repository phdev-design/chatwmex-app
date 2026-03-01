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
	Type       string             `bson:"type"`
	IsRead     bool               `bson:"is_read"`
	ReadBy     []string           `bson:"read_by"`
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
		Type:       m.Type,
		IsRead:     m.IsRead,
		ReadBy:     m.ReadBy,
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
		Type:       m.Type,
		IsRead:     m.IsRead,
		ReadBy:     m.ReadBy,
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

func (r *MessageRepository) GetHistory(ctx context.Context, userID, contactID string, limit, offset int) ([]*domain.Message, error) {
	// Strategy: We query for both cases.
	// Case 1: Direct Message
	// dmFilter := bson.M{
	// 	"$or": []bson.M{
	// 		{"sender_id": userID, "receiver_id": contactID},
	// 		{"sender_id": contactID, "receiver_id": userID},
	// 	},
	// }

	// Case 2: Group Message
	// roomFilter := bson.M{"room_id": contactID}

	// Better: The caller should probably specify or we infer.
	// For simplicity, let's just use an $or query that covers both scenarios:
	// (sender=me AND receiver=contact) OR (sender=contact AND receiver=me) OR (room_id=contact)
	// Note: This assumes contactID is the roomID for group chats.
	
	filter := bson.M{
		"$or": []bson.M{
			{"sender_id": userID, "receiver_id": contactID},
			{"sender_id": contactID, "receiver_id": userID},
			{"room_id": contactID},
		},
	}
	
	findOptions := options.Find()
	findOptions.SetSort(bson.D{{Key: "created_at", Value: -1}}) // Newest first
	findOptions.SetLimit(int64(limit))
	findOptions.SetSkip(int64(offset))

	cursor, err := r.collection.Find(ctx, filter, findOptions)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch messages: %w", err)
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
			// Skip malformed/decryption error messages? or return error?
			// Let's log and skip for robustness
			continue 
		}
		messages = append(messages, domainMsg)
	}

	return messages, nil
}

// MarkAsRead marks messages as read.
func (r *MessageRepository) MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error {
	var filter bson.M
	var update bson.M

	if isRoom {
		// For rooms: Add userID to read_by array if not present, for messages in this room
		// Only update messages where userID is NOT in read_by
		filter = bson.M{
			"room_id": conversationID,
			"read_by": bson.M{"$ne": userID},
		}
		update = bson.M{"$addToSet": bson.M{"read_by": userID}}
	} else {
		// For DM: Mark messages SENT BY the other person (conversationID) as read.
		// SenderID = conversationID, ReceiverID = userID
		filter = bson.M{
			"sender_id": conversationID,
			"receiver_id": userID,
			"is_read": false,
		}
		update = bson.M{
			"$set": bson.M{"is_read": true},
			"$addToSet": bson.M{"read_by": userID},
		}
	}

	_, err := r.collection.UpdateMany(ctx, filter, update)
	if err != nil {
		return fmt.Errorf("failed to mark messages as read: %w", err)
	}
	return nil
}
