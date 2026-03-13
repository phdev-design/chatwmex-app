package usecase

import (
	"context"
	"fmt"
	"testing"
	"testing/quick"
	"time"

	"chatwmex_backend/internal/domain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// **Validates: Requirements 3.2**
// Property 8: Preservation - Non-Link-Preview Message Type Handling
//
// IMPORTANT: This is a PRESERVATION test - it runs on UNFIXED code
// EXPECTED OUTCOME: Test PASSES (confirms baseline behavior to preserve)
//
// This test verifies that messages WITHOUT Link Preview continue to be processed
// normally by the backend, ensuring the fix doesn't break existing functionality.
//
// Property: For any message without Link Preview, backend SHALL continue to
// process message types normally (Type field remains unchanged)

// TestPreservation_NonLinkPreviewMessageTypeHandling tests that messages without
// Link Preview are processed correctly and their Type field is preserved.
//
// This is a property-based test that generates various message types without Link Preview
// to ensure the backend continues to handle them correctly after the fix is implemented.
func TestPreservation_NonLinkPreviewMessageTypeHandling(t *testing.T) {
	// Test cases covering all valid message types without Link Preview
	testCases := []struct {
		name         string
		messageType  string
		content      string
		description  string
	}{
		{
			name:        "text_message_plain",
			messageType: "text",
			content:     "Hello, this is a plain text message",
			description: "Plain text message without any links",
		},
		{
			name:        "text_message_long",
			messageType: "text",
			content:     "This is a longer text message that contains multiple sentences. It should be processed normally without any Link Preview data. The backend should preserve the message type as 'text'.",
			description: "Long text message without Link Preview",
		},
		{
			name:        "image_message",
			messageType: "image",
			content:     "encrypted_image_data_base64...",
			description: "Image message (encrypted)",
		},
		{
			name:        "file_message",
			messageType: "file",
			content:     "encrypted_file_data_base64...",
			description: "File message (encrypted)",
		},
		{
			name:        "audio_message",
			messageType: "audio",
			content:     "encrypted_audio_data_base64...",
			description: "Audio message (encrypted)",
		},
		{
			name:        "video_message",
			messageType: "video",
			content:     "encrypted_video_data_base64...",
			description: "Video message (encrypted)",
		},
		{
			name:        "location_message",
			messageType: "location",
			content:     "encrypted_location_data...",
			description: "Location message (encrypted)",
		},
		{
			name:        "contact_message",
			messageType: "contact",
			content:     "encrypted_contact_data...",
			description: "Contact message (encrypted)",
		},
		{
			name:        "text_with_emoji",
			messageType: "text",
			content:     "Hello! 👋 How are you? 😊",
			description: "Text message with emoji",
		},
		{
			name:        "text_with_numbers",
			messageType: "text",
			content:     "Meeting at 3:30 PM, room 123",
			description: "Text message with numbers",
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

			// Create a message WITHOUT Link Preview
			msg := &domain.Message{
				ID:          fmt.Sprintf("msg_%d", time.Now().UnixNano()),
				SenderID:    "user_sender",
				ReceiverID:  "user_receiver",
				Content:     tc.content,
				Type:        tc.messageType,
				LinkPreview: nil, // CRITICAL: No Link Preview
			}

			originalType := msg.Type

			t.Logf("Testing: %s", tc.description)
			t.Logf("Message Type: %s", tc.messageType)
			t.Logf("Has Link Preview: false")

			// Setup mock expectations
			mockOnlineRepo.On("IsUserOnline", mock.Anything, "user_receiver").Return(true, nil)

			// Capture the message that gets stored
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

			// PRESERVATION ASSERTION:
			// Messages without Link Preview should have their Type preserved
			// This behavior MUST remain unchanged after the fix
			assert.Equal(t, originalType, msg.Type,
				"Message type should be preserved for messages without Link Preview")

			// Verify the stored message also has the correct type
			assert.NotNil(t, storedMessage, "Message should be stored")
			if storedMessage != nil {
				assert.Equal(t, originalType, storedMessage.Type,
					"Stored message type should match original for non-Link-Preview messages")
			}

			// Verify Link Preview remains nil
			assert.Nil(t, msg.LinkPreview,
				"Link Preview should remain nil for messages without Link Preview")

			t.Logf("✅ PRESERVATION VERIFIED: Type '%s' preserved correctly (no Link Preview)", msg.Type)

			// Verify mocks were called
			mockOnlineRepo.AssertExpectations(t)
			mockMessageRepo.AssertExpectations(t)
		})
	}
}

// TestPreservation_NonLinkPreviewGroupMessages tests preservation for group messages
// without Link Preview to ensure they continue to work correctly.
func TestPreservation_NonLinkPreviewGroupMessages(t *testing.T) {
	testCases := []struct {
		name        string
		messageType string
		memberCount int
		content     string
		description string
	}{
		{
			name:        "group_text_5_members",
			messageType: "text",
			memberCount: 5,
			content:     "Team meeting at 2 PM",
			description: "Group text message with 5 members, no Link Preview",
		},
		{
			name:        "group_text_10_members",
			messageType: "text",
			memberCount: 10,
			content:     "Project update: All tasks completed",
			description: "Group text message with 10 members, no Link Preview",
		},
		{
			name:        "group_image_5_members",
			messageType: "image",
			memberCount: 5,
			content:     "encrypted_image_data...",
			description: "Group image message with 5 members",
		},
		{
			name:        "group_file_20_members",
			messageType: "file",
			memberCount: 20,
			content:     "encrypted_file_data...",
			description: "Group file message with 20 members",
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

			// Create a group message WITHOUT Link Preview
			msg := &domain.Message{
				ID:          fmt.Sprintf("msg_%d", time.Now().UnixNano()),
				SenderID:    members[0], // First member is sender
				RoomID:      "test_room_123",
				Content:     tc.content,
				Type:        tc.messageType,
				LinkPreview: nil, // CRITICAL: No Link Preview
			}

			originalType := msg.Type

			t.Logf("Testing: %s", tc.description)
			t.Logf("Message Type: %s", tc.messageType)
			t.Logf("Members: %d", tc.memberCount)
			t.Logf("Has Link Preview: false")

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

			// PRESERVATION ASSERTION:
			// Group messages without Link Preview should have their Type preserved
			assert.Equal(t, originalType, msg.Type,
				"Group message type should be preserved when no Link Preview is present")

			// Verify stored message
			assert.NotNil(t, storedMessage, "Message should be stored")
			if storedMessage != nil {
				assert.Equal(t, originalType, storedMessage.Type,
					"Stored group message type should match original")
			}

			// Verify Link Preview remains nil
			assert.Nil(t, msg.LinkPreview,
				"Link Preview should remain nil for group messages without Link Preview")

			t.Logf("✅ PRESERVATION VERIFIED: Group message type '%s' preserved correctly", msg.Type)

			// Verify mocks
			mockRoomRepo.AssertExpectations(t)
			mockOnlineRepo.AssertExpectations(t)
			mockMessageRepo.AssertExpectations(t)
		})
	}
}

// TestPreservation_MessageTypeProperty uses property-based testing with quick.Check
// to generate random message types and verify preservation behavior.
//
// This provides stronger guarantees by testing many random combinations.
func TestPreservation_MessageTypeProperty(t *testing.T) {
	// Valid message types that should be preserved
	validTypes := []string{"text", "image", "file", "audio", "video", "location", "contact"}

	// Property: For any valid message type without Link Preview,
	// the backend preserves the Type field unchanged
	property := func(typeIndex uint8, contentLength uint8) bool {
		// Map random input to valid message type
		messageType := validTypes[int(typeIndex)%len(validTypes)]

		// Generate random content (1-255 characters)
		contentLen := int(contentLength)
		if contentLen == 0 {
			contentLen = 1
		}
		content := make([]byte, contentLen)
		for i := range content {
			content[i] = 'a' + byte(i%26) // Simple pattern
		}

		// Setup mocks
		mockMessageRepo := new(MockMessageRepository)
		mockOnlineRepo := new(MockOnlineRepository)
		mockRoomRepo := new(MockRoomRepository)

		usecase := &messageUsecase{
			messageRepo:    mockMessageRepo,
			onlineRepo:     mockOnlineRepo,
			roomRepo:       mockRoomRepo,
			contextTimeout: 5 * time.Second,
		}

		// Create message without Link Preview
		msg := &domain.Message{
			ID:          fmt.Sprintf("msg_%d", time.Now().UnixNano()),
			SenderID:    "user_sender",
			ReceiverID:  "user_receiver",
			Content:     string(content),
			Type:        messageType,
			LinkPreview: nil, // No Link Preview
		}

		originalType := msg.Type

		// Setup mocks
		mockOnlineRepo.On("IsUserOnline", mock.Anything, "user_receiver").Return(true, nil)
		mockMessageRepo.On("StoreMessage", mock.Anything, mock.AnythingOfType("*domain.Message")).Return(nil)

		// Execute
		ctx := context.Background()
		err := usecase.SendMessage(ctx, msg)
		if err != nil {
			return false
		}

		// Verify preservation
		return msg.Type == originalType && msg.LinkPreview == nil
	}

	// Run property-based test with multiple iterations
	config := &quick.Config{
		MaxCount: 50, // Test with 50 random combinations
	}

	err := quick.Check(property, config)
	if err != nil {
		t.Errorf("Property violation: %v", err)
	} else {
		t.Logf("✅ PRESERVATION PROPERTY VERIFIED: Tested %d random message combinations", config.MaxCount)
		t.Logf("   All messages without Link Preview preserved their Type field correctly")
	}
}

// TestPreservation_EmptyLinkPreview tests that messages with empty/invalid Link Preview
// are handled correctly (Link Preview should be cleared, Type preserved).
func TestPreservation_EmptyLinkPreview(t *testing.T) {
	testCases := []struct {
		name         string
		messageType  string
		linkPreview  *domain.LinkPreview
		description  string
	}{
		{
			name:        "nil_link_preview",
			messageType: "text",
			linkPreview: nil,
			description: "Message with nil Link Preview",
		},
		{
			name:        "empty_url_link_preview",
			messageType: "text",
			linkPreview: &domain.LinkPreview{
				URL:   "",
				Title: "Some Title",
			},
			description: "Message with empty URL in Link Preview",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Setup mocks
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
				ID:          fmt.Sprintf("msg_%d", time.Now().UnixNano()),
				SenderID:    "user_sender",
				ReceiverID:  "user_receiver",
				Content:     "Test message",
				Type:        tc.messageType,
				LinkPreview: tc.linkPreview,
			}

			originalType := msg.Type

			t.Logf("Testing: %s", tc.description)

			// Setup mocks
			mockOnlineRepo.On("IsUserOnline", mock.Anything, "user_receiver").Return(true, nil)
			mockMessageRepo.On("StoreMessage", mock.Anything, mock.AnythingOfType("*domain.Message")).Return(nil)

			// Execute
			ctx := context.Background()
			err := usecase.SendMessage(ctx, msg)
			require.NoError(t, err)

			// PRESERVATION ASSERTION:
			// Type should be preserved even when Link Preview is invalid
			assert.Equal(t, originalType, msg.Type,
				"Message type should be preserved when Link Preview is empty/invalid")

			// Invalid Link Preview should be cleared
			assert.Nil(t, msg.LinkPreview,
				"Invalid Link Preview should be cleared by backend")

			t.Logf("✅ PRESERVATION VERIFIED: Type '%s' preserved, invalid Link Preview cleared", msg.Type)

			mockOnlineRepo.AssertExpectations(t)
			mockMessageRepo.AssertExpectations(t)
		})
	}
}
