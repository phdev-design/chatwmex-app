package usecase

import (
	"context"
	"errors"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"golang.org/x/crypto/bcrypt"
)

// MockUserRepository is a mock implementation of domain.UserRepository
type MockUserRepository struct {
	mock.Mock
}

func (m *MockUserRepository) Create(ctx context.Context, user *domain.User) error {
	args := m.Called(ctx, user)
	return args.Error(0)
}

func (m *MockUserRepository) GetByID(ctx context.Context, id string) (*domain.User, error) {
	args := m.Called(ctx, id)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*domain.User), args.Error(1)
}

func (m *MockUserRepository) GetByUsername(ctx context.Context, username string) (*domain.User, error) {
	args := m.Called(ctx, username)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*domain.User), args.Error(1)
}

func (m *MockUserRepository) GetByEmail(ctx context.Context, email string) (*domain.User, error) {
	args := m.Called(ctx, email)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*domain.User), args.Error(1)
}

func (m *MockUserRepository) Update(ctx context.Context, user *domain.User) error {
	args := m.Called(ctx, user)
	return args.Error(0)
}

func (m *MockUserRepository) UpdateAvatar(ctx context.Context, id, avatarURL string) error {
	args := m.Called(ctx, id, avatarURL)
	return args.Error(0)
}

func (m *MockUserRepository) UpdatePublicKey(ctx context.Context, id, publicKey string) error {
	args := m.Called(ctx, id, publicKey)
	return args.Error(0)
}

// UpdateKeyBackup mocks the UpdateKeyBackup method.
func (m *MockUserRepository) UpdateKeyBackup(ctx context.Context, id, encryptedKey, salt string) error {
	args := m.Called(ctx, id, encryptedKey, salt)
	return args.Error(0)
}

func TestRegister(t *testing.T) {
	mockRepo := new(MockUserRepository)
	usecase := NewUserUsecase(mockRepo, time.Second)
	ctx := context.Background()

	t.Run("Success", func(t *testing.T) {
		mockRepo.On("GetByUsername", mock.Anything, "testuser").Return(nil, errors.New("user not found"))
		mockRepo.On("GetByEmail", mock.Anything, "test@example.com").Return(nil, errors.New("user not found"))
		mockRepo.On("Create", mock.Anything, mock.MatchedBy(func(u *domain.User) bool {
			return u.Username == "testuser" && u.Email == "test@example.com"
		})).Return(nil)

		err := usecase.Register(ctx, "testuser", "test@example.com", "password")
		assert.NoError(t, err)
		mockRepo.AssertExpectations(t)
	})

	t.Run("UsernameExists", func(t *testing.T) {
		// Clear previous expectations or use new mock
		mockRepo := new(MockUserRepository)
		usecase := NewUserUsecase(mockRepo, time.Second)

		existingUser := &domain.User{Username: "testuser"}
		mockRepo.On("GetByUsername", mock.Anything, "testuser").Return(existingUser, nil)

		err := usecase.Register(ctx, "testuser", "test@example.com", "password")
		assert.Error(t, err)
		assert.Equal(t, "username already exists", err.Error())
	})

	t.Run("EmailExists", func(t *testing.T) {
		mockRepo := new(MockUserRepository)
		usecase := NewUserUsecase(mockRepo, time.Second)

		mockRepo.On("GetByUsername", mock.Anything, "testuser").Return(nil, errors.New("user not found"))
		existingUser := &domain.User{Email: "test@example.com"}
		mockRepo.On("GetByEmail", mock.Anything, "test@example.com").Return(existingUser, nil)

		err := usecase.Register(ctx, "testuser", "test@example.com", "password")
		assert.Error(t, err)
		assert.Equal(t, "email already exists", err.Error())
	})
}

func TestLogin(t *testing.T) {
	mockRepo := new(MockUserRepository)
	usecase := NewUserUsecase(mockRepo, time.Second)
	ctx := context.Background()

	hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("password"), bcrypt.DefaultCost)
	user := &domain.User{
		ID:           "123",
		Username:     "testuser",
		Email:        "test@example.com",
		PasswordHash: string(hashedPassword),
	}

	t.Run("SuccessWithUsername", func(t *testing.T) {
		mockRepo.On("GetByUsername", mock.Anything, "testuser").Return(user, nil)

		token, err := usecase.Login(ctx, "testuser", "password")
		assert.NoError(t, err)
		assert.Equal(t, "123", token)
	})

	t.Run("SuccessWithEmail", func(t *testing.T) {
		mockRepo.On("GetByEmail", mock.Anything, "test@example.com").Return(user, nil)

		token, err := usecase.Login(ctx, "test@example.com", "password")
		assert.NoError(t, err)
		assert.Equal(t, "123", token)
	})

	t.Run("InvalidCredentials", func(t *testing.T) {
		mockRepo.On("GetByUsername", mock.Anything, "testuser").Return(user, nil)

		_, err := usecase.Login(ctx, "testuser", "wrongpassword")
		assert.Error(t, err)
		assert.Equal(t, "invalid credentials", err.Error())
	})

	t.Run("UserNotFound", func(t *testing.T) {
		mockRepo := new(MockUserRepository)
		usecase := NewUserUsecase(mockRepo, time.Second)

		mockRepo.On("GetByUsername", mock.Anything, "nonexistent").Return(nil, errors.New("user not found"))

		_, err := usecase.Login(ctx, "nonexistent", "password")
		assert.Error(t, err)
		assert.Equal(t, "invalid credentials", err.Error())
	})
}
