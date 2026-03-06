package mongo_repo

import (
	"context"
	"time"

	"chatwmex_backend/internal/domain"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type roomLabelRepository struct {
	collection *mongo.Collection
}

func NewRoomLabelRepository(db *mongo.Database) domain.RoomLabelRepository {
	return &roomLabelRepository{
		collection: db.Collection("room_labels"),
	}
}

func (r *roomLabelRepository) Create(ctx context.Context, label *domain.RoomLabel) error {
	label.CreatedAt = time.Now()
	label.UpdatedAt = time.Now()
	if label.RoomIDs == nil {
		label.RoomIDs = make([]string, 0)
	}

	res, err := r.collection.InsertOne(ctx, label)
	if err != nil {
		return err
	}
	if oid, ok := res.InsertedID.(primitive.ObjectID); ok {
		label.ID = oid.Hex()
	}
	return nil
}

func (r *roomLabelRepository) GetByUserID(ctx context.Context, userID string) ([]*domain.RoomLabel, error) {
	opts := options.Find().SetSort(bson.D{{Key: "sort_order", Value: 1}})
	cursor, err := r.collection.Find(ctx, bson.M{"user_id": userID}, opts)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var labels []*domain.RoomLabel
	if err := cursor.All(ctx, &labels); err != nil {
		return nil, err
	}
	if labels == nil {
		labels = make([]*domain.RoomLabel, 0)
	}
	return labels, nil
}

func (r *roomLabelRepository) GetByID(ctx context.Context, id string) (*domain.RoomLabel, error) {
	oid, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return nil, err
	}

	var label domain.RoomLabel
	if err := r.collection.FindOne(ctx, bson.M{"_id": oid}).Decode(&label); err != nil {
		return nil, err
	}
	return &label, nil
}

func (r *roomLabelRepository) Update(ctx context.Context, label *domain.RoomLabel) error {
	oid, err := primitive.ObjectIDFromHex(label.ID)
	if err != nil {
		return err
	}

	label.UpdatedAt = time.Now()
	update := bson.M{
		"$set": bson.M{
			"name":       label.Name,
			"is_enabled": label.IsEnabled,
			"room_ids":   label.RoomIDs,
			"updated_at": label.UpdatedAt,
		},
	}

	_, err = r.collection.UpdateOne(ctx, bson.M{"_id": oid, "user_id": label.UserID}, update)
	return err
}

func (r *roomLabelRepository) Delete(ctx context.Context, id string, userID string) error {
	oid, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return err
	}

	_, err = r.collection.DeleteOne(ctx, bson.M{"_id": oid, "user_id": userID})
	return err
}

func (r *roomLabelRepository) ReorderLabels(ctx context.Context, userID string, orderedIDs []string) error {
	// Reorder using a series of update operations or a bulk write.
	var models []mongo.WriteModel

	for i, id := range orderedIDs {
		oid, err := primitive.ObjectIDFromHex(id)
		if err != nil {
			return err
		}
		model := mongo.NewUpdateOneModel().
			SetFilter(bson.M{"_id": oid, "user_id": userID}).
			SetUpdate(bson.M{"$set": bson.M{"sort_order": i, "updated_at": time.Now()}})
		models = append(models, model)
	}

	if len(models) == 0 {
		return nil
	}

	_, err := r.collection.BulkWrite(ctx, models)
	return err
}
