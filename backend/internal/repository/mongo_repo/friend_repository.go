package mongo_repo

import (
	"context"
	"errors"
	"time"

	"chatwmex_backend/internal/domain"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

const friendRequestCollectionName = "friend_requests"

type mongoFriendRequest struct {
	ID         primitive.ObjectID         `bson:"_id,omitempty"`
	SenderID   string                     `bson:"sender_id"`
	ReceiverID string                     `bson:"receiver_id"`
	Status     domain.FriendRequestStatus `bson:"status"`
	CreatedAt  time.Time                  `bson:"created_at"`
	UpdatedAt  time.Time                  `bson:"updated_at"`
}

type FriendRepository struct {
	collection     *mongo.Collection
	userCollection *mongo.Collection
}

func NewFriendRepository(db *mongo.Database) domain.FriendRepository {
	collection := db.Collection(friendRequestCollectionName)
	userCollection := db.Collection(userCollectionName)

	// Unique index to prevent duplicate requests between same pair
	// We need a compound index on SenderID and ReceiverID
	// But since A->B and B->A are effectively the same "relationship" potential,
	// we might want to check existence manually or just rely on application logic.
	// Simple unique index on sender+receiver.
	model := mongo.IndexModel{
		Keys:    bson.D{{Key: "sender_id", Value: 1}, {Key: "receiver_id", Value: 1}},
		Options: options.Index().SetUnique(true),
	}
	
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	collection.Indexes().CreateOne(ctx, model)

	return &FriendRepository{
		collection:     collection,
		userCollection: userCollection,
	}
}

func (r *FriendRepository) toDomain(m *mongoFriendRequest) *domain.FriendRequest {
	return &domain.FriendRequest{
		ID:         m.ID.Hex(),
		SenderID:   m.SenderID,
		ReceiverID: m.ReceiverID,
		Status:     m.Status,
		CreatedAt:  m.CreatedAt,
		UpdatedAt:  m.UpdatedAt,
	}
}

func (r *FriendRepository) CreateRequest(ctx context.Context, req *domain.FriendRequest) error {
	mReq := &mongoFriendRequest{
		SenderID:   req.SenderID,
		ReceiverID: req.ReceiverID,
		Status:     domain.FriendRequestPending,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}

	res, err := r.collection.InsertOne(ctx, mReq)
	if err != nil {
		if mongo.IsDuplicateKeyError(err) {
			return errors.New("request already exists")
		}
		return err
	}

	req.ID = res.InsertedID.(primitive.ObjectID).Hex()
	req.Status = mReq.Status
	req.CreatedAt = mReq.CreatedAt
	req.UpdatedAt = mReq.UpdatedAt
	return nil
}

func (r *FriendRepository) GetRequestByID(ctx context.Context, id string) (*domain.FriendRequest, error) {
	oid, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return nil, errors.New("invalid id")
	}

	var mReq mongoFriendRequest
	err = r.collection.FindOne(ctx, bson.M{"_id": oid}).Decode(&mReq)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			return nil, errors.New("request not found")
		}
		return nil, err
	}

	return r.toDomain(&mReq), nil
}

func (r *FriendRepository) GetRequestsByReceiverID(ctx context.Context, receiverID string) ([]*domain.FriendRequest, error) {
	cursor, err := r.collection.Find(ctx, bson.M{"receiver_id": receiverID, "status": domain.FriendRequestPending})
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var requests []*domain.FriendRequest
	for cursor.Next(ctx) {
		var mReq mongoFriendRequest
		if err := cursor.Decode(&mReq); err != nil {
			continue
		}
		
		req := r.toDomain(&mReq)
		
		// Fetch sender username
		senderOID, err := primitive.ObjectIDFromHex(mReq.SenderID)
		if err == nil {
			var mUser mongoUser
			if err := r.userCollection.FindOne(ctx, bson.M{"_id": senderOID}).Decode(&mUser); err == nil {
				req.SenderUsername = mUser.Username
			}
		}
		
		requests = append(requests, req)
	}
	return requests, nil
}

func (r *FriendRepository) GetRequestsBySenderID(ctx context.Context, senderID string) ([]*domain.FriendRequest, error) {
	cursor, err := r.collection.Find(ctx, bson.M{"sender_id": senderID})
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var requests []*domain.FriendRequest
	for cursor.Next(ctx) {
		var mReq mongoFriendRequest
		if err := cursor.Decode(&mReq); err != nil {
			continue
		}
		requests = append(requests, r.toDomain(&mReq))
	}
	return requests, nil
}

func (r *FriendRepository) UpdateRequestStatus(ctx context.Context, id string, status domain.FriendRequestStatus) error {
	oid, err := primitive.ObjectIDFromHex(id)
	if err != nil {
		return errors.New("invalid id")
	}

	update := bson.M{
		"$set": bson.M{
			"status":     status,
			"updated_at": time.Now(),
		},
	}

	_, err = r.collection.UpdateOne(ctx, bson.M{"_id": oid}, update)
	return err
}

func (r *FriendRepository) AddFriend(ctx context.Context, userID, friendID string) error {
	// Not needed if we rely on request status 'accepted'
	// But if we want a separate friends collection, we implement it here.
	// For now, let's assume 'accepted' status in friend_requests implies friendship.
	return nil
}

func (r *FriendRepository) GetFriends(ctx context.Context, userID string) ([]*domain.Friend, error) {
	// Find all accepted requests where user is sender OR receiver
	filter := bson.M{
		"status": domain.FriendRequestAccepted,
		"$or": []bson.M{
			{"sender_id": userID},
			{"receiver_id": userID},
		},
	}

	cursor, err := r.collection.Find(ctx, filter)
	if err != nil {
		return nil, err
	}
	defer cursor.Close(ctx)

	var friendIDs []primitive.ObjectID
	for cursor.Next(ctx) {
		var mReq mongoFriendRequest
		if err := cursor.Decode(&mReq); err != nil {
			continue
		}
		
		var fid string
		if mReq.SenderID == userID {
			fid = mReq.ReceiverID
		} else {
			fid = mReq.SenderID
		}
		
		oid, _ := primitive.ObjectIDFromHex(fid)
		friendIDs = append(friendIDs, oid)
	}

	if len(friendIDs) == 0 {
		return []*domain.Friend{}, nil
	}

	// Fetch user details
	userCursor, err := r.userCollection.Find(ctx, bson.M{"_id": bson.M{"$in": friendIDs}})
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

func (r *FriendRepository) IsFriend(ctx context.Context, userID, friendID string) (bool, error) {
	filter := bson.M{
		"status": domain.FriendRequestAccepted,
		"$or": []bson.M{
			{"sender_id": userID, "receiver_id": friendID},
			{"sender_id": friendID, "receiver_id": userID},
		},
	}
	count, err := r.collection.CountDocuments(ctx, filter)
	return count > 0, err
}
