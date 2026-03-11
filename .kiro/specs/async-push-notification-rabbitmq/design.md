# Design Document: Async Push Notification with RabbitMQ

## Overview

This design refactors the push notification system to use RabbitMQ for asynchronous processing, decoupling notification delivery from the main API and WebSocket flows. Currently, the `message_usecase.go` calls the OneSignal service synchronously via `pushToOfflineUsers()`, which blocks message processing. The new architecture introduces a producer-consumer pattern where notification messages are published to a dedicated RabbitMQ queue and processed by a separate worker.

### Current Architecture Issues

- Push notifications are sent synchronously in `message_usecase.SendMessage()`
- The `pushToOfflineUsers()` goroutine still blocks on HTTP calls to OneSignal
- Message operations wait for notification delivery, increasing latency
- No retry mechanism for failed notifications
- No visibility into notification processing failures

### Proposed Solution

Implement a queue-based notification system with:
- **Producer**: Publishes notification messages to RabbitMQ queue from message usecase
- **Consumer**: Worker that processes notifications asynchronously
- **Dead Letter Queue**: Handles failed notifications after retry attempts
- **Graceful degradation**: Message operations succeed even if notification publishing fails

### Benefits

- Reduced API response time (no blocking on push notification delivery)
- Improved reliability with automatic retries
- Better observability with centralized error logging
- Scalability through independent worker scaling
- Fault isolation between message delivery and notification delivery

## Architecture

### System Context

The notification system integrates with the existing Clean Architecture layers:

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                       │
│  (HTTP Handlers, WebSocket Hub)                             │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│                    Application Layer                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Message Usecase                               │  │
│  │  - SendMessage()                                      │  │
│  │  - Calls NotificationProducer.Publish()              │  │
│  └──────────────────┬───────────────────────────────────┘  │
└─────────────────────┼──────────────────────────────────────┘
                      │
┌─────────────────────▼──────────────────────────────────────┐
│                Infrastructure Layer                         │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  NotificationProducer                                 │ │
│  │  - Publish(PushNotificationMessage)                  │ │
│  │  - Serializes to JSON                                │ │
│  │  - Publishes to "notification_queue"                 │ │
│  └──────────────────┬───────────────────────────────────┘ │
│                     │                                       │
│  ┌──────────────────▼───────────────────────────────────┐ │
│  │         RabbitMQ Broker                              │ │
│  │  Queue: "notification_queue" (durable)               │ │
│  │  DLQ: "notification_dlq"                             │ │
│  └──────────────────┬───────────────────────────────────┘ │
│                     │                                       │
│  ┌──────────────────▼───────────────────────────────────┐ │
│  │  NotificationConsumer (Worker)                       │ │
│  │  - Consumes from "notification_queue"                │ │
│  │  - Deserializes JSON                                 │ │
│  │  - Calls OneSignalService                            │ │
│  │  - Handles ACK/NACK with retry                       │ │
│  └──────────────────┬───────────────────────────────────┘ │
│                     │                                       │
│  ┌──────────────────▼───────────────────────────────────┐ │
│  │  OneSignalService                                    │ │
│  │  - SendNotificationToDevices()                       │ │
│  │  - HTTP POST to OneSignal API                        │ │
│  └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Component Interaction Flow

```mermaid
sequenceDiagram
    participant API as HTTP/WebSocket Handler
    participant MU as Message Usecase
    participant NP as NotificationProducer
    participant RMQ as RabbitMQ Queue
    participant NC as NotificationConsumer
    participant OS as OneSignal Service
    
    API->>MU: SendMessage(msg)
    MU->>MU: Validate & Store Message
    MU->>MU: Build PushNotificationMessage
    MU->>NP: Publish(pushMsg)
    NP->>NP: Serialize to JSON
    NP->>RMQ: Publish to notification_queue
    NP-->>MU: Return (no wait)
    MU-->>API: Return success
    
    Note over NC,RMQ: Async Processing
    RMQ->>NC: Deliver message
    NC->>NC: Deserialize JSON
    NC->>OS: SendNotificationToDevices()
    OS-->>NC: Success/Error
    alt Success
        NC->>RMQ: ACK message
    else Transient Error
        NC->>RMQ: NACK with requeue
    else Permanent Error
        NC->>RMQ: NACK without requeue
        RMQ->>RMQ: Route to DLQ
    end
```

### Clean Architecture Boundaries

The design maintains Clean Architecture principles:

1. **Domain Layer** (`internal/domain`):
   - Defines `PushNotificationMessage` struct
   - Defines `NotificationProducer` interface
   - No dependencies on infrastructure

2. **Application Layer** (`internal/usecase`):
   - `MessageUsecase` depends on `NotificationProducer` interface
   - Business logic for when to send notifications
   - No knowledge of RabbitMQ implementation details

3. **Infrastructure Layer** (`internal/infrastructure/rabbitmq`):
   - `NotificationProducer` implementation
   - `NotificationConsumer` implementation
   - RabbitMQ connection management
   - Depends on domain interfaces

4. **Main Application** (`cmd/server/main.go`):
   - Dependency injection and wiring
   - Lifecycle management (startup/shutdown)
   - Configuration loading

## Components and Interfaces

### Domain Layer Definitions

#### PushNotificationMessage

```go
// File: internal/domain/notification.go

type PushNotificationMessage struct {
    PlayerIDs []string               `json:"player_ids"` // OneSignal device IDs
    Title     string                 `json:"title"`      // Notification heading
    Content   string                 `json:"content"`    // Notification body
    Data      map[string]interface{} `json:"data"`       // Custom payload
}
```

#### NotificationProducer Interface

```go
// File: internal/domain/notification.go

type NotificationProducer interface {
    // Publish sends a notification message to the queue
    // Returns error if publishing fails, but does not wait for delivery
    Publish(ctx context.Context, msg *PushNotificationMessage) error
    
    // Close gracefully shuts down the producer
    Close() error
}
```

### Infrastructure Layer Implementation

#### RabbitMQ Producer

```go
// File: internal/infrastructure/rabbitmq/notification_producer.go

type NotificationProducerImpl struct {
    conn      *amqp.Connection
    channel   *amqp.Channel
    queueName string
}

func NewNotificationProducer(cfg *config.Config) (domain.NotificationProducer, error) {
    // Connect to RabbitMQ
    // Declare notification_queue as durable
    // Declare DLQ with appropriate bindings
    // Return producer instance
}

func (p *NotificationProducerImpl) Publish(ctx context.Context, msg *domain.PushNotificationMessage) error {
    // Serialize message to JSON
    // Publish to notification_queue
    // Return immediately (non-blocking)
}

func (p *NotificationProducerImpl) Close() error {
    // Close channel and connection gracefully
}
```

#### RabbitMQ Consumer

```go
// File: internal/infrastructure/rabbitmq/notification_consumer.go

type NotificationConsumer struct {
    conn            *amqp.Connection
    channel         *amqp.Channel
    queueName       string
    oneSignalService domain.PushNotificationService
    maxRetries      int
}

func NewNotificationConsumer(
    cfg *config.Config,
    oneSignalService domain.PushNotificationService,
) (*NotificationConsumer, error) {
    // Connect to RabbitMQ
    // Setup consumer channel
    // Return consumer instance
}

func (c *NotificationConsumer) Start(ctx context.Context) error {
    // Begin consuming from notification_queue
    // For each message:
    //   - Deserialize JSON
    //   - Call OneSignalService
    //   - Handle ACK/NACK based on result
    // Respect context cancellation for graceful shutdown
}

func (c *NotificationConsumer) Stop() error {
    // Stop consuming
    // Close channel and connection
}
```

### Application Layer Integration

#### Message Usecase Modification

```go
// File: internal/usecase/message_usecase.go

type messageUsecase struct {
    // ... existing fields ...
    notificationProducer domain.NotificationProducer // NEW
}

func NewMessageUsecase(
    // ... existing params ...
    notificationProducer domain.NotificationProducer, // NEW
    timeout time.Duration,
) domain.MessageUsecase {
    return &messageUsecase{
        // ... existing assignments ...
        notificationProducer: notificationProducer,
    }
}

func (u *messageUsecase) SendMessage(c context.Context, msg *domain.Message) error {
    // ... existing validation and storage logic ...
    
    // Build notification message
    if u.notificationProducer != nil && len(pushTargets) > 0 {
        pushMsg := u.buildPushNotificationMessage(pushTargets, msg)
        
        // Publish asynchronously - don't block on errors
        if err := u.notificationProducer.Publish(c, pushMsg); err != nil {
            log.Printf("Failed to publish notification: %v", err)
            // Continue - message was already stored successfully
        }
    }
    
    return nil
}

func (u *messageUsecase) buildPushNotificationMessage(
    userIDs []string,
    msg *domain.Message,
) *domain.PushNotificationMessage {
    // Collect player IDs from device repository
    // Build title and content
    // Create data payload
    // Return PushNotificationMessage
}
```

## Data Models

### PushNotificationMessage Structure

```go
type PushNotificationMessage struct {
    PlayerIDs []string               `json:"player_ids"`
    Title     string                 `json:"title"`
    Content   string                 `json:"content"`
    Data      map[string]interface{} `json:"data"`
}
```

**Field Descriptions:**

- `PlayerIDs`: Array of OneSignal device IDs (player IDs) to target
- `Title`: Notification heading displayed to user
- `Content`: Notification body text (may be encrypted message placeholder)
- `Data`: Custom payload containing:
  - `room_id`: Chat room or sender ID for navigation
  - `is_room`: Boolean indicating group vs DM
  - `room_name`: Display name for notification
  - `encrypted_content`: Original encrypted message content
  - `sender_id`: Message sender's user ID
  - `message_id`: Unique message identifier

### RabbitMQ Queue Configuration

#### notification_queue

```go
QueueConfig{
    Name:       "notification_queue",
    Durable:    true,  // Survive broker restarts
    AutoDelete: false, // Don't delete when unused
    Exclusive:  false, // Allow multiple consumers
    Arguments: map[string]interface{}{
        "x-dead-letter-exchange":    "notification_dlx",
        "x-dead-letter-routing-key": "notification_dlq",
        "x-message-ttl":             300000, // 5 minutes
    },
}
```

#### notification_dlq (Dead Letter Queue)

```go
QueueConfig{
    Name:       "notification_dlq",
    Durable:    true,
    AutoDelete: false,
    Exclusive:  false,
    Arguments:  nil,
}

ExchangeConfig{
    Name:       "notification_dlx",
    Type:       "direct",
    Durable:    true,
    AutoDelete: false,
}
```

### Message Flow Data Transformation

```
Message Usecase
    ↓
    userIDs: ["user1", "user2"]
    msg: *domain.Message
    ↓
    [Query device repository]
    ↓
    playerIDs: ["device1", "device2", "device3"]
    ↓
    PushNotificationMessage{
        PlayerIDs: ["device1", "device2", "device3"],
        Title: "Room Name",
        Content: "🔒 一則加密訊息",
        Data: {
            "room_id": "room123",
            "is_room": true,
            "encrypted_content": "...",
            "sender_id": "user1",
            "message_id": "msg456"
        }
    }
    ↓
    [JSON Serialization]
    ↓
    RabbitMQ Queue
    ↓
    [JSON Deserialization]
    ↓
    NotificationConsumer
    ↓
    OneSignalService.SendNotificationToDevices()
```


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

Before defining the correctness properties, let me analyze each acceptance criterion for testability:


### Property Reflection

After analyzing the acceptance criteria, I identified the following testable properties and examples. Here's the reflection on potential redundancies:

**Serialization Properties (3.2, 4.2):**
- These two criteria describe the same round-trip property from different perspectives
- Combined into a single comprehensive serialization round-trip property

**Non-blocking Behavior (3.4, 6.3):**
- Both test that operations don't wait for notification delivery
- Combined into a single property about asynchronous publishing

**Error Logging (3.3, 5.3):**
- Both require error logging but at different layers
- Kept separate as they test different components (producer vs consumer)

**Acknowledgment Properties (4.4, 5.1):**
- Both test message acknowledgment but for different outcomes
- Kept separate as they represent different control flow paths

**Graceful Degradation (6.2):**
- Unique property ensuring message operations succeed despite notification failures
- No redundancy identified

After reflection, the following properties provide unique validation value:

### Property 1: Notification Message Serialization Round-Trip

*For any* valid PushNotificationMessage, serializing to JSON and then deserializing should produce an equivalent message with all fields preserved (PlayerIDs, Title, Content, Data).

**Validates: Requirements 3.2, 4.2**

### Property 2: Asynchronous Publishing Non-Blocking

*For any* valid PushNotificationMessage, the Publish() operation should return immediately without waiting for consumer processing or OneSignal delivery, with execution time bounded by network I/O to RabbitMQ only.

**Validates: Requirements 3.4, 6.3**

### Property 3: Message Queue Delivery

*For any* valid PushNotificationMessage published to the notification queue, the message should be consumable by the NotificationConsumer and deserializable back to the original structure.

**Validates: Requirements 3.1, 4.1, 4.2**

### Property 4: Successful Delivery Acknowledgment

*For any* notification message where OneSignal returns success, the RabbitMQ_Consumer should acknowledge the message, removing it from the queue.

**Validates: Requirements 4.3, 4.4**

### Property 5: Transient Error Retry

*For any* notification message where OneSignal returns a transient error (network timeout, 5xx status), the RabbitMQ_Consumer should negatively acknowledge with requeue enabled, allowing retry.

**Validates: Requirements 5.1**

### Property 6: Error Logging on Failure

*For any* error occurring during message processing (deserialization, OneSignal call, etc.), the system should log the error with message details and error context.

**Validates: Requirements 3.3, 5.3**

### Property 7: Graceful Degradation

*For any* message operation in Message_Usecase, if notification publishing fails, the message should still be stored successfully and the operation should return success (notification failure does not fail message delivery).

**Validates: Requirements 6.2**

### Property 8: Consumer Invokes OneSignal

*For any* successfully deserialized PushNotificationMessage, the NotificationConsumer should invoke OneSignalService.SendNotificationToDevices() with the correct PlayerIDs, Title, Content, and Data.

**Validates: Requirements 4.3**


## Error Handling

### Error Categories

The system handles three categories of errors:

1. **Producer Errors**: Failures during message publishing
2. **Consumer Errors**: Failures during message consumption and processing
3. **OneSignal Errors**: Failures from the external notification service

### Producer Error Handling

```go
func (p *NotificationProducerImpl) Publish(ctx context.Context, msg *PushNotificationMessage) error {
    body, err := json.Marshal(msg)
    if err != nil {
        log.Printf("Failed to serialize notification message: %v", err)
        return fmt.Errorf("serialization error: %w", err)
    }
    
    err = p.channel.PublishWithContext(
        ctx,
        "",                  // exchange
        p.queueName,         // routing key
        false,               // mandatory
        false,               // immediate
        amqp.Publishing{
            ContentType:  "application/json",
            Body:         body,
            DeliveryMode: amqp.Persistent, // Survive broker restarts
        },
    )
    
    if err != nil {
        log.Printf("Failed to publish notification to queue: %v", err)
        return fmt.Errorf("publish error: %w", err)
    }
    
    return nil
}
```

**Error Handling Strategy:**
- Serialization errors: Log and return error (indicates programming bug)
- Publishing errors: Log and return error (indicates RabbitMQ connectivity issue)
- Caller (Message Usecase) logs but continues processing

### Consumer Error Handling

```go
func (c *NotificationConsumer) processMessage(delivery amqp.Delivery) {
    var msg domain.PushNotificationMessage
    
    // Deserialization errors - permanent failure
    if err := json.Unmarshal(delivery.Body, &msg); err != nil {
        log.Printf("Failed to deserialize notification message: %v, body: %s", 
            err, string(delivery.Body))
        delivery.Nack(false, false) // Don't requeue - bad message
        return
    }
    
    // Validation errors - permanent failure
    if len(msg.PlayerIDs) == 0 {
        log.Printf("Invalid notification message: no player IDs")
        delivery.Nack(false, false) // Don't requeue
        return
    }
    
    // OneSignal delivery
    err := c.oneSignalService.SendNotificationToDevices(
        msg.PlayerIDs,
        msg.Title,
        msg.Content,
        msg.Data,
    )
    
    if err != nil {
        if isTransientError(err) {
            // Transient error - retry
            log.Printf("Transient error sending notification (will retry): %v", err)
            delivery.Nack(false, true) // Requeue for retry
        } else {
            // Permanent error - don't retry
            log.Printf("Permanent error sending notification: %v", err)
            delivery.Nack(false, false) // Send to DLQ
        }
        return
    }
    
    // Success
    delivery.Ack(false)
}

func isTransientError(err error) bool {
    // Network timeouts, 5xx errors are transient
    // 4xx errors (bad request) are permanent
    errStr := err.Error()
    return strings.Contains(errStr, "timeout") ||
           strings.Contains(errStr, "connection refused") ||
           strings.Contains(errStr, "500") ||
           strings.Contains(errStr, "502") ||
           strings.Contains(errStr, "503") ||
           strings.Contains(errStr, "504")
}
```

**Error Handling Strategy:**
- Deserialization errors: NACK without requeue (malformed message)
- Validation errors: NACK without requeue (invalid data)
- Transient OneSignal errors: NACK with requeue (retry)
- Permanent OneSignal errors: NACK without requeue (send to DLQ)

### Dead Letter Queue Configuration

```go
func declareQueues(ch *amqp.Channel) error {
    // Declare DLX (Dead Letter Exchange)
    err := ch.ExchangeDeclare(
        "notification_dlx", // name
        "direct",           // type
        true,               // durable
        false,              // auto-deleted
        false,              // internal
        false,              // no-wait
        nil,                // arguments
    )
    if err != nil {
        return fmt.Errorf("failed to declare DLX: %w", err)
    }
    
    // Declare DLQ (Dead Letter Queue)
    _, err = ch.QueueDeclare(
        "notification_dlq", // name
        true,               // durable
        false,              // delete when unused
        false,              // exclusive
        false,              // no-wait
        nil,                // arguments
    )
    if err != nil {
        return fmt.Errorf("failed to declare DLQ: %w", err)
    }
    
    // Bind DLQ to DLX
    err = ch.QueueBind(
        "notification_dlq", // queue name
        "notification_dlq", // routing key
        "notification_dlx", // exchange
        false,
        nil,
    )
    if err != nil {
        return fmt.Errorf("failed to bind DLQ: %w", err)
    }
    
    // Declare main queue with DLX configuration
    _, err = ch.QueueDeclare(
        "notification_queue", // name
        true,                 // durable
        false,                // delete when unused
        false,                // exclusive
        false,                // no-wait
        amqp.Table{
            "x-dead-letter-exchange":    "notification_dlx",
            "x-dead-letter-routing-key": "notification_dlq",
            "x-message-ttl":             300000, // 5 minutes
        },
    )
    if err != nil {
        return fmt.Errorf("failed to declare notification queue: %w", err)
    }
    
    return nil
}
```

### Retry Mechanism

The retry mechanism is handled by RabbitMQ's built-in requeue functionality:

1. **First Attempt**: Consumer processes message
2. **Transient Failure**: NACK with requeue=true
3. **Redelivery**: RabbitMQ redelivers message (with `redelivered` flag set)
4. **Retry Attempts**: Consumer tracks retry count via message headers
5. **Max Retries Exceeded**: NACK with requeue=false → DLQ

```go
func (c *NotificationConsumer) processMessage(delivery amqp.Delivery) {
    // Check retry count
    retryCount := 0
    if xDeath, ok := delivery.Headers["x-death"].([]interface{}); ok && len(xDeath) > 0 {
        if death, ok := xDeath[0].(amqp.Table); ok {
            if count, ok := death["count"].(int64); ok {
                retryCount = int(count)
            }
        }
    }
    
    if retryCount >= c.maxRetries {
        log.Printf("Max retries exceeded for notification message, sending to DLQ")
        delivery.Nack(false, false) // Send to DLQ
        return
    }
    
    // ... rest of processing ...
}
```

### Error Logging Standards

All errors should be logged with structured context:

```go
log.Printf("[NotificationProducer] Failed to publish: error=%v, playerIDs=%v, title=%s",
    err, msg.PlayerIDs, msg.Title)

log.Printf("[NotificationConsumer] Processing failed: error=%v, retryCount=%d, playerIDs=%v",
    err, retryCount, msg.PlayerIDs)
```

### Graceful Degradation

The system is designed to degrade gracefully:

- **Producer unavailable**: Message operations succeed, notifications lost
- **Consumer unavailable**: Messages queue up, delivered when consumer restarts
- **OneSignal unavailable**: Messages retry, eventually move to DLQ
- **RabbitMQ unavailable**: Producer returns error, logged but message operation succeeds

## Testing Strategy

### Dual Testing Approach

The testing strategy employs both unit tests and property-based tests to ensure comprehensive coverage:

- **Unit Tests**: Verify specific examples, edge cases, error conditions, and integration points
- **Property-Based Tests**: Verify universal properties across randomized inputs

Both approaches are complementary and necessary for comprehensive correctness validation.

### Property-Based Testing

Property-based tests will be implemented using the **testify** library with custom property test helpers for Go. Each property test will:

- Run a minimum of 100 iterations with randomized inputs
- Reference the corresponding design document property via comment tag
- Use the format: `// Feature: async-push-notification-rabbitmq, Property {number}: {property_text}`

#### Property Test Examples

**Property 1: Serialization Round-Trip**

```go
// Feature: async-push-notification-rabbitmq, Property 1: Notification Message Serialization Round-Trip
func TestProperty_SerializationRoundTrip(t *testing.T) {
    for i := 0; i < 100; i++ {
        // Generate random PushNotificationMessage
        original := generateRandomPushNotificationMessage()
        
        // Serialize
        data, err := json.Marshal(original)
        require.NoError(t, err)
        
        // Deserialize
        var decoded domain.PushNotificationMessage
        err = json.Unmarshal(data, &decoded)
        require.NoError(t, err)
        
        // Assert equivalence
        assert.Equal(t, original.PlayerIDs, decoded.PlayerIDs)
        assert.Equal(t, original.Title, decoded.Title)
        assert.Equal(t, original.Content, decoded.Content)
        assert.Equal(t, original.Data, decoded.Data)
    }
}
```

**Property 2: Asynchronous Publishing Non-Blocking**

```go
// Feature: async-push-notification-rabbitmq, Property 2: Asynchronous Publishing Non-Blocking
func TestProperty_PublishNonBlocking(t *testing.T) {
    producer := setupTestProducer(t)
    defer producer.Close()
    
    for i := 0; i < 100; i++ {
        msg := generateRandomPushNotificationMessage()
        
        start := time.Now()
        err := producer.Publish(context.Background(), msg)
        duration := time.Since(start)
        
        require.NoError(t, err)
        // Publishing should complete quickly (< 100ms for local RabbitMQ)
        assert.Less(t, duration, 100*time.Millisecond)
    }
}
```

**Property 7: Graceful Degradation**

```go
// Feature: async-push-notification-rabbitmq, Property 7: Graceful Degradation
func TestProperty_GracefulDegradation(t *testing.T) {
    // Setup usecase with failing producer
    failingProducer := &FailingNotificationProducer{}
    usecase := setupMessageUsecaseWithProducer(t, failingProducer)
    
    for i := 0; i < 100; i++ {
        msg := generateRandomMessage()
        
        // Message operation should succeed despite notification failure
        err := usecase.SendMessage(context.Background(), msg)
        assert.NoError(t, err)
        
        // Verify message was stored
        stored, err := usecase.GetHistory(context.Background(), msg.SenderID, msg.ReceiverID, 1, 0)
        require.NoError(t, err)
        assert.Len(t, stored, 1)
    }
}
```

### Unit Testing

Unit tests focus on specific scenarios, edge cases, and integration points:

#### Producer Unit Tests

```go
func TestNotificationProducer_PublishSuccess(t *testing.T) {
    // Test successful publishing
}

func TestNotificationProducer_PublishWithInvalidJSON(t *testing.T) {
    // Test serialization error handling
}

func TestNotificationProducer_PublishWithClosedConnection(t *testing.T) {
    // Test connection error handling
}

func TestNotificationProducer_CloseGracefully(t *testing.T) {
    // Test graceful shutdown
}
```

#### Consumer Unit Tests

```go
func TestNotificationConsumer_ProcessValidMessage(t *testing.T) {
    // Test successful message processing and ACK
}

func TestNotificationConsumer_ProcessMalformedJSON(t *testing.T) {
    // Test deserialization error → NACK without requeue
}

func TestNotificationConsumer_ProcessWithTransientError(t *testing.T) {
    // Test transient OneSignal error → NACK with requeue
}

func TestNotificationConsumer_ProcessWithPermanentError(t *testing.T) {
    // Test permanent OneSignal error → NACK without requeue → DLQ
}

func TestNotificationConsumer_ProcessMaxRetriesExceeded(t *testing.T) {
    // Test max retry limit → DLQ
}

func TestNotificationConsumer_GracefulShutdown(t *testing.T) {
    // Test context cancellation stops consumer
}
```

#### Integration Tests

```go
func TestIntegration_EndToEndNotificationFlow(t *testing.T) {
    // Setup: RabbitMQ, Producer, Consumer, Mock OneSignal
    // Publish notification via Message Usecase
    // Verify consumer processes and calls OneSignal
    // Verify message is ACKed and removed from queue
}

func TestIntegration_DLQRouting(t *testing.T) {
    // Setup with failing OneSignal (permanent error)
    // Publish notification
    // Verify message ends up in DLQ
}

func TestIntegration_RetryMechanism(t *testing.T) {
    // Setup with OneSignal that fails then succeeds
    // Publish notification
    // Verify retry and eventual success
}
```

### Test Configuration

```go
// Test RabbitMQ connection (use testcontainers for isolation)
const TestRabbitMQURL = "amqp://guest:guest@localhost:5672/"

// Property test iterations
const PropertyTestIterations = 100

// Test timeouts
const TestTimeout = 5 * time.Second
```

### Testing Tools

- **testify/assert**: Assertions and test utilities
- **testify/require**: Fatal assertions
- **testify/mock**: Mock implementations for OneSignalService
- **testcontainers-go**: Isolated RabbitMQ instances for integration tests
- Custom property test helpers for randomized input generation

### Coverage Goals

- Unit test coverage: > 80% for producer and consumer code
- Property tests: All 8 correctness properties implemented
- Integration tests: End-to-end flows and error scenarios
- Edge cases: Empty player IDs, malformed JSON, connection failures, shutdown scenarios

