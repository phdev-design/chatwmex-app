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
	"go.mongodb.org/mongo-driver/mongo/options"
)

const userCollectionName = "users"

// mongoUser is the DTO for storing user data in MongoDB.
// It is internal to this package and should not be exposed.
type mongoUser struct {
	ID           primitive.ObjectID `bson:"_id,omitempty"`
	Username     string             `bson:"username"`
	PasswordHash string             `bson:"password_hash"`
	CreatedAt    time.Time          `bson:"created_at"`
	UpdatedAt    time.Time          `bson:"updated_at"`
}

// UserRepository implements domain.UserRepository for MongoDB.
type UserRepository struct {
	collection *mongo.Collection
}

// NewUserRepository creates a new instance of UserRepository.
// It also ensures that a unique index on the username field exists.
func NewUserRepository(db *mongo.Database) domain.UserRepository {
	collection := db.Collection(userCollectionName)

	// Ensure unique index on username
	indexModel := mongo.IndexModel{
		Keys:    bson.D{{Key: "username", Value: 1}},
		Options: options.Index().SetUnique(true),
	}

	// We create the index in the background to avoid blocking, 
	// though for a new app this is fast.
	// In a real production scenario, index creation might be handled by migration scripts.
	// For simplicity here, we do it on startup but log errors instead of crashing.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	
	_, err := collection.Indexes().CreateOne(ctx, indexModel)
	if err != nil {
		fmt.Printf("Warning: failed to create unique index on users.username: %v\n", err)
	}

	return &UserRepository{
		collection: collection,
	}
}

// toDomain converts a mongoUser to a domain.User.
func (r *UserRepository) toDomain(u *mongoUser) *domain.User {
	return &domain.User{
		ID:           u.ID.Hex(),
		Username:     u.Username,
		PasswordHash: u.PasswordHash,
		CreatedAt:    u.CreatedAt,
		UpdatedAt:    u.UpdatedAt,
	}
}

// fromDomain converts a domain.User to a mongoUser.
func (r *UserRepository) fromDomain(u *domain.User) (*mongoUser, error) {
	id := primitive.NilObjectID
	if u.ID != "" {
		var err error
		id, err = primitive.ObjectIDFromHex(u.ID)
		if err != nil {
			return nil, fmt.Errorf("invalid object ID: %w", err)
		}
	}

	return &mongoUser{
		ID:           id,
		Username:     u.Username,
		PasswordHash: u.PasswordHash,
		CreatedAt:    u.CreatedAt,
		UpdatedAt:    u.UpdatedAt,
	}, nil
}

// Create inserts a new user into the database.
func (r *UserRepository) Create(ctx context.Context, user *domain.User) error {
	mongoUser, err := r.fromDomain(user)
	if err != nil {
		return err
	}

	if mongoUser.ID == primitive.NilObjectID {
		mongoUser.ID = primitive.NewObjectID()
	}

	now := time.Now()
	if mongoUser.CreatedAt.IsZero() {
		mongoUser.CreatedAt = now
	}
	mongoUser.UpdatedAt = now

	_, err = r.collection.InsertOne(ctx, mongoUser)
	if err != nil {
		// Check for duplicate key error
		if mongo.IsDuplicateKeyError(err) {
			return errors.New("username already exists")
		}
		return fmt.Errorf("failed to create user: %w", err)
	}

	// Update domain object with generated ID and timestamps
	user.ID = mongoUser.ID.Hex()
	user.CreatedAt = mongoUser.CreatedAt
	user.UpdatedAt = mongoUser.UpdatedAt

	return nil
}

// GetByID retrieves a user by their ID.
func (r *UserRepository) GetByID(ctx context.Context, id string) (*domain.User, error) {
	objectID, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return nil, fmt.Errorf("invalid object ID: %w", err)
	}

	var mUser mongoUser
	err = r.collection.FindOne(ctx, bson.M{"_id": objectID}).Decode(&mUser)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("failed to get user by ID: %w", err)
	}

	return r.toDomain(&mUser), nil
}

// GetByUsername retrieves a user by their username.
func (r *UserRepository) GetByUsername(ctx context.Context, username string) (*domain.User, error) {
	var mUser mongoUser
	err = r.collection.FindOne(ctx, bson.M{"username": username}).Decode(&mUser)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("failed to get user by username: %w", err)
	}

	return r.toDomain(&mUser), nil
}
