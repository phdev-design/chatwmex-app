package rabbitmq

import (
	"context"
	"testing"
	"time"

	"chatwmex_backend/internal/config"
	"chatwmex_backend/internal/domain"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// MockPushNotificationService is a mock implementation of domain.PushNotificationService
type MockPushNotificationService struct {
	mock.Mock
}

func (m *MockPushNotificationService) SendNotificationToDevices(playerIDs []string, title string, content string, data map[string]interface{}) error {
	args := m.Called(playerIDs, title, content, data)
	return args.Error(0)
}

// TestIntegration_EndToEndNotificationFlow tests the complete flow from producer to consumer
// Feature: async-push-notification-rabbitmq
// This test validates Requirements 3.1, 4.1, 4.3, 4.4
func TestIntegration_EndToEndNotificationFlow(t *testing.T) {
	// Skip if RabbitMQ is not available
	cfg := &config.Config{
		RabbitMQURL: "amqp://guest:guest@localhost:5672/",
	}

	// Test connection first
	producer, err := NewNotificationProducer(cfg)
	if err != nil {
		t.Skipf("Skipping integration test: RabbitMQ not available: %v", err)
		return
	}
	defer producer.Close()

	// Setup mock OneSignal service
	mockOneSignal := new(MockPushNotificationService)
	
	// Create test notification message
	testMsg := &domain.PushNotificationMessage{
		PlayerIDs: []string{"device1", "device2", "device3"},
		Title:     "Test Notification",
		Content:   "This is a test message",
		Data: map[string]interface{}{
			"room_id":           "room123",
			"is_room":           true,
			"room_name":         "Test Room",
			"encrypted_content": "encrypted_test_content",
			"sender_id":         "user456",
			"message_id":        "msg789",
		},
	}

	// Setup expectation: OneSignal should be called with the correct data
	mockOneSignal.On("SendNotificationToDevices",
		testMsg.PlayerIDs,
		testMsg.Title,
		testMsg.Content,
		testMsg.Data,
	).Return(nil).Once()

	// Create consumer
	consumer, err := NewNotificationConsumer(cfg, mockOneSignal)
	require.NoError(t, err, "Failed to create consumer")
	defer consumer.Stop()

	// Start consumer with timeout context
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	err = consumer.Start(ctx)
	require.NoError(t, err, "Failed to start consumer")

	// Give consumer time to start listening
	time.Sleep(100 * time.Millisecond)

	// Publish notification message
	err = producer.Publish(context.Background(), testMsg)
	require.NoError(t, err, "Failed to publish message")

	// Wait for message to be processed (with timeout)
	// The mock will be called when the consumer processes the message
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if mockOneSignal.AssertExpectations(t) {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	// Verify that OneSignal was called with correct parameters
	mockOneSignal.AssertExpectations(t)
	mockOneSignal.AssertCalled(t, "SendNotificationToDevices",
		testMsg.PlayerIDs,
		testMsg.Title,
		testMsg.Content,
		testMsg.Data,
	)
}

// TestIntegration_MessageSerializationRoundTrip tests JSON serialization/deserialization
// Feature: async-push-notification-rabbitmq, Property 1: Notification Message Serialization Round-Trip
// Validates: Requirements 3.2, 4.2
func TestIntegration_MessageSerializationRoundTrip(t *testing.T) {
	cfg := &config.Config{
		RabbitMQURL: "amqp://guest:guest@localhost:5672/",
	}

	producer, err := NewNotificationProducer(cfg)
	if err != nil {
		t.Skipf("Skipping integration test: RabbitMQ not available: %v", err)
		return
	}
	defer producer.Close()

	mockOneSignal := new(MockPushNotificationService)

	// Create test message with various data types
	originalMsg := &domain.PushNotificationMessage{
		PlayerIDs: []string{"device1", "device2"},
		Title:     "Test Title with 中文",
		Content:   "Test Content with emoji 🔒",
		Data: map[string]interface{}{
			"string_field": "test_value",
			"int_field":    123,
			"bool_field":   true,
			"nested_map": map[string]interface{}{
				"nested_key": "nested_value",
			},
		},
	}

	// Setup mock to capture the received message
	var receivedPlayerIDs []string
	var receivedTitle string
	var receivedContent string
	var receivedData map[string]interface{}

	mockOneSignal.On("SendNotificationToDevices",
		mock.AnythingOfType("[]string"),
		mock.AnythingOfType("string"),
		mock.AnythingOfType("string"),
		mock.AnythingOfType("map[string]interface {}"),
	).Run(func(args mock.Arguments) {
		receivedPlayerIDs = args.Get(0).([]string)
		receivedTitle = args.Get(1).(string)
		receivedContent = args.Get(2).(string)
		receivedData = args.Get(3).(map[string]interface{})
	}).Return(nil).Once()

	consumer, err := NewNotificationConsumer(cfg, mockOneSignal)
	require.NoError(t, err)
	defer consumer.Stop()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	err = consumer.Start(ctx)
	require.NoError(t, err)

	time.Sleep(100 * time.Millisecond)

	// Publish message
	err = producer.Publish(context.Background(), originalMsg)
	require.NoError(t, err)

	// Wait for processing
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if mockOneSignal.AssertExpectations(t) {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	// Verify serialization round-trip preserved all fields
	assert.Equal(t, originalMsg.PlayerIDs, receivedPlayerIDs, "PlayerIDs should match")
	assert.Equal(t, originalMsg.Title, receivedTitle, "Title should match")
	assert.Equal(t, originalMsg.Content, receivedContent, "Content should match")
	assert.Equal(t, originalMsg.Data["string_field"], receivedData["string_field"], "String field should match")
	assert.Equal(t, float64(123), receivedData["int_field"], "Int field should match (JSON numbers are float64)")
	assert.Equal(t, originalMsg.Data["bool_field"], receivedData["bool_field"], "Bool field should match")
}

// TestIntegration_ConsumerErrorHandling tests error handling and retry logic
// Feature: async-push-notification-rabbitmq
// Validates: Requirements 5.1, 5.3
func TestIntegration_ConsumerErrorHandling(t *testing.T) {
	cfg := &config.Config{
		RabbitMQURL: "amqp://guest:guest@localhost:5672/",
	}

	producer, err := NewNotificationProducer(cfg)
	if err != nil {
		t.Skipf("Skipping integration test: RabbitMQ not available: %v", err)
		return
	}
	defer producer.Close()

	mockOneSignal := new(MockPushNotificationService)

	testMsg := &domain.PushNotificationMessage{
		PlayerIDs: []string{"device1"},
		Title:     "Test",
		Content:   "Test",
		Data:      map[string]interface{}{},
	}

	// First call fails with transient error, second call succeeds
	callCount := 0
	mockOneSignal.On("SendNotificationToDevices",
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
	).Run(func(args mock.Arguments) {
		callCount++
	}).Return(func([]string, string, string, map[string]interface{}) error {
		if callCount == 1 {
			// Return transient error (should trigger retry)
			return assert.AnError
		}
		// Second attempt succeeds
		return nil
	})

	consumer, err := NewNotificationConsumer(cfg, mockOneSignal)
	require.NoError(t, err)
	defer consumer.Stop()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	err = consumer.Start(ctx)
	require.NoError(t, err)

	time.Sleep(100 * time.Millisecond)

	// Publish message
	err = producer.Publish(context.Background(), testMsg)
	require.NoError(t, err)

	// Wait for processing with retries
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		if callCount >= 2 {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}

	// Verify that the service was called at least twice (initial + retry)
	assert.GreaterOrEqual(t, callCount, 2, "OneSignal should be called at least twice (initial + retry)")
}

// TestIntegration_MultipleMessages tests handling multiple concurrent messages
// Feature: async-push-notification-rabbitmq
// Validates: Requirements 3.1, 4.1
func TestIntegration_MultipleMessages(t *testing.T) {
	cfg := &config.Config{
		RabbitMQURL: "amqp://guest:guest@localhost:5672/",
	}

	producer, err := NewNotificationProducer(cfg)
	if err != nil {
		t.Skipf("Skipping integration test: RabbitMQ not available: %v", err)
		return
	}
	defer producer.Close()

	mockOneSignal := new(MockPushNotificationService)

	// Setup mock to accept any calls
	mockOneSignal.On("SendNotificationToDevices",
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
	).Return(nil)

	consumer, err := NewNotificationConsumer(cfg, mockOneSignal)
	require.NoError(t, err)
	defer consumer.Stop()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	err = consumer.Start(ctx)
	require.NoError(t, err)

	time.Sleep(100 * time.Millisecond)

	// Publish multiple messages
	messageCount := 5
	for i := 0; i < messageCount; i++ {
		testMsg := &domain.PushNotificationMessage{
			PlayerIDs: []string{string(rune('A' + i))},
			Title:     "Test",
			Content:   "Test",
			Data:      map[string]interface{}{"index": i},
		}
		err = producer.Publish(context.Background(), testMsg)
		require.NoError(t, err)
	}

	// Wait for all messages to be processed
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if len(mockOneSignal.Calls) >= messageCount {
			break
		}
		time.Sleep(200 * time.Millisecond)
	}

	// Verify all messages were processed
	assert.GreaterOrEqual(t, len(mockOneSignal.Calls), messageCount,
		"All messages should be processed")
}

// TestIntegration_GracefulShutdown tests graceful shutdown of producer and consumer
// Feature: async-push-notification-rabbitmq
// Validates: Requirements 2.3, 7.4
func TestIntegration_GracefulShutdown(t *testing.T) {
	cfg := &config.Config{
		RabbitMQURL: "amqp://guest:guest@localhost:5672/",
	}

	producer, err := NewNotificationProducer(cfg)
	if err != nil {
		t.Skipf("Skipping integration test: RabbitMQ not available: %v", err)
		return
	}

	mockOneSignal := new(MockPushNotificationService)
	mockOneSignal.On("SendNotificationToDevices",
		mock.Anything,
		mock.Anything,
		mock.Anything,
		mock.Anything,
	).Return(nil)

	consumer, err := NewNotificationConsumer(cfg, mockOneSignal)
	require.NoError(t, err)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	err = consumer.Start(ctx)
	require.NoError(t, err)

	time.Sleep(100 * time.Millisecond)

	// Publish a message
	testMsg := &domain.PushNotificationMessage{
		PlayerIDs: []string{"device1"},
		Title:     "Test",
		Content:   "Test",
		Data:      map[string]interface{}{},
	}
	err = producer.Publish(context.Background(), testMsg)
	require.NoError(t, err)

	// Wait a bit for processing
	time.Sleep(500 * time.Millisecond)

	// Test graceful shutdown
	err = consumer.Stop()
	assert.NoError(t, err, "Consumer should stop gracefully")

	err = producer.Close()
	assert.NoError(t, err, "Producer should close gracefully")

	// Verify we can't publish after closing
	err = producer.Publish(context.Background(), testMsg)
	assert.Error(t, err, "Publishing after close should fail")
}
