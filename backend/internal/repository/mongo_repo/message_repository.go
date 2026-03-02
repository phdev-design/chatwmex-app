package mongo_repo

import (
	"context"
	"fmt"
	"log"
	"time"

	"chatwmex_backend/internal/domain"
	"chatwmex_backend/pkg/crypto"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const messageCollectionName = "messages"
const offlineCollectionName = "offline_messages"

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

type offlineMessage struct {
	ID      primitive.ObjectID `bson:"_id,omitempty"`
	UserID  string             `bson:"user_id"` // Recipient
	Message mongoMessage       `bson:"message"`
}

// MessageRepository implements domain.MessageRepository for MongoDB.
type MessageRepository struct {
	collection        *mongo.Collection
	offlineCollection *mongo.Collection
	cryptor           *crypto.AESCrypto
}

// NewMessageRepository creates a new instance of MessageRepository.
func NewMessageRepository(db *mongo.Database, cryptor *crypto.AESCrypto) domain.MessageRepository {
	return &MessageRepository{
		collection:        db.Collection(messageCollectionName),
		offlineCollection: db.Collection(offlineCollectionName),
		cryptor:           cryptor,
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
	
	readBy := m.ReadBy
	if readBy == nil {
		readBy = []string{}
	}

	return &mongoMessage{
		ID:         id,
		SenderID:   m.SenderID,
		ReceiverID: m.ReceiverID,
		RoomID:     m.RoomID,
		Content:    encryptedContent,
		Type:       m.Type,
		IsRead:     m.IsRead,
		ReadBy:     readBy,
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

// StoreOfflineMessage stores a message for offline delivery.
func (r *MessageRepository) StoreOfflineMessage(ctx context.Context, userID string, msg *domain.Message) error {
	mongoMsg, err := r.fromDomain(msg)
	if err != nil {
		return err
	}

	offlineMsg := offlineMessage{
		UserID:  userID,
		Message: *mongoMsg,
	}

	_, err = r.offlineCollection.InsertOne(ctx, offlineMsg)
	if err != nil {
		return fmt.Errorf("failed to insert offline message: %w", err)
	}

	return nil
}

// GetOfflineMessages retrieves and deletes offline messages for a user.
func (r *MessageRepository) GetOfflineMessages(ctx context.Context, userID string) ([]*domain.Message, error) {
	filter := bson.M{"user_id": userID}
	
	cursor, err := r.offlineCollection.Find(ctx, filter)
	if err != nil {
		return nil, fmt.Errorf("failed to find offline messages: %w", err)
	}
	defer cursor.Close(ctx)

	var messages []*domain.Message
	for cursor.Next(ctx) {
		var offMsg offlineMessage
		if err := cursor.Decode(&offMsg); err != nil {
			continue
		}

		domainMsg, err := r.toDomain(&offMsg.Message)
		if err != nil {
			continue
		}
		messages = append(messages, domainMsg)
	}

	// Delete fetched messages
	// In a robust system, we would wait for ACK. Here we assume successful delivery or re-fetch.
	// But to avoid infinite loop if delivery fails, we delete.
	// Or maybe delete after successful delivery?
	// The requirement "offline queue" usually implies "try to deliver once connected".
	// If we delete now, and websocket write fails, message is lost from "offline queue" but exists in "history".
	// This is acceptable for this scope.
	_, err = r.offlineCollection.DeleteMany(ctx, filter)
	if err != nil {
		// Log error but return messages
		fmt.Printf("Error deleting offline messages: %v\n", err)
	}

	return messages, nil
}

// GetConversations retrieves DM conversations for a user.
func (r *MessageRepository) GetConversations(ctx context.Context, userID string) ([]*domain.Conversation, error) {
	// Aggregation pipeline to find last message for each conversation
	pipeline := mongo.Pipeline{
		// 1. Match: Messages where I am sender or receiver, AND not a room message
		{{Key: "$match", Value: bson.M{
			"$or": []bson.M{
				{"sender_id": userID},
				{"receiver_id": userID},
			},
			"room_id": bson.M{"$in": []interface{}{"", nil}},
		}}},
		// 2. Sort by created_at desc
		{{Key: "$sort", Value: bson.M{"created_at": -1}}},
		// 3. Project "other_id"
		{{Key: "$project", Value: bson.M{
			"sender_id": 1, "receiver_id": 1, "content": 1, "created_at": 1, "is_read": 1, "read_by": 1,
			"other_id": bson.M{
				"$cond": bson.M{
					"if":   bson.M{"$eq": []interface{}{"$sender_id", userID}},
					"then": "$receiver_id",
					"else": "$sender_id",
				},
			},
		}}},
		// 4. Group by other_id
		{{Key: "$group", Value: bson.M{
			"_id":              "$other_id",
			"last_message_doc": bson.M{"$first": "$$ROOT"},
			"unread_count": bson.M{
				"$sum": bson.M{
					"$cond": bson.M{
						"if": bson.M{
							"$and": []interface{}{
								bson.M{"$eq": []interface{}{"$receiver_id", userID}},
								bson.M{"$eq": []interface{}{"$is_read", false}},
							},
						},
						"then": 1,
						"else": 0,
					},
				},
			},
			"last_read_at": bson.M{
				"$max": bson.M{
					"$cond": bson.M{
						"if": bson.M{
							"$and": []interface{}{
								bson.M{"$eq": []interface{}{"$receiver_id", userID}},
								bson.M{"$eq": []interface{}{"$is_read", true}},
							},
						},
						"then": "$created_at",
						"else": nil,
					},
				},
			},
		}}},
		// 5. Lookup User details
		// Convert _id (string) to ObjectID if needed?
		// User IDs are strings (hex of ObjectID) in this app.
		// In mongoUser, ID is ObjectID. In message, sender_id/receiver_id are strings.
		// So we need to convert string ID to ObjectID for lookup.
		{{Key: "$addFields", Value: bson.M{
			"other_oid": bson.M{"$toObjectId": "$_id"},
		}}},
		{{Key: "$lookup", Value: bson.M{
			"from":         "users",
			"localField":   "other_oid",
			"foreignField": "_id",
			"as":           "user_info",
		}}},
		{{Key: "$unwind", Value: bson.M{"path": "$user_info", "preserveNullAndEmptyArrays": true}}},
	}

	cursor, err := r.collection.Aggregate(ctx, pipeline)
	if err != nil {
		return nil, fmt.Errorf("failed to aggregate conversations: %w", err)
	}
	defer cursor.Close(ctx)

	var results []struct {
		OtherUserID    string       `bson:"_id"`
		LastMessageDoc mongoMessage `bson:"last_message_doc"`
		UnreadCount    int          `bson:"unread_count"`
		LastReadAt     time.Time    `bson:"last_read_at"`
		UserInfo       struct {
			Username string `bson:"username"`
		} `bson:"user_info"`
	}

	if err := cursor.All(ctx, &results); err != nil {
		return nil, fmt.Errorf("failed to decode conversations: %w", err)
	}

	var conversations []*domain.Conversation
	for _, res := range results {
		// Decrypt last message content
		content, err := r.cryptor.Decrypt(res.LastMessageDoc.Content)
		if err != nil {
			content = "[Encrypted Message]"
		}

		conversations = append(conversations, &domain.Conversation{
			OtherUserID:     res.OtherUserID,
			OtherUsername:   res.UserInfo.Username,
			LastMessage:     content,
			LastMessageTime: res.LastMessageDoc.CreatedAt,
			UnreadCount:     res.UnreadCount,
			LastReadAt:      res.LastReadAt,
		})
	}

	return conversations, nil
}

func (r *MessageRepository) CountUnreadInRoom(ctx context.Context, roomID, userID string) (int, error) {
	filter := bson.M{
		"room_id":   roomID,
		"sender_id": bson.M{"$ne": userID},
		"read_by":   bson.M{"$ne": userID},
	}
	count, err := r.collection.CountDocuments(ctx, filter)
	if err != nil {
		return 0, fmt.Errorf("failed to count unread messages: %w", err)
	}
	return int(count), nil
}

func (r *MessageRepository) GetRoomLastReadAt(ctx context.Context, roomID, userID string) (time.Time, error) {
	filter := bson.M{
		"room_id": roomID,
		"read_by": userID,
	}
	opts := options.FindOne().SetSort(bson.D{{Key: "created_at", Value: -1}})
	var msg mongoMessage
	err := r.collection.FindOne(ctx, filter, opts).Decode(&msg)
	if err == mongo.ErrNoDocuments {
		return time.Time{}, nil
	}
	if err != nil {
		return time.Time{}, fmt.Errorf("failed to get last read message: %w", err)
	}
	return msg.CreatedAt, nil
}

func (r *MessageRepository) CountUnreadInRoomAfter(ctx context.Context, roomID, userID string, lastReadAt time.Time) (int, error) {
	filter := bson.M{
		"room_id":   roomID,
		"sender_id": bson.M{"$ne": userID},
	}
	if !lastReadAt.IsZero() {
		filter["created_at"] = bson.M{"$gt": lastReadAt}
	}
	count, err := r.collection.CountDocuments(ctx, filter)
	if err != nil {
		return 0, fmt.Errorf("failed to count unread messages: %w", err)
	}
	return int(count), nil
}

func (r *MessageRepository) MarkMessageAsReadBy(ctx context.Context, messageID string, userID string) error {
	oid, err := primitive.ObjectIDFromHex(messageID)
	if err != nil {
		return fmt.Errorf("invalid object ID: %w", err)
	}
	update := bson.M{"$addToSet": bson.M{"read_by": userID}}
	result, err := r.collection.UpdateOne(ctx, bson.M{"_id": oid}, update)
	if err != nil {
		return fmt.Errorf("failed to mark message as read: %w", err)
	}
	if result.MatchedCount == 0 {
		return fmt.Errorf("message not found")
	}
	return nil
}

func (r *MessageRepository) GetRoomMessageMap(ctx context.Context, messageIDs []string) (map[string][]string, error) {
	if len(messageIDs) == 0 {
		return map[string][]string{}, nil
	}

	objectIDs := make([]primitive.ObjectID, 0, len(messageIDs))
	for _, id := range messageIDs {
		if id == "" {
			continue
		}
		oid, err := primitive.ObjectIDFromHex(id)
		if err != nil {
			return nil, fmt.Errorf("invalid object ID: %w", err)
		}
		objectIDs = append(objectIDs, oid)
	}
	if len(objectIDs) == 0 {
		return map[string][]string{}, nil
	}

	cursor, err := r.collection.Find(ctx, bson.M{"_id": bson.M{"$in": objectIDs}})
	if err != nil {
		return nil, fmt.Errorf("failed to query messages: %w", err)
	}
	defer cursor.Close(ctx)

	roomMap := map[string][]string{}
	for cursor.Next(ctx) {
		var msg mongoMessage
		if err := cursor.Decode(&msg); err != nil {
			return nil, err
		}
		if msg.RoomID == "" {
			continue
		}
		roomMap[msg.RoomID] = append(roomMap[msg.RoomID], msg.ID.Hex())
	}
	if err := cursor.Err(); err != nil {
		return nil, err
	}
	return roomMap, nil
}

func (r *MessageRepository) MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error {
	var filter bson.M
	var update bson.M

	_, _ = r.collection.UpdateMany(
		ctx,
		bson.M{"read_by": bson.M{"$type": 10}},
		bson.M{"$set": bson.M{"read_by": []string{}}},
	)

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

	result, err := r.collection.UpdateMany(ctx, filter, update)
	if err != nil {
		return fmt.Errorf("failed to mark messages as read: %w", err)
	}
	log.Printf("mark_read user=%s conversation=%s is_room=%v matched=%d modified=%d", userID, conversationID, isRoom, result.MatchedCount, result.ModifiedCount)
	return nil
}
