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

const chatSettingCollectionName = "chat_settings"

type mongoChatSetting struct {
	ID                primitive.ObjectID `bson:"_id,omitempty"`
	ChatID            string             `bson:"chat_id"`
	DisappearingTimer int                `bson:"disappearing_timer"` // Seconds
	MuteUntil         *int64             `bson:"mute_until"`
	SaveToCameraRoll  *int               `bson:"save_to_camera_roll"`
	AutoDownload      *int               `bson:"auto_download"`
	MediaQuality      *int               `bson:"media_quality"`
	UpdatedAt         time.Time          `bson:"updated_at"`
}

type ChatSettingRepository struct {
	collection *mongo.Collection
}

func NewChatSettingRepository(db *mongo.Database) domain.ChatSettingRepository {
	col := db.Collection(chatSettingCollectionName)

	// Create a unique index on chat_id
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	indexModel := mongo.IndexModel{
		Keys:    bson.D{{Key: "chat_id", Value: 1}},
		Options: options.Index().SetUnique(true),
	}
	_, _ = col.Indexes().CreateOne(ctx, indexModel)

	return &ChatSettingRepository{
		collection: col,
	}
}

func (r *ChatSettingRepository) toDomain(m *mongoChatSetting) *domain.ChatSetting {
	return &domain.ChatSetting{
		ID:                m.ID.Hex(),
		ChatID:            m.ChatID,
		DisappearingTimer: m.DisappearingTimer,
		MuteUntil:         m.MuteUntil,
		SaveToCameraRoll:  m.SaveToCameraRoll,
		AutoDownload:      m.AutoDownload,
		MediaQuality:      m.MediaQuality,
		UpdatedAt:         m.UpdatedAt,
	}
}

func (r *ChatSettingRepository) GetSetting(ctx context.Context, chatID string) (*domain.ChatSetting, error) {
	var m mongoChatSetting
	err := r.collection.FindOne(ctx, bson.M{"chat_id": chatID}).Decode(&m)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			// Return default setting if not found
			return &domain.ChatSetting{
				ChatID:            chatID,
				DisappearingTimer: 0,
				UpdatedAt:         time.Now(),
			}, nil
		}
		return nil, fmt.Errorf("failed to get chat setting: %w", err)
	}
	return r.toDomain(&m), nil
}

func (r *ChatSettingRepository) UpsertSetting(ctx context.Context, setting *domain.ChatSetting) error {
	filter := bson.M{"chat_id": setting.ChatID}
	update := bson.M{
		"$set": bson.M{
			"disappearing_timer":  setting.DisappearingTimer,
			"mute_until":          setting.MuteUntil,
			"save_to_camera_roll": setting.SaveToCameraRoll,
			"auto_download":       setting.AutoDownload,
			"media_quality":       setting.MediaQuality,
			"updated_at":          time.Now(),
		},
	}
	opts := options.Update().SetUpsert(true)

	_, err := r.collection.UpdateOne(ctx, filter, update, opts)
	if err != nil {
		return fmt.Errorf("failed to upsert chat setting: %w", err)
	}

	setting.UpdatedAt = time.Now()
	// Optionally fetch back the generated ID, but it's not strictly necessary for our use case right now.
	return nil
}
