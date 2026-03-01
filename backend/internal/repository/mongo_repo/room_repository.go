package mongo_repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"chatwmex_backend/internal/domain"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

const roomCollectionName = "rooms"

type mongoRoom struct {
	ID        primitive.ObjectID `bson:"_id,omitempty"`
	Name      string             `bson:"name"`
	OwnerID   string             `bson:"owner_id"`
	Members   []string           `bson:"members"`
	CreatedAt time.Time          `bson:"created_at"`
	UpdatedAt time.Time          `bson:"updated_at"`
}

type RoomRepository struct {
	collection *mongo.Collection
}

func NewRoomRepository(db *mongo.Database) domain.RoomRepository {
	return &RoomRepository{
		collection: db.Collection(roomCollectionName),
	}
}

func (r *RoomRepository) toDomain(mr *mongoRoom) *domain.Room {
	return &domain.Room{
		ID:        mr.ID.Hex(),
		Name:      mr.Name,
		OwnerID:   mr.OwnerID,
		Members:   mr.Members,
		CreatedAt: mr.CreatedAt,
		UpdatedAt: mr.UpdatedAt,
	}
}

func (r *RoomRepository) fromDomain(dr *domain.Room) (*mongoRoom, error) {
	id := primitive.NilObjectID
	if dr.ID != "" {
		var err error
		id, err = primitive.ObjectIDFromHex(dr.ID)
		if err != nil {
			return nil, fmt.Errorf("invalid object ID: %w", err)
		}
	}
	return &mongoRoom{
		ID:        id,
		Name:      dr.Name,
		OwnerID:   dr.OwnerID,
		Members:   dr.Members,
		CreatedAt: dr.CreatedAt,
		UpdatedAt: dr.UpdatedAt,
	}, nil
}

func (r *RoomRepository) Create(ctx context.Context, room *domain.Room) error {
	mr, err := r.fromDomain(room)
	if err != nil {
		return err
	}
	if mr.ID == primitive.NilObjectID {
		mr.ID = primitive.NewObjectID()
	}
	now := time.Now()
	if mr.CreatedAt.IsZero() {
		mr.CreatedAt = now
	}
	mr.UpdatedAt = now

	_, err = r.collection.InsertOne(ctx, mr)
	if err != nil {
		return fmt.Errorf("failed to create room: %w", err)
	}

	room.ID = mr.ID.Hex()
	room.CreatedAt = mr.CreatedAt
	room.UpdatedAt = mr.UpdatedAt
	return nil
}

func (r *RoomRepository) GetByID(ctx context.Context, id string) (*domain.Room, error) {
	oid, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return nil, fmt.Errorf("invalid object ID: %w", err)
	}

	var mr mongoRoom
	if err := r.collection.FindOne(ctx, bson.M{"_id": oid}).Decode(&mr); err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, errors.New("room not found")
		}
		return nil, fmt.Errorf("failed to get room: %w", err)
	}
	return r.toDomain(&mr), nil
}

func (r *RoomRepository) AddMember(ctx context.Context, roomID string, userID string) error {
	oid, err := primitive.ObjectIDFromHex(roomID)
	if err != nil {
		return fmt.Errorf("invalid object ID: %w", err)
	}

	// Use $addToSet to avoid duplicates
	update := bson.M{"$addToSet": bson.M{"members": userID}, "$set": bson.M{"updated_at": time.Now()}}
	_, err = r.collection.UpdateOne(ctx, bson.M{"_id": oid}, update)
	if err != nil {
		return fmt.Errorf("failed to add member: %w", err)
	}
	return nil
}

func (r *RoomRepository) RemoveMember(ctx context.Context, roomID string, userID string) error {
	oid, err := primitive.ObjectIDFromHex(roomID)
	if err != nil {
		return fmt.Errorf("invalid object ID: %w", err)
	}

	update := bson.M{"$pull": bson.M{"members": userID}, "$set": bson.M{"updated_at": time.Now()}}
	_, err = r.collection.UpdateOne(ctx, bson.M{"_id": oid}, update)
	if err != nil {
		return fmt.Errorf("failed to remove member: %w", err)
	}
	return nil
}

func (r *RoomRepository) GetMembers(ctx context.Context, roomID string) ([]string, error) {
	room, err := r.GetByID(ctx, roomID)
	if err != nil {
		return nil, err
	}
	return room.Members, nil
}

func (r *RoomRepository) GetUserRooms(ctx context.Context, userID string) ([]*domain.Room, error) {
	filter := bson.M{"members": userID}
	cursor, err := r.collection.Find(ctx, filter)
	if err != nil {
		return nil, fmt.Errorf("failed to find user rooms: %w", err)
	}
	defer cursor.Close(ctx)

	var rooms []*domain.Room
	for cursor.Next(ctx) {
		var mr mongoRoom
		if err := cursor.Decode(&mr); err != nil {
			return nil, err
		}
		rooms = append(rooms, r.toDomain(&mr))
	}
	return rooms, nil
}
