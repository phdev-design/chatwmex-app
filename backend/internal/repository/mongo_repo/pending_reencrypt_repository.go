package mongo_repo

import (
	"context"
	"log"
	"time"

	"chatwmex_backend/internal/domain"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const pendingReEncryptCollectionName = "pending_reencrypt_requests"

// mongoPendingReEncryptRequest is the DTO for storing pending re-encrypt requests in MongoDB.
type mongoPendingReEncryptRequest struct {
	ID         primitive.ObjectID `bson:"_id,omitempty"`
	MessageID  string             `bson:"message_id"`
	SenderID   string             `bson:"sender_id"`
	ReceiverID string             `bson:"receiver_id"`
	RoomID     string             `bson:"room_id"`
	CreatedAt  time.Time          `bson:"created_at"`
	ExpiresAt  time.Time          `bson:"expires_at"`
}

// PendingReEncryptRepository implements domain.PendingReEncryptRepository for MongoDB.
type PendingReEncryptRepository struct {
	collection *mongo.Collection
}

// NewPendingReEncryptRepository creates a new instance of PendingReEncryptRepository.
func NewPendingReEncryptRepository(db *mongo.Database) domain.PendingReEncryptRepository {
	repo := &PendingReEncryptRepository{
		collection: db.Collection(pendingReEncryptCollectionName),
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := repo.EnsureIndexes(ctx); err != nil {
		log.Printf("failed to ensure pending_reencrypt indexes: %v", err)
	}
	return repo
}

// EnsureIndexes creates the necessary indexes for the pending_reencrypt_requests collection.
func (r *PendingReEncryptRepository) EnsureIndexes(ctx context.Context) error {
	background := true
	models := []mongo.IndexModel{
		{
			// TTL index on expiresAt field - MongoDB will automatically delete documents after expiration
			Keys:    bson.D{{Key: "expires_at", Value: 1}},
			Options: options.Index().SetBackground(background).SetName("expires_at_ttl_idx").SetExpireAfterSeconds(0),
		},
		{
			// Compound index on senderId + createdAt for query optimization
			// This optimizes the query when sender reconnects and we need to fetch all pending requests
			Keys: bson.D{
				{Key: "sender_id", Value: 1},
				{Key: "created_at", Value: 1},
			},
			Options: options.Index().SetBackground(background).SetName("sender_created_idx"),
		},
		{
			// Index on messageId + receiverId for efficient deletion after successful delivery
			Keys: bson.D{
				{Key: "message_id", Value: 1},
				{Key: "receiver_id", Value: 1},
			},
			Options: options.Index().SetBackground(background).SetName("message_receiver_idx"),
		},
	}

	_, err := r.collection.Indexes().CreateMany(ctx, models)
	if err != nil {
		return err
	}
	return nil
}

// Store saves a pending re-encrypt request to MongoDB.
func (r *PendingReEncryptRepository) Store(ctx context.Context, req *domain.PendingReEncryptRequest) error {
	mongoReq := &mongoPendingReEncryptRequest{
		MessageID:  req.MessageID,
		SenderID:   req.SenderID,
		ReceiverID: req.ReceiverID,
		RoomID:     req.RoomID,
		CreatedAt:  req.CreatedAt,
		ExpiresAt:  req.ExpiresAt,
	}

	result, err := r.collection.InsertOne(ctx, mongoReq)
	if err != nil {
		return err
	}

	// Set the generated ID back to the domain object
	if oid, ok := result.InsertedID.(primitive.ObjectID); ok {
		req.ID = oid.Hex()
	}

	return nil
}

// GetBySenderID retrieves all pending requests for a specific sender, sorted by creation time.
func (r *PendingReEncryptRepository) GetBySenderID(ctx context.Context, senderID string) ([]*domain.PendingReEncryptRequest, error) {
	filter := bson.M{"sender_id": senderID}
	opts := options.Find().SetSort(bson.D{{Key: "created_at", Value: 1}})

	cursor, err := r.collection.Find(ctx, filter, opts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var mongoReqs []*mongoPendingReEncryptRequest
	if err := cursor.All(ctx, &mongoReqs); err != nil {
		return nil, err
	}

	// Convert to domain objects
	requests := make([]*domain.PendingReEncryptRequest, 0, len(mongoReqs))
	for _, mongoReq := range mongoReqs {
		requests = append(requests, &domain.PendingReEncryptRequest{
			ID:         mongoReq.ID.Hex(),
			MessageID:  mongoReq.MessageID,
			SenderID:   mongoReq.SenderID,
			ReceiverID: mongoReq.ReceiverID,
			RoomID:     mongoReq.RoomID,
			CreatedAt:  mongoReq.CreatedAt,
			ExpiresAt:  mongoReq.ExpiresAt,
		})
	}

	return requests, nil
}

// Delete removes a pending request by its ID.
func (r *PendingReEncryptRepository) Delete(ctx context.Context, id string) error {
	oid, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return err
	}

	filter := bson.M{"_id": oid}
	_, err = r.collection.DeleteOne(ctx, filter)
	return err
}

// DeleteByMessageID removes a pending request by message ID and receiver ID.
func (r *PendingReEncryptRepository) DeleteByMessageID(ctx context.Context, messageID, receiverID string) error {
	filter := bson.M{
		"message_id":  messageID,
		"receiver_id": receiverID,
	}
	_, err := r.collection.DeleteOne(ctx, filter)
	return err
}
