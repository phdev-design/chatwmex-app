package usecase

import (
	"context"
	"errors"
	"time"

	"chatwmex_backend/internal/domain"

	"golang.org/x/crypto/bcrypt"
)

type userUsecase struct {
	userRepo       domain.UserRepository
	contextTimeout time.Duration
}

// NewUserUsecase creates a new instance of UserUsecase.
func NewUserUsecase(userRepo domain.UserRepository, timeout time.Duration) domain.UserUsecase {
	return &userUsecase{
		userRepo:       userRepo,
		contextTimeout: timeout,
	}
}

// Register creates a new user.
func (u *userUsecase) Register(c context.Context, username, password string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// 1. Check if user already exists
	existingUser, err := u.userRepo.GetByUsername(ctx, username)
	if existingUser != nil {
		return errors.New("username already exists")
	}
	// If error is not "user not found", it's a real database error
	if err != nil && err.Error() != "user not found" {
		return err
	}

	// 2. Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	// 3. Create user
	user := &domain.User{
		Username:     username,
		PasswordHash: string(hashedPassword),
	}

	return u.userRepo.Create(ctx, user)
}

// Login validates credentials and returns the authentication token (or user ID for now).
// In a real application, this would return a JWT token.
func (u *userUsecase) Login(c context.Context, username, password string) (string, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// 1. Get user by username
	user, err := u.userRepo.GetByUsername(ctx, username)
	if err != nil {
		// Avoid leaking whether the user exists or not
		if err.Error() == "user not found" {
			return "", errors.New("invalid credentials")
		}
		return "", err
	}

	// 2. Compare password
	err = bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password))
	if err != nil {
		return "", errors.New("invalid credentials")
	}

	// 3. Generate token (Placeholder for now)
	// TODO: Implement JWT generation
	return "mock-jwt-token-for-" + user.ID, nil
}

// GetUserProfile retrieves the user profile by ID.
func (u *userUsecase) GetUserProfile(c context.Context, id string) (*domain.User, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	return u.userRepo.GetByID(ctx, id)
}
