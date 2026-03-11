# Implementation Plan: Async Push Notification with RabbitMQ

## Overview

This implementation refactors the push notification system to use RabbitMQ for asynchronous processing. The work involves creating a producer-consumer pattern where notification messages are published to a dedicated RabbitMQ queue and processed by a separate worker, decoupling notification delivery from the main API flow.

## Tasks

- [x] 1. Define domain models and interfaces
  - [x] 1.1 Add PushNotificationMessage struct to domain layer
    - Add struct with PlayerIDs, Title, Content, and Data fields to `internal/domain/notification.go`
    - Include JSON tags for serialization
    - _Requirements: 1.1, 1.2, 1.3, 1.4_
  
  - [x] 1.2 Add NotificationProducer interface to domain layer
    - Define interface with Publish() and Close() methods in `internal/domain/notification.go`
    - _Requirements: 3.1, 3.4_

- [x] 2. Implement RabbitMQ producer
  - [x] 2.1 Create NotificationProducerImpl in infrastructure layer
    - Create `internal/infrastructure/rabbitmq/notification_producer.go`
    - Implement struct with connection, channel, and queueName fields
    - Implement NewNotificationProducer constructor with queue declaration
    - Declare notification_queue as durable with DLQ configuration
    - _Requirements: 2.1, 2.4, 3.1, 5.4, 8.2_
  
  - [x] 2.2 Implement Publish method for producer
    - Serialize PushNotificationMessage to JSON
    - Publish to notification_queue with persistent delivery mode
    - Return immediately without waiting for consumer processing
    - Log errors on serialization or publishing failures
    - _Requirements: 3.1, 3.2, 3.3, 3.4_
  
  - [x] 2.3 Implement Close method for producer
    - Gracefully close channel and connection
    - _Requirements: 2.3_
  
  - [ ]* 2.4 Write property test for producer serialization
    - **Property 1: Notification Message Serialization Round-Trip**
    - **Validates: Requirements 3.2, 4.2**
  
  - [ ]* 2.5 Write property test for non-blocking publish
    - **Property 2: Asynchronous Publishing Non-Blocking**
    - **Validates: Requirements 3.4, 6.3**
  
  - [ ]* 2.6 Write unit tests for producer error handling
    - Test serialization errors
    - Test publishing failures with closed connection
    - Test graceful shutdown
    - _Requirements: 3.3_

- [x] 3. Implement RabbitMQ consumer worker
  - [x] 3.1 Create NotificationConsumer in infrastructure layer
    - Create `internal/infrastructure/rabbitmq/notification_consumer.go`
    - Implement struct with connection, channel, queueName, oneSignalService, and maxRetries fields
    - Implement NewNotificationConsumer constructor
    - _Requirements: 4.1, 5.1_
  
  - [x] 3.2 Implement Start method for consumer
    - Begin consuming from notification_queue
    - Deserialize JSON messages to PushNotificationMessage
    - Call OneSignalService.SendNotificationToDevices()
    - Implement ACK/NACK logic based on result
    - Handle context cancellation for graceful shutdown
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  
  - [x] 3.3 Implement error handling and retry logic
    - Distinguish transient vs permanent errors
    - NACK with requeue for transient errors (network timeouts, 5xx)
    - NACK without requeue for permanent errors (4xx, deserialization failures)
    - Track retry count via x-death headers
    - Route to DLQ after max retries exceeded
    - Log all errors with message details and context
    - _Requirements: 5.1, 5.2, 5.3_
  
  - [x] 3.4 Implement Stop method for consumer
    - Stop consuming messages
    - Close channel and connection gracefully
    - _Requirements: 2.3, 7.4_
  
  - [ ]* 3.5 Write property test for message queue delivery
    - **Property 3: Message Queue Delivery**
    - **Validates: Requirements 3.1, 4.1, 4.2**
  
  - [ ]* 3.6 Write property test for successful delivery acknowledgment
    - **Property 4: Successful Delivery Acknowledgment**
    - **Validates: Requirements 4.3, 4.4**
  
  - [ ]* 3.7 Write property test for transient error retry
    - **Property 5: Transient Error Retry**
    - **Validates: Requirements 5.1**
  
  - [ ]* 3.8 Write property test for error logging
    - **Property 6: Error Logging on Failure**
    - **Validates: Requirements 3.3, 5.3**
  
  - [ ]* 3.9 Write property test for consumer invokes OneSignal
    - **Property 8: Consumer Invokes OneSignal**
    - **Validates: Requirements 4.3**
  
  - [ ]* 3.10 Write unit tests for consumer edge cases
    - Test malformed JSON deserialization
    - Test empty PlayerIDs validation
    - Test max retries exceeded
    - Test graceful shutdown with context cancellation
    - _Requirements: 4.5, 5.2, 7.4_

- [ ] 4. Checkpoint - Ensure producer and consumer tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Integrate producer into Message Usecase
  - [x] 5.1 Add NotificationProducer field to messageUsecase struct
    - Modify `internal/usecase/message_usecase.go`
    - Add notificationProducer field of type domain.NotificationProducer
    - Update NewMessageUsecase constructor to accept NotificationProducer parameter
    - _Requirements: 6.1_
  
  - [x] 5.2 Implement buildPushNotificationMessage helper method
    - Query device repository to collect player IDs from user IDs
    - Build title and content from message data
    - Create data payload with room_id, is_room, encrypted_content, sender_id, message_id
    - Return PushNotificationMessage struct
    - _Requirements: 1.1, 1.2, 1.3, 1.4_
  
  - [x] 5.3 Refactor SendMessage to use NotificationProducer
    - Replace direct OneSignal calls with NotificationProducer.Publish()
    - Build PushNotificationMessage using helper method
    - Log errors but continue processing if publishing fails
    - Do not wait for notification delivery confirmation
    - _Requirements: 6.1, 6.2, 6.3_
  
  - [ ]* 5.4 Write property test for graceful degradation
    - **Property 7: Graceful Degradation**
    - **Validates: Requirements 6.2**
  
  - [ ]* 5.5 Write unit tests for Message Usecase integration
    - Test successful notification publishing
    - Test message operation succeeds when publishing fails
    - Test buildPushNotificationMessage with various inputs
    - _Requirements: 6.1, 6.2, 6.3_

- [x] 6. Wire components in main application
  - [x] 6.1 Initialize NotificationProducer in main.go
    - Create producer after RabbitMQ connection check
    - Pass config to NewNotificationProducer
    - Handle initialization errors with fatal log
    - Register producer for graceful shutdown
    - _Requirements: 2.1, 7.1, 7.3, 8.1_
  
  - [x] 6.2 Initialize NotificationConsumer in main.go
    - Create consumer with config and OneSignal service
    - Start consumer in separate goroutine
    - Handle initialization errors with fatal log
    - _Requirements: 4.1, 7.1, 7.2, 7.3_
  
  - [x] 6.3 Update MessageUsecase initialization
    - Pass NotificationProducer to NewMessageUsecase
    - _Requirements: 6.1_
  
  - [x] 6.4 Implement graceful shutdown for notification system
    - Stop consumer before closing connections
    - Close producer connection
    - Ensure shutdown completes within timeout
    - _Requirements: 2.3, 7.4_
  
  - [x]* 6.5 Write integration test for end-to-end notification flow
    - Setup RabbitMQ, producer, consumer, and mock OneSignal
    - Publish notification via Message Usecase
    - Verify consumer processes and calls OneSignal
    - Verify message is ACKed and removed from queue
    - _Requirements: 3.1, 4.1, 4.3, 4.4_
  
  - [ ]* 6.6 Write integration test for DLQ routing
    - Setup with failing OneSignal (permanent error)
    - Publish notification
    - Verify message ends up in DLQ after NACK
    - _Requirements: 5.2, 5.4_

- [x] 7. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- The implementation follows Clean Architecture with clear separation between domain, application, and infrastructure layers
- Property tests validate universal correctness properties across randomized inputs
- Unit tests validate specific examples, edge cases, and error conditions
- Integration tests validate end-to-end flows and component interactions
- The consumer worker runs in a separate goroutine for true asynchronous processing
- Dead Letter Queue configuration ensures failed notifications are not lost
- Graceful shutdown ensures in-flight messages are processed before termination
