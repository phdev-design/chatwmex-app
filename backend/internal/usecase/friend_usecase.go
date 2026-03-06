package usecase

import (
	"context"
	"errors"
	"time"

	"chatwmex_backend/internal/domain"
)

type friendUsecase struct {
	friendRepo     domain.FriendRepository
	userRepo       domain.UserRepository
	notification   domain.NotificationService
	contextTimeout time.Duration
}

func NewFriendUsecase(friendRepo domain.FriendRepository, userRepo domain.UserRepository, notification domain.NotificationService, timeout time.Duration) domain.FriendUsecase {
	return &friendUsecase{
		friendRepo:     friendRepo,
		userRepo:       userRepo,
		notification:   notification,
		contextTimeout: timeout,
	}
}

func (u *friendUsecase) SendFriendRequest(c context.Context, senderID, receiverUsernameOrEmail string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// Find receiver
	var receiver *domain.User
	var err error

	// Basic check if email
	isEmail := false
	for _, char := range receiverUsernameOrEmail {
		if char == '@' {
			isEmail = true
			break
		}
	}

	if isEmail {
		receiver, err = u.userRepo.GetByEmail(ctx, receiverUsernameOrEmail)
	} else {
		receiver, err = u.userRepo.GetByUsername(ctx, receiverUsernameOrEmail)
	}

	if err != nil {
		return errors.New("user not found")
	}

	if receiver.ID == senderID {
		return errors.New("cannot add yourself")
	}

	// Check if already friends or request exists
	isFriend, err := u.friendRepo.IsFriend(ctx, senderID, receiver.ID)
	if err != nil {
		return err
	}
	if isFriend {
		return errors.New("already friends")
	}

	// Create Request
	req := &domain.FriendRequest{
		SenderID:   senderID,
		ReceiverID: receiver.ID,
	}

	if err := u.friendRepo.CreateRequest(ctx, req); err != nil {
		return err
	}

	// Send Notification
	if u.notification != nil {
		// Fetch sender info for notification
		sender, _ := u.userRepo.GetByID(ctx, senderID)
		if sender != nil {
			req.SenderUsername = sender.Username
		}
		u.notification.SendNotification(receiver.ID, "friend_request", req)
	}

	return nil
}

func (u *friendUsecase) AcceptFriendRequest(c context.Context, requestID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// Fetch request to get SenderID
	req, err := u.friendRepo.GetRequestByID(ctx, requestID)
	if err != nil {
		return err
	}

	if err := u.friendRepo.UpdateRequestStatus(ctx, requestID, domain.FriendRequestAccepted); err != nil {
		return err
	}

	// Send Notification to the sender of the request
	if u.notification != nil {
		// Fetch receiver info (who accepted)
		// Wait, AcceptFriendRequest is called by Receiver.
		// We don't have ReceiverID in context here easily without passing it.
		// But req has ReceiverID.
		// We want to notify req.SenderID that req.ReceiverID accepted.

		// Ideally we send the updated request or a "friend_accepted" event with friend info.
		// Let's send the request object with status Accepted.
		req.Status = domain.FriendRequestAccepted
		u.notification.SendNotification(req.SenderID, "friend_accepted", req)
	}

	return nil
}

func (u *friendUsecase) RejectFriendRequest(c context.Context, requestID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.friendRepo.UpdateRequestStatus(ctx, requestID, domain.FriendRequestRejected)
}

func (u *friendUsecase) GetPendingRequests(c context.Context, userID string) ([]*domain.FriendRequest, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.friendRepo.GetRequestsByReceiverID(ctx, userID)
}

func (u *friendUsecase) GetFriends(c context.Context, userID string) ([]*domain.Friend, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.friendRepo.GetFriends(ctx, userID)
}

func (u *friendUsecase) UnfriendUser(c context.Context, currentUserID, targetUserID string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	isFriend, err := u.friendRepo.IsFriend(ctx, currentUserID, targetUserID)
	if err != nil {
		return err
	}
	if !isFriend {
		return errors.New("not friends")
	}
	return u.friendRepo.RemoveFriend(ctx, currentUserID, targetUserID)
}
