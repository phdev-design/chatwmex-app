package usecase

import (
	"context"
	"fmt"
	"testing"
	"time"

	"chatwmex_backend/internal/domain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// **Validates: Requirements 1.2**
// Property 1: Bug Condition - Link Preview Type Overwrite Crash
//
// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
// DO NOT attempt to fix the test or the code when it fails
//
// This test encodes the expected behavior - it will validate the fix when it passes after implementation
// GOAL: Surface counterexamples that demonstrate the bug exists
//
// Scoped PBT Approach: Scope to messages with Link Preview metadata
// Test that backend overwrites msg.Type to "link" when Link Preview detected, causing Flutter StateError in Message.fromJson()
// The test assertions verify msg.Type remains unchanged
//
// EXPECTED OUTCOME: Test FAILS (this is correct - it proves the bug exists)

// MockMessageRepository is a mock implementation of domain.MessageRepository
type MockMessageRepository struct {
	mock.Mock
}

func (m *MockMessageRepository) StoreMessage(ctx context.Context, msg *domain.Message) error {
	args := m.Called(ctx, msg)
	return args.Error(0)
}

func (m *MockMessageRepository) GetHistory(ctx context.Context, userID, contactID string, limit, offset int) ([]*domain.Message, error) {
	args := m.Called(ctx, userID, contactID, limit, offset)
	return args.Get(0).([]*domain.Message), args.Error(1)
}

func (m *MockMessageRepository) StoreOfflineMessage(ctx context.Context, userID string, msg *domain.Message) error {
	args := m.Called(ctx, userID, msg)
	return args.Error(0)
}

func (m *MockMessageRepository) GetOfflineMessages(ctx context.Context, userID string) ([]*domain.Message, error) {
	args := m.Called(ctx, userID)
	return args.Get(0).([]*domain.Message), args.Error(1)
}

func (m *MockMessageRepository) CountUnreadInRoom(ctx context.Context, roomID, userID string) (int, error) {
	args := m.Called(ctx, roomID, userID)
	return args.Int(0), args.Error(1)
}

func (m *MockMessageRepository) GetRoomLastReadAt(ctx context.Context, roomID, userID string) (time.Time, error) {
	args := m.Called(ctx, roomID, userID)
	return args.Get(0).(time.Time), args.Error(1)
}

func (m *MockMessageRepository) CountUnreadInRoomAfter(ctx context.Context, roomID, userID string, lastReadAt time.Time) (int, error) {
	args := m.Called(ctx, roomID, userID, lastReadAt)
	return args.Int(0), args.Error(1)
}

func (m *MockMessageRepository) MarkMessageAsReadBy(ctx context.Context, messageID string, userID string) error {
	args := m.Called(ctx, messageID, userID)
	return args.Error(0)
}

func (m *MockMessageRepository) GetRoomMessageMap(ctx context.Context, messageIDs []string) (map[string][]string, error) {
	args := m.Called(ctx, messageIDs)
	return args.Get(0).(map[string][]string), args.Error(1)
}

func (m *MockMessageRepository) GetRoomResources(ctx context.Context, userID, roomID, category, cursor string, limit int) ([]domain.Message, error) {
	args := m.Called(ctx, userID, roomID, category, cursor, limit)
	return args.Get(0).([]domain.Message), args.Error(1)
}

func (m *MockMessageRepository) ToggleReaction(ctx context.Context, messageID string, userID string, emoji string) (*domain.Message, error) {
	args := m.Called(ctx, messageID, userID, emoji)
	return args.Get(0).(*domain.Message), args.Error(1)
}

func (m *MockMessageRepository) UnsendMessage(ctx context.Context, messageID string, userID string) (*domain.Message, error) {
	args := m.Called(ctx, messageID, userID)
	return args.Get(0).(*domain.Message), args.Error(1)
}

func (m *MockMessageRepository) SoftDeleteMessage(ctx context.Context, messageID string, userID string) error {
	args := m.Called(ctx, messageID, userID)
	return args.Error(0)
}

func (m *MockMessageRepository) GetConversations(ctx context.Context, userID string) ([]*domain.Conversation, error) {
	args := m.Called(ctx, userID)
	return args.Get(0).([]*domain.Conversation), args.Error(1)
}

func (m *MockMessageRepository) GetLastRoomMessage(ctx context.Context, roomID string) (*domain.Message, error) {
	args := m.Called(ctx, roomID)
	return args.Get(0).(*domain.Message), args.Error(1)
}

func (m *MockMessageRepository) MarkAsRead(ctx context.Context, userID, conversationID string, isRoom bool) error {
	args := m.Called(ctx, userID, conversationID, isRoom)
	return args.Error(0)
}

func (m *MockMessageRepository) ClearRoomMessages(ctx context.Context, roomID, userID string) error {
	args := m.Called(ctx, roomID, userID)
	return args.Error(0)
}

func (m *MockMessageRepository) UpdateMessageStatus(ctx context.Context, messageID string, status string) error {
	args := m.Called(ctx, messageID, status)
	return args.Error(0)
}

func (m *MockMessageRepository) StoreDeliveredReceiptNotification(ctx context.Context, notification *domain.DeliveredReceiptNotification) error {
	args := m.Called(ctx, notification)
	return args.Error(0)
}

func (m *MockMessageRepository) FetchAndClearDeliveredReceiptNotifications(ctx context.Context, userID string) ([]*domain.DeliveredReceiptNotification, error) {
	args := m.Called(ctx, userID)
	return args.Get(0).([]*domain.DeliveredReceiptNotification), args.Error(1)
}

// MockOnlineRepository is a mock implementation for online status checking
type MockOnlineRepository struct {
	mock.Mock
}

func (m *MockOnlineRepository) SetUserOnline(ctx context.Context, userID string) error {
	args := m.Called(ctx, userID)
	return args.Error(0)
}

func (m *MockOnlineRepository) SetUserOffline(ctx context.Context, userID string) error {
	args := m.Called(ctx, userID)
	return args.Error(0)
}

func (m *MockOnlineRepository) IsUserOnline(ctx context.Context, userID string) (bool, error) {
	args := m.Called(ctx, userID)
	return args.Bool(0), args.Error(1)
}

func (m *MockOnlineRepository) GetOnlineUsers(ctx context.Context, userIDs []string) (map[string]bool, error) {
	args := m.Called(ctx, userIDs)
	return args.Get(0).(map[string]bool), args.Error(1)
}

// MockRoomRepository is a mock implementation for room operations
type MockRoomRepository struct {
	mock.Mock
}

func (m *MockRoomRepository) Create(ctx context.Context, room *domain.Room) error {
	args := m.Called(ctx, room)
	return args.Error(0)
}

func (m *MockRoomRepository) GetByID(ctx context.Context, id string) (*domain.Room, error) {
	args := m.Called(ctx, id)
	return args.Get(0).(*domain.Room), args.Error(1)
}

func (m *MockRoomRepository) AddMember(ctx context.Context, roomID string, userID string) error {
	args := m.Called(ctx, roomID, userID)
	return args.Error(0)
}

func (m *MockRoomRepository) RemoveMember(ctx context.Context, roomID string, userID string) error {
	args := m.Called(ctx, roomID, userID)
	return args.Error(0)
}

func (m *MockRoomRepository) DeleteRoom(ctx context.Context, roomID string) error {
	args := m.Called(ctx, roomID)
	return args.Error(0)
}

func (m *MockRoomRepository) GetMembers(ctx context.Context, roomID string) ([]string, error) {
	args := m.Called(ctx, roomID)
	return args.Get(0).([]string), args.Error(1)
}

func (m *MockRoomRepository) GetUserRooms(ctx context.Context, userID string) ([]*domain.Room, error) {
	args := m.Called(ctx, userID)
	return args.Get(0).([]*domain.Room), args.Error(1)
}

func (m *MockRoomRepository) UpdateRoom(ctx context.Context, roomID string, update map[string]interface{}) error {
	args := m.Called(ctx, roomID, update)
	return args.Error(0)
}

func (m *MockRoomRepository) UpdateOwner(ctx context.Context, roomID string, newOwnerID string) error {
	args := m.Called(ctx, roomID, newOwnerID)
	return args.Error(0)
}

// TestProperty_LinkPreviewTypePreservation tests the bug condition:
// Backend should NOT overwrite msg.Type to "link" when Link Preview is detected
//
// This is a scoped property-based test that generates messages with Link Preview metadata
func TestProperty_LinkPreviewTypePreservation(t *testing.T) {
	// Test cases representing different message types with Link Preview
	testCases := []struct {
		name             string
		originalType     string
		linkPreviewURL   string
		linkPreviewTitle string
		description      string
	}{
		{
			name:             "text_message_with_youtube_link",
			originalType:     "text",
			linkPreviewURL:   "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
			linkPreviewTitle: "Rick Astley - Never Gonna Give You Up",
			description:      "User sends text message with YouTube link",
		},
		{
			name:             "text_message_with_news_link",
			originalType:     "text",
			linkPreviewURL:   "https://www.example.com/news/article-123",
			linkPreviewTitle: "Breaking News: Important Update",
			description:      "User sends text message with news website link",
		},
		{
			name:             "text_message_with_github_link",
			originalType:     "text",
			linkPreviewURL:   "https://github.com/user/repo",
			linkPreviewTitle: "GitHub Repository",
			description:      "User sends text message with GitHub link",
		},
		{
			name:             "text_message_with_twitter_link",
			originalType:     "text",
			linkPreviewURL:   "https://twitter.com/user/status/123456",
			linkPreviewTitle: "Tweet from @user",
			description:      "User sends text message with Twitter link",
		},
		{
			name:             "text_message_with_blog_link",
			originalType:     "text",
			linkPreviewURL:   "https://blog.example.com/post/how-to-code",
			linkPreviewTitle: "How to Code: A Beginner's Guide",
			description:      "User sends text message with blog post link",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Setup mocks
			mockMessageRepo := new(MockMessageRepository)
			mockOnlineRepo := new(MockOnlineRepository)
			mockRoomRepo := new(MockRoomRepository)

			// Create usecase with mocks
			usecase := &messageUsecase{
				messageRepo:    mockMessageRepo,
				onlineRepo:     mockOnlineRepo,
				roomRepo:       mockRoomRepo,
				contextTimeout: 5 * time.Second,
			}

			// Create a message with Link Preview
			msg := &domain.Message{
				ID:         fmt.Sprintf("msg_%d", time.Now().UnixNano()),
				SenderID:   "user_sender",
				ReceiverID: "user_receiver",
				Content:    "Check out this link!",
				Type:       tc.originalType, // Original type set by frontend
				LinkPreview: &domain.LinkPreview{
					URL:         tc.linkPreviewURL,
					Title:       tc.linkPreviewTitle,
					Description: "Link preview description",
					ImageURL:    "https://example.com/image.jpg",
				},
			}

			t.Logf("Testing: %s", tc.description)
			t.Logf("Original Type: %s", tc.originalType)
			t.Logf("Link Preview URL: %s", tc.linkPreviewURL)

			// Setup mock expectations
			mockOnlineRepo.On("IsUserOnline", mock.Anything, "user_receiver").Return(true, nil)
			
			// Capture the message that gets stored to verify Type field
			var storedMessage *domain.Message
			mockMessageRepo.On("StoreMessage", mock.Anything, mock.AnythingOfType("*domain.Message")).
				Run(func(args mock.Arguments) {
					storedMessage = args.Get(1).(*domain.Message)
				}).
				Return(nil)

			// Execute SendMessage
			ctx := context.Background()
			err := usecase.SendMessage(ctx, msg)
			require.NoError(t, err, "SendMessage should not return error")

			// CRITICAL ASSERTION:
			// With unfixed code, msg.Type will be overwritten to "link"
			// This causes Flutter frontend to crash with StateError because "link" is not in MessageType enum
			//
			// After the fix, msg.Type should remain as the original type ("text")
			
			if msg.Type != tc.originalType {
				t.Logf("❌ COUNTEREXAMPLE FOUND: msg.Type was overwritten!")
				t.Logf("   Original Type: %s", tc.originalType)
				t.Logf("   Modified Type: %s", msg.Type)
				t.Logf("   Link Preview URL: %s", tc.linkPreviewURL)
				t.Logf("   This confirms the bug exists: Backend overwrites msg.Type to 'link'")
				t.Logf("   Flutter frontend will crash with StateError when parsing this message")
				
				t.Errorf("COUNTEREXAMPLE: Message type was overwritten from '%s' to '%s' when Link Preview detected",
					tc.originalType, msg.Type)
			} else {
				t.Logf("✅ msg.Type preserved as '%s' (expected behavior after fix)", tc.originalType)
			}

			// Verify the stored message also has the correct type
			assert.NotNil(t, storedMessage, "Message should be stored")
			if storedMessage != nil {
				if storedMessage.Type != tc.originalType {
					t.Errorf("COUNTEREXAMPLE: Stored message type is '%s', expected '%s'",
						storedMessage.Type, tc.originalType)
				}
			}

			// Verify Link Preview data is preserved
			assert.NotNil(t, msg.LinkPreview, "Link Preview should be preserved")
			if msg.LinkPreview != nil {
				assert.Equal(t, tc.linkPreviewURL, msg.LinkPreview.URL, 
					"Link Preview URL should be preserved")
				assert.Equal(t, tc.linkPreviewTitle, msg.LinkPreview.Title,
					"Link Preview Title should be preserved")
			}

			// Verify mocks were called
			mockOnlineRepo.AssertExpectations(t)
			mockMessageRepo.AssertExpectations(t)
		})
	}
}

// TestProperty_LinkPreviewTypePreservation_GroupMessages tests the bug condition for group messages
func TestProperty_LinkPreviewTypePreservation_GroupMessages(t *testing.T) {
	testCases := []struct {
		name             string
		originalType     string
		linkPreviewURL   string
		memberCount      int
		description      string
	}{
		{
			name:           "group_text_with_link_preview_5_members",
			originalType:   "text",
			linkPreviewURL: "https://www.youtube.com/watch?v=example",
			memberCount:    5,
			description:    "Group message with 5 members and link preview",
		},
		{
			name:           "group_text_with_link_preview_10_members",
			originalType:   "text",
			linkPreviewURL: "https://github.com/example/repo",
			memberCount:    10,
			description:    "Group message with 10 members and link preview",
		},
		{
			name:           "group_text_with_link_preview_20_members",
			originalType:   "text",
			linkPreviewURL: "https://news.example.com/article",
			memberCount:    20,
			description:    "Group message with 20 members and link preview",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Setup mocks
			mockMessageRepo := new(MockMessageRepository)
			mockOnlineRepo := new(MockOnlineRepository)
			mockRoomRepo := new(MockRoomRepository)

			// Create usecase with mocks
			usecase := &messageUsecase{
				messageRepo:    mockMessageRepo,
				onlineRepo:     mockOnlineRepo,
				roomRepo:       mockRoomRepo,
				contextTimeout: 5 * time.Second,
			}

			// Generate member IDs
			members := make([]string, tc.memberCount)
			for i := 0; i < tc.memberCount; i++ {
				members[i] = fmt.Sprintf("user_%d", i)
			}

			// Create a group message with Link Preview
			msg := &domain.Message{
				ID:       fmt.Sprintf("msg_%d", time.Now().UnixNano()),
				SenderID: members[0], // First member is sender
				RoomID:   "test_room_123",
				Content:  "Check out this link everyone!",
				Type:     tc.originalType, // Original type set by frontend
				LinkPreview: &domain.LinkPreview{
					URL:         tc.linkPreviewURL,
					Title:       "Shared Link",
					Description: "Link preview for group",
				},
			}

			t.Logf("Testing: %s", tc.description)
			t.Logf("Original Type: %s", tc.originalType)
			t.Logf("Members: %d", tc.memberCount)

			// Setup mock expectations
			mockRoomRepo.On("GetMembers", mock.Anything, "test_room_123").Return(members, nil)
			
			// Create online status map (all members online)
			onlineMap := make(map[string]bool)
			for _, memberID := range members {
				onlineMap[memberID] = true
			}
			mockOnlineRepo.On("GetOnlineUsers", mock.Anything, members).Return(onlineMap, nil)

			// Capture the stored message
			var storedMessage *domain.Message
			mockMessageRepo.On("StoreMessage", mock.Anything, mock.AnythingOfType("*domain.Message")).
				Run(func(args mock.Arguments) {
					storedMessage = args.Get(1).(*domain.Message)
				}).
				Return(nil)

			// Execute SendMessage
			ctx := context.Background()
			err := usecase.SendMessage(ctx, msg)
			require.NoError(t, err, "SendMessage should not return error")

			// CRITICAL ASSERTION: Type should be preserved
			if msg.Type != tc.originalType {
				t.Logf("❌ COUNTEREXAMPLE FOUND in group message!")
				t.Logf("   Original Type: %s", tc.originalType)
				t.Logf("   Modified Type: %s", msg.Type)
				t.Logf("   Group Members: %d", tc.memberCount)
				t.Logf("   This bug affects group messages with Link Preview")
				
				t.Errorf("COUNTEREXAMPLE: Group message type overwritten from '%s' to '%s'",
					tc.originalType, msg.Type)
			} else {
				t.Logf("✅ Group message type preserved as '%s'", tc.originalType)
			}

			// Verify stored message
			assert.NotNil(t, storedMessage, "Message should be stored")
			if storedMessage != nil {
				assert.Equal(t, tc.originalType, storedMessage.Type,
					"Stored message type should match original")
			}

			// Verify mocks
			mockRoomRepo.AssertExpectations(t)
			mockOnlineRepo.AssertExpectations(t)
			mockMessageRepo.AssertExpectations(t)
		})
	}
}

// TestProperty_MessageWithoutLinkPreview tests that messages without Link Preview are unaffected
// This serves as a control test to ensure the bug is specific to Link Preview
func TestProperty_MessageWithoutLinkPreview(t *testing.T) {
	testCases := []struct {
		name         string
		messageType  string
		hasLinkPreview bool
	}{
		{
			name:         "text_message_no_link",
			messageType:  "text",
			hasLinkPreview: false,
		},
		{
			name:         "image_message",
			messageType:  "image",
			hasLinkPreview: false,
		},
		{
			name:         "file_message",
			messageType:  "file",
			hasLinkPreview: false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			mockMessageRepo := new(MockMessageRepository)
			mockOnlineRepo := new(MockOnlineRepository)
			mockRoomRepo := new(MockRoomRepository)

			usecase := &messageUsecase{
				messageRepo:    mockMessageRepo,
				onlineRepo:     mockOnlineRepo,
				roomRepo:       mockRoomRepo,
				contextTimeout: 5 * time.Second,
			}

			msg := &domain.Message{
				ID:         fmt.Sprintf("msg_%d", time.Now().UnixNano()),
				SenderID:   "user_sender",
				ReceiverID: "user_receiver",
				Content:    "Regular message without link",
				Type:       tc.messageType,
				LinkPreview: nil, // No Link Preview
			}

			originalType := msg.Type

			mockOnlineRepo.On("IsUserOnline", mock.Anything, "user_receiver").Return(true, nil)
			mockMessageRepo.On("StoreMessage", mock.Anything, mock.AnythingOfType("*domain.Message")).Return(nil)

			ctx := context.Background()
			err := usecase.SendMessage(ctx, msg)
			require.NoError(t, err)

			// Type should remain unchanged for messages without Link Preview
			assert.Equal(t, originalType, msg.Type,
				"Message type should not change when no Link Preview is present")

			t.Logf("✅ Message without Link Preview: Type '%s' preserved correctly", msg.Type)
		})
	}
}
