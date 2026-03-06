package mongo_repo

import (
	"context"
	"time"

	"chatwmex_backend/internal/domain"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type mongoBlockRecord struct {
	ID        primitive.ObjectID `bson:"_id,omitempty"`
	BlockerID string             `bson:"blocker_id"`
	BlockedID string             `bson:"blocked_id"`
	CreatedAt time.Time          `bson:"created_at"`
}

func (r *FriendRepository) BlockUser(ctx context.Context, blockerID, blockedID string) error {
	// Remove friendship
	filter := bson.M{
		"status": domain.FriendRequestAccepted,
		"$or": []bson.M{
			{"sender_id": blockerID, "receiver_id": blockedID},
			{"sender_id": blockedID, "receiver_id": blockerID},
		},
	}
	_, err := r.collection.DeleteMany(ctx, filter)
	if err != nil {
		return err
	}

	// Insert block record
	blockRecord := mongoBlockRecord{
		BlockerID: blockerID,
		BlockedID: blockedID,
		CreatedAt: time.Now(),
	}

	// Use UpdateOne with upsert=true or InsertOne ignoring duplicates
	opts := options.Update().SetUpsert(true)
	update := bson.M{
		"$setOnInsert": blockRecord,
	}
	_, err = r.blockCollection.UpdateOne(
		ctx,
		bson.M{"blocker_id": blockerID, "blocked_id": blockedID},
		update,
		opts,
	)

	return err
}

func (r *FriendRepository) UnblockUser(ctx context.Context, blockerID, blockedID string) error {
	_, err := r.blockCollection.DeleteOne(ctx, bson.M{
		"blocker_id": blockerID,
		"blocked_id": blockedID,
	})
	return err
}

func (r *FriendRepository) IsBlocked(ctx context.Context, userA, userB string) (bool, error) {
	filter := bson.M{
		"$or": []bson.M{
			{"blocker_id": userA, "blocked_id": userB},
			{"blocker_id": userB, "blocked_id": userA},
		},
	}
	count, err := r.blockCollection.CountDocuments(ctx, filter)
	return count > 0, err
}

func (r *FriendRepository) GetBlockedUsers(ctx context.Context, userID string) ([]*domain.Friend, error) {
	cursor, err := r.blockCollection.Find(ctx, bson.M{"blocker_id": userID})
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var blockedIDs []primitive.ObjectID
	for cursor.Next(ctx) {
		var mBlock mongoBlockRecord
		if err := cursor.Decode(&mBlock); err != nil {
			continue
		}
		oid, _ := primitive.ObjectIDFromHex(mBlock.BlockedID)
		blockedIDs = append(blockedIDs, oid)
	}

	if len(blockedIDs) == 0 {
		return []*domain.Friend{}, nil
	}

	userCursor, err := r.userCollection.Find(ctx, bson.M{"_id": bson.M{"$in": blockedIDs}})
	if err != nil {
		return nil, err
	}
	defer userCursor.Close(ctx)

	var friends []*domain.Friend
	for userCursor.Next(ctx) {
		var u mongoUser
		if err := userCursor.Decode(&u); err != nil {
			continue
		}
		friends = append(friends, &domain.Friend{
			ID:       u.ID.Hex(),
			Username: u.Username,
			Email:    u.Email,
		})
	}

	return friends, nil
}
