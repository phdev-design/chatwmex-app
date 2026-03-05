package usecase

import (
	"context"
	"errors"
	"regexp"
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
func (u *userUsecase) Register(c context.Context, username, email, password string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// 1. Check if user already exists
	// We should check both username and email.
	// Check Username
	existingUser, err := u.userRepo.GetByUsername(ctx, username)
	if existingUser != nil {
		return errors.New("username already exists")
	}
	if err != nil && err.Error() != "user not found" {
		return err
	}

	// Check Email
	existingEmail, err := u.userRepo.GetByEmail(ctx, email)
	if existingEmail != nil {
		return errors.New("email already exists")
	}
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
		Email:        email,
		PasswordHash: string(hashedPassword),
	}

	return u.userRepo.Create(ctx, user)
}

// Login validates credentials and returns the authentication token (or user ID for now).
// In a real application, this would return a JWT token.
func (u *userUsecase) Login(c context.Context, usernameOrEmail, password string) (string, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// 1. Get user by username or email
	// Determine if input is email or username
	var user *domain.User
	var err error

	// Simple check for '@'
	if isEmail(usernameOrEmail) {
		user, err = u.userRepo.GetByEmail(ctx, usernameOrEmail)
	} else {
		user, err = u.userRepo.GetByUsername(ctx, usernameOrEmail)
	}

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
	return user.ID, nil
}

// GetUserProfile retrieves the user profile by ID.
func (u *userUsecase) GetUserProfile(c context.Context, id string) (*domain.User, error) {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	user, err := u.userRepo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	return user, nil
}

// UpdateProfile updates the user's email and phone number.
func (u *userUsecase) UpdateProfile(c context.Context, id, email, phoneNumber string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	// 1. Validate Email
	if email != "" && !isEmail(email) {
		return errors.New("invalid email format")
	}

	// 2. Validate Phone Number (Basic check)
	if phoneNumber != "" && !isValidPhone(phoneNumber) {
		return errors.New("invalid phone number format")
	}

	// 3. Get User
	user, err := u.userRepo.GetByID(ctx, id)
	if err != nil {
		return err
	}

	// 4. Update Fields
	user.Email = email
	user.PhoneNumber = phoneNumber

	// 5. Save
	return u.userRepo.Update(ctx, user)
}

func (u *userUsecase) UpdateAvatar(c context.Context, id, avatarURL string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()
	if id == "" {
		return errors.New("user id is required")
	}
	if avatarURL == "" {
		return errors.New("avatar url is required")
	}
	return u.userRepo.UpdateAvatar(ctx, id, avatarURL)
}

func (u *userUsecase) UpdatePublicKey(c context.Context, id, publicKey string) error {
	ctx, cancel := context.WithTimeout(c, u.contextTimeout)
	defer cancel()

	if id == "" {
		return errors.New("user id is required")
	}
	if publicKey == "" {
		return errors.New("public key is required")
	}

	return u.userRepo.UpdatePublicKey(ctx, id, publicKey)
}

func isEmail(s string) bool {
	// Basic check
	for _, c := range s {
		if c == '@' {
			return true
		}
	}
	return false
}

func isValidPhone(s string) bool {
	// Basic check: 10-15 digits, optionally starting with +
	re := regexp.MustCompile(`^\+?[0-9]{10,15}$`)
	return re.MatchString(s)
}
