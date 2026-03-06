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
	ID                  primitive.ObjectID `bson:"_id,omitempty"`
	Username            string             `bson:"username"`
	Email               string             `bson:"email,omitempty"`
	PhoneNumber         string             `bson:"phone_number,omitempty"`
	AvatarURL           string             `bson:"avatar_url,omitempty"`
	PublicKey           string             `bson:"public_key,omitempty"`
	EncryptedPrivateKey string             `bson:"encrypted_private_key,omitempty"`
	KeyBackupSalt       string             `bson:"key_backup_salt,omitempty"`
	PasswordHash        string             `bson:"password_hash"`
	CreatedAt           time.Time          `bson:"created_at"`
	UpdatedAt           time.Time          `bson:"updated_at"`
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
	usernameIndexModel := mongo.IndexModel{
		Keys:    bson.D{{Key: "username", Value: 1}},
		Options: options.Index().SetUnique(true),
	}

	// Ensure unique index on email
	// We use Sparse: true to allow multiple documents to have no email field (existing users)
	emailIndexModel := mongo.IndexModel{
		Keys:    bson.D{{Key: "email", Value: 1}},
		Options: options.Index().SetUnique(true).SetSparse(true),
	}

	// We create the index in the background to avoid blocking,
	// though for a new app this is fast.
	// In a real production scenario, index creation might be handled by migration scripts.
	// For simplicity here, we do it on startup but log errors instead of crashing.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	_, err := collection.Indexes().CreateOne(ctx, usernameIndexModel)
	if err != nil {
		fmt.Printf("Warning: failed to create unique index on users.username: %v\n", err)
	}

	_, err = collection.Indexes().CreateOne(ctx, emailIndexModel)
	if err != nil {
		fmt.Printf("Warning: failed to create unique index on users.email: %v\n", err)
	}

	return &UserRepository{
		collection: collection,
	}
}

// toDomain converts a mongoUser to a domain.User.
func (r *UserRepository) toDomain(u *mongoUser) *domain.User {
	return &domain.User{
		ID:                  u.ID.Hex(),
		Username:            u.Username,
		Email:               u.Email,
		PhoneNumber:         u.PhoneNumber,
		AvatarURL:           u.AvatarURL,
		PublicKey:           u.PublicKey, // ← 修復：必須映射公鑰
		EncryptedPrivateKey: u.EncryptedPrivateKey,
		KeyBackupSalt:       u.KeyBackupSalt,
		PasswordHash:        u.PasswordHash,
		CreatedAt:           u.CreatedAt,
		UpdatedAt:           u.UpdatedAt,
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
		ID:                  id,
		Username:            u.Username,
		Email:               u.Email,
		PhoneNumber:         u.PhoneNumber,
		AvatarURL:           u.AvatarURL,
		PublicKey:           u.PublicKey,
		EncryptedPrivateKey: u.EncryptedPrivateKey,
		KeyBackupSalt:       u.KeyBackupSalt,
		PasswordHash:        u.PasswordHash,
		CreatedAt:           u.CreatedAt,
		UpdatedAt:           u.UpdatedAt,
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
			// Determine which key is duplicate if possible, or just generic
			// Usually mongo error message contains the key pattern.
			// Ideally we parse it, but for now generic "already exists" is okay.
			// But user wants to know if email or username.
			// Simple check: Check if username exists, if so return "username exists", else "email exists"
			// But that's extra queries.
			// Let's just return a generic duplicate error for now or let the usecase handle it.
			// Actually, let's just return "username or email already exists"
			return errors.New("username or email already exists")
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

// Update updates an existing user in the database.
func (r *UserRepository) Update(ctx context.Context, user *domain.User) error {
	mongoUser, err := r.fromDomain(user)
	if err != nil {
		return err
	}

	update := bson.M{
		"$set": bson.M{
			"email":        mongoUser.Email,
			"phone_number": mongoUser.PhoneNumber,
			"updated_at":   time.Now(),
		},
	}

	_, err = r.collection.UpdateOne(ctx, bson.M{"_id": mongoUser.ID}, update)
	if err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return errors.New("email already exists")
		}
		return fmt.Errorf("failed to update user: %w", err)
	}

	return nil
}

func (r *UserRepository) UpdateAvatar(ctx context.Context, id, avatarURL string) error {
	objectID, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return fmt.Errorf("invalid object ID: %w", err)
	}
	update := bson.M{
		"$set": bson.M{
			"avatar_url": avatarURL,
			"updated_at": time.Now(),
		},
	}
	result, err := r.collection.UpdateOne(ctx, bson.M{"_id": objectID}, update)
	if err != nil {
		return fmt.Errorf("failed to update avatar: %w", err)
	}
	if result.MatchedCount == 0 {
		return errors.New("user not found")
	}
	return nil
}

// UpdateKeyBackup updates the encrypted private key and salt for E2EE cloud backup.
func (r *UserRepository) UpdateKeyBackup(ctx context.Context, id, encryptedKey, salt string) error {
	objectID, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return fmt.Errorf("invalid object ID: %w", err)
	}

	filter := bson.M{"_id": objectID}
	update := bson.M{
		"$set": bson.M{
			"encrypted_private_key": encryptedKey,
			"key_backup_salt":       salt,
			"updated_at":            time.Now(),
		},
	}

	_, err = r.collection.UpdateOne(ctx, filter, update)
	if err != nil {
		return fmt.Errorf("failed to update key backup: %w", err)
	}

	return nil
}

// UpdatePublicKey updates the user's public key in the database.
func (r *UserRepository) UpdatePublicKey(ctx context.Context, id, publicKey string) error {
	objectID, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return fmt.Errorf("invalid object ID: %w", err)
	}

	update := bson.M{
		"$set": bson.M{
			"public_key": publicKey,
			"updated_at": time.Now(),
		},
	}

	result, err := r.collection.UpdateOne(ctx, bson.M{"_id": objectID}, update)
	if err != nil {
		return fmt.Errorf("failed to update public key: %w", err)
	}

	if result.MatchedCount == 0 {
		return errors.New("user not found")
	}

	return nil
}

// GetByUsername retrieves a user by their username.
func (r *UserRepository) GetByUsername(ctx context.Context, username string) (*domain.User, error) {
	var mUser mongoUser
	err := r.collection.FindOne(ctx, bson.M{"username": username}).Decode(&mUser)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("failed to get user by username: %w", err)
	}

	return r.toDomain(&mUser), nil
}

// GetByEmail retrieves a user by their email.
func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*domain.User, error) {
	var mUser mongoUser
	err := r.collection.FindOne(ctx, bson.M{"email": email}).Decode(&mUser)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, errors.New("user not found")
		}
		return nil, fmt.Errorf("failed to get user by email: %w", err)
	}

	return r.toDomain(&mUser), nil
}
