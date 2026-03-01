package domain

import (
	"context"
	"time"
)

// User represents a user in the system.
type User struct {
	ID           string    `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"` // PasswordHash should not be exposed in JSON
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// UserRepository defines the interface for user data persistence.
type UserRepository interface {
	Create(ctx context.Context, user *User) error
	GetByID(ctx context.Context, id string) (*User, error)
	GetByUsername(ctx context.Context, username string) (*User, error)
}

// UserUsecase defines the interface for user business logic.
type UserUsecase interface {
	// Register creates a new user.
	Register(ctx context.Context, username, password string) error
	// Login validates credentials and returns the authentication token (or user).
	// Returning string (token) is common, but depending on implementation, it might return User.
	// We'll return the token string here as a common practice.
	Login(ctx context.Context, username, password string) (string, error)
	// GetUserProfile retrieves the user profile by ID.
	GetUserProfile(ctx context.Context, id string) (*User, error)
}
