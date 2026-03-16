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

const linkedDeviceCollectionName = "linked_devices"

type LinkedDeviceRepository struct {
	collection *mongo.Collection
}

func NewLinkedDeviceRepository(db *mongo.Database) domain.LinkedDeviceRepository {
	repo := &LinkedDeviceRepository{
		collection: db.Collection(linkedDeviceCollectionName),
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := repo.EnsureIndexes(ctx); err != nil {
		log.Printf("failed to ensure linked_devices indexes: %v", err)
	}
	return repo
}

// EnsureIndexes creates the required indexes for the linked_devices collection:
// - user_id index for querying a user's linked devices
// - TTL index on expires_at for 30-day auto-expiry of inactive devices
func (r *LinkedDeviceRepository) EnsureIndexes(ctx context.Context) error {
	models := []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "user_id", Value: 1}},
			Options: options.Index().SetBackground(true).SetName("user_id_idx"),
		},
		{
			Keys:    bson.D{{Key: "expires_at", Value: 1}},
			Options: options.Index().SetBackground(true).SetName("expires_at_ttl_idx").SetExpireAfterSeconds(0),
		},
	}
	_, err := r.collection.Indexes().CreateMany(ctx, models)
	return err
}

func (r *LinkedDeviceRepository) Create(ctx context.Context, device *domain.LinkedDevice) error {
	_, err := r.collection.InsertOne(ctx, device)
	return err
}

func (r *LinkedDeviceRepository) Delete(ctx context.Context, deviceID string) error {
	_, err := r.collection.DeleteOne(ctx, bson.M{"_id": deviceID})
	return err
}

func (r *LinkedDeviceRepository) DeleteByUserID(ctx context.Context, userID string) error {
	_, err := r.collection.DeleteMany(ctx, bson.M{"user_id": userID})
	return err
}

func (r *LinkedDeviceRepository) GetByID(ctx context.Context, deviceID string) (*domain.LinkedDevice, error) {
	var device domain.LinkedDevice
	err := r.collection.FindOne(ctx, bson.M{"_id": deviceID}).Decode(&device)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, nil
		}
		return nil, err
	}
	return &device, nil
}

func (r *LinkedDeviceRepository) GetByUserID(ctx context.Context, userID string) ([]*domain.LinkedDevice, error) {
	cursor, err := r.collection.Find(ctx, bson.M{"user_id": userID})
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var devices []*domain.LinkedDevice
	for cursor.Next(ctx) {
		var d domain.LinkedDevice
		if err := cursor.Decode(&d); err != nil {
			return nil, err
		}
		devices = append(devices, &d)
	}
	if err := cursor.Err(); err != nil {
		return nil, err
	}
	return devices, nil
}

func (r *LinkedDeviceRepository) CountByUserID(ctx context.Context, userID string) (int, error) {
	count, err := r.collection.CountDocuments(ctx, bson.M{"user_id": userID})
	if err != nil {
		return 0, err
	}
	return int(count), nil
}

func (r *LinkedDeviceRepository) UpdateLastActive(ctx context.Context, deviceID string) error {
	update := bson.M{
		"$set": bson.M{
			"last_active_at": time.Now(),
		},
	}
	_, err := r.collection.UpdateOne(ctx, bson.M{"_id": deviceID}, update)
	return err
}
