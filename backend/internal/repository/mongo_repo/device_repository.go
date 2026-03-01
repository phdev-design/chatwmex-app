package mongo_repo

import (
	"context"
	"time"

	"chatwmex_backend/internal/domain"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const deviceCollectionName = "devices"

type DeviceRepository struct {
	collection *mongo.Collection
}

func NewDeviceRepository(db *mongo.Database) domain.DeviceRepository {
	collection := db.Collection(deviceCollectionName)
	
	// Ensure index on user_id
	model := mongo.IndexModel{
		Keys:    bson.D{{Key: "user_id", Value: 1}},
		Options: options.Index().SetBackground(true),
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	collection.Indexes().CreateOne(ctx, model)
	
	return &DeviceRepository{collection: collection}
}

func (r *DeviceRepository) Upsert(ctx context.Context, device *domain.Device) error {
	// If device exists, update its user_id and last_active.
	// This naturally handles account switching: Token T1 will move from User A to User B.
	filter := bson.M{"_id": device.ID}
	update := bson.M{
		"$set": bson.M{
			"user_id":     device.UserID,
			"platform":    device.Platform,
			"last_active": time.Now(),
		},
	}
	opts := options.Update().SetUpsert(true)
	_, err := r.collection.UpdateOne(ctx, filter, update, opts)
	return err
}

func (r *DeviceRepository) Delete(ctx context.Context, deviceID string) error {
	_, err := r.collection.DeleteOne(ctx, bson.M{"_id": deviceID})
	return err
}

func (r *DeviceRepository) DeleteByUserID(ctx context.Context, userID string) error {
	_, err := r.collection.DeleteMany(ctx, bson.M{"user_id": userID})
	return err
}

func (r *DeviceRepository) GetByID(ctx context.Context, deviceID string) (*domain.Device, error) {
	var d domain.Device
	err := r.collection.FindOne(ctx, bson.M{"_id": deviceID}).Decode(&d)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, nil
		}
		return nil, err
	}
	return &d, nil
}
