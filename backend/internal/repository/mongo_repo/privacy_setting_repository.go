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

const privacySettingCollectionName = "privacy_settings"

type mongoPrivacySetting struct {
	ID                  primitive.ObjectID `bson:"_id,omitempty"`
	UserID              string             `bson:"user_id"`
	LastSeenPrivacy     int                `bson:"last_seen_privacy"`
	OnlineStatusPrivacy int                `bson:"online_status_privacy"`
	ProfilePhotoPrivacy int                `bson:"profile_photo_privacy"`
	ReadReceiptsEnabled bool               `bson:"read_receipts_enabled"`
	UpdatedAt           time.Time          `bson:"updated_at"`
}

// PrivacySettingRepository implements domain.UserPrivacyRepository for MongoDB.
type PrivacySettingRepository struct {
	collection *mongo.Collection
}

// NewPrivacySettingRepository creates a new PrivacySettingRepository and ensures
// a unique index on the user_id field exists.
func NewPrivacySettingRepository(db *mongo.Database) domain.UserPrivacyRepository {
	col := db.Collection(privacySettingCollectionName)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	indexModel := mongo.IndexModel{
		Keys:    bson.D{{Key: "user_id", Value: 1}},
		Options: options.Index().SetUnique(true),
	}
	_, _ = col.Indexes().CreateOne(ctx, indexModel)

	return &PrivacySettingRepository{
		collection: col,
	}
}

func (r *PrivacySettingRepository) toDomain(m *mongoPrivacySetting) *domain.PrivacySetting {
	return &domain.PrivacySetting{
		UserID:              m.UserID,
		LastSeenPrivacy:     domain.PrivacyLevel(m.LastSeenPrivacy),
		OnlineStatusPrivacy: domain.PrivacyLevel(m.OnlineStatusPrivacy),
		ProfilePhotoPrivacy: domain.PrivacyLevel(m.ProfilePhotoPrivacy),
		ReadReceiptsEnabled: m.ReadReceiptsEnabled,
	}
}

// GetPrivacySetting retrieves the privacy setting for a user.
// If no record exists, it returns the default values (all 0, read_receipts_enabled=true)
// without writing to the database (lazy default).
func (r *PrivacySettingRepository) GetPrivacySetting(ctx context.Context, userID string) (*domain.PrivacySetting, error) {
	var m mongoPrivacySetting
	err := r.collection.FindOne(ctx, bson.M{"user_id": userID}).Decode(&m)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			return &domain.PrivacySetting{
				UserID:              userID,
				LastSeenPrivacy:     domain.PrivacyLevelEveryone,
				OnlineStatusPrivacy: domain.PrivacyLevelEveryone,
				ProfilePhotoPrivacy: domain.PrivacyLevelEveryone,
				ReadReceiptsEnabled: true,
			}, nil
		}
		return nil, fmt.Errorf("failed to get privacy setting: %w", err)
	}
	return r.toDomain(&m), nil
}

// UpsertPrivacySetting inserts or updates the privacy setting for a user.
func (r *PrivacySettingRepository) UpsertPrivacySetting(ctx context.Context, setting *domain.PrivacySetting) error {
	filter := bson.M{"user_id": setting.UserID}
	update := bson.M{
		"$set": bson.M{
			"last_seen_privacy":     int(setting.LastSeenPrivacy),
			"online_status_privacy": int(setting.OnlineStatusPrivacy),
			"profile_photo_privacy": int(setting.ProfilePhotoPrivacy),
			"read_receipts_enabled": setting.ReadReceiptsEnabled,
			"updated_at":            time.Now(),
		},
	}
	opts := options.Update().SetUpsert(true)

	_, err := r.collection.UpdateOne(ctx, filter, update, opts)
	if err != nil {
		return fmt.Errorf("failed to upsert privacy setting: %w", err)
	}
	return nil
}
