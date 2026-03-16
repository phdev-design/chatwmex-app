package mongo_repo

import (
	"context"
	"log"
	"time"

	"chatwmex_backend/internal/domain"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const offlineLinkedMessageCollectionName = "offline_messages_linked"

type OfflineLinkedMessageRepository struct {
	collection *mongo.Collection
}

func NewOfflineLinkedMessageRepository(db *mongo.Database) domain.OfflineLinkedMessageRepository {
	repo := &OfflineLinkedMessageRepository{
		collection: db.Collection(offlineLinkedMessageCollectionName),
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := repo.EnsureIndexes(ctx); err != nil {
		log.Printf("failed to ensure offline_messages_linked indexes: %v", err)
	}
	return repo
}

// EnsureIndexes creates the required indexes for the offline_messages_linked collection:
// - Compound index on device_id + created_at for time-ordered queries
// - TTL index on expires_at for 7-day auto-deletion of offline messages
func (r *OfflineLinkedMessageRepository) EnsureIndexes(ctx context.Context) error {
	models := []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "device_id", Value: 1}, {Key: "created_at", Value: 1}},
			Options: options.Index().SetBackground(true).SetName("device_id_created_at_idx"),
		},
		{
			Keys:    bson.D{{Key: "expires_at", Value: 1}},
			Options: options.Index().SetBackground(true).SetName("expires_at_ttl_idx").SetExpireAfterSeconds(0),
		},
	}
	_, err := r.collection.Indexes().CreateMany(ctx, models)
	return err
}

func (r *OfflineLinkedMessageRepository) Store(ctx context.Context, msg *domain.OfflineLinkedMessage) error {
	_, err := r.collection.InsertOne(ctx, msg)
	return err
}

func (r *OfflineLinkedMessageRepository) GetByDeviceID(ctx context.Context, deviceID string) ([]*domain.OfflineLinkedMessage, error) {
	opts := options.Find().SetSort(bson.D{{Key: "created_at", Value: 1}})
	cursor, err := r.collection.Find(ctx, bson.M{"device_id": deviceID}, opts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var messages []*domain.OfflineLinkedMessage
	for cursor.Next(ctx) {
		var m domain.OfflineLinkedMessage
		if err := cursor.Decode(&m); err != nil {
			return nil, err
		}
		messages = append(messages, &m)
	}
	if err := cursor.Err(); err != nil {
		return nil, err
	}
	return messages, nil
}

func (r *OfflineLinkedMessageRepository) DeleteByDeviceID(ctx context.Context, deviceID string) error {
	_, err := r.collection.DeleteMany(ctx, bson.M{"device_id": deviceID})
	return err
}
