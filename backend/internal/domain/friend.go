package domain

import (
	"context"
	"time"
)

type FriendRequestStatus string

const (
	FriendRequestPending  FriendRequestStatus = "pending"
	FriendRequestAccepted FriendRequestStatus = "accepted"
	FriendRequestRejected FriendRequestStatus = "rejected"
)

type FriendRequest struct {
	ID             string              `json:"id"`
	SenderID       string              `json:"sender_id"`
	SenderUsername string              `json:"sender_username,omitempty"` // Populated for responses
	ReceiverID     string              `json:"receiver_id"`
	Status         FriendRequestStatus `json:"status"`
	CreatedAt      time.Time           `json:"created_at"`
	UpdatedAt      time.Time           `json:"updated_at"`
}

type Friend struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Email    string `json:"email"`
}

type FriendRepository interface {
	CreateRequest(ctx context.Context, req *FriendRequest) error
	GetRequestByID(ctx context.Context, id string) (*FriendRequest, error)
	GetRequestsByReceiverID(ctx context.Context, receiverID string) ([]*FriendRequest, error)
	GetRequestsBySenderID(ctx context.Context, senderID string) ([]*FriendRequest, error)
	UpdateRequestStatus(ctx context.Context, id string, status FriendRequestStatus) error
	AddFriend(ctx context.Context, userID, friendID string) error
	GetFriends(ctx context.Context, userID string) ([]*Friend, error)
	IsFriend(ctx context.Context, userID, friendID string) (bool, error)
	RemoveFriend(ctx context.Context, userID, friendID string) error
}

type FriendUsecase interface {
	SendFriendRequest(ctx context.Context, senderID, receiverUsernameOrEmail string) error
	AcceptFriendRequest(ctx context.Context, requestID string) error
	RejectFriendRequest(ctx context.Context, requestID string) error
	GetPendingRequests(ctx context.Context, userID string) ([]*FriendRequest, error)
	GetFriends(ctx context.Context, userID string) ([]*Friend, error)
	UnfriendUser(ctx context.Context, currentUserID, targetUserID string) error
}
