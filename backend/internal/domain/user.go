package domain

import (
	"context"
	"time"
)

// User represents a user in the system.
type User struct {
	ID                  string    `json:"id"`
	Username            string    `json:"username"`
	Email               string    `json:"email"`
	PhoneNumber         string    `json:"phone_number"`
	FirstName           string    `json:"first_name,omitempty"`
	LastName            string    `json:"last_name,omitempty"`
	Bio                 string    `json:"bio,omitempty"`
	AvatarURL           string    `json:"avatar_url,omitempty"`
	PublicKey           string    `json:"public_key,omitempty"` // X25519 public key in Base64
	EncryptedPrivateKey string    `json:"encrypted_private_key,omitempty"`
	KeyBackupSalt       string    `json:"key_backup_salt,omitempty"`
	PasswordHash        string    `json:"-"` // PasswordHash should not be exposed in JSON
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
}

// UserRepository defines the interface for user data persistence.
type UserRepository interface {
	Create(ctx context.Context, user *User) error
	GetByID(ctx context.Context, id string) (*User, error)
	GetByUsername(ctx context.Context, username string) (*User, error)
	GetByEmail(ctx context.Context, email string) (*User, error)
	Update(ctx context.Context, user *User) error
	UpdateAvatar(ctx context.Context, id, avatarURL string) error
	UpdatePublicKey(ctx context.Context, id, publicKey string) error
	UpdateKeyBackup(ctx context.Context, id, encryptedKey, salt string) error
}

// UserUsecase defines the interface for user business logic.
type UserUsecase interface {
	// Register creates a new user.
	Register(ctx context.Context, username, email, password string) error
	// Login validates credentials and returns the authentication token (or user).
	// Returning string (token) is common, but depending on implementation, it might return User.
	// We'll return the token string here as a common practice.
	Login(ctx context.Context, usernameOrEmail, password string) (string, error)
	// GetUserProfile retrieves the user profile by ID.
	GetUserProfile(ctx context.Context, id string) (*User, error)
	// UpdateProfile updates the user's profile details.
	UpdateProfile(ctx context.Context, id, email, phoneNumber, firstName, lastName, bio string) error
	// UpdateAvatar updates the user's avatar URL.
	UpdateAvatar(ctx context.Context, id, avatarURL string) error
	// UpdatePublicKey updates the user's X25519 public key for E2EE.
	UpdatePublicKey(ctx context.Context, id, publicKey string) error
	// BackupE2EEKey updates the encrypted private key and salt for E2EE cloud backup.
	BackupE2EEKey(ctx context.Context, id, encryptedKey, salt string) error
	// GetE2EEKeyBackup retrieves the user's encrypted private key and salt.
	GetE2EEKeyBackup(ctx context.Context, id string) (*User, error)
}
