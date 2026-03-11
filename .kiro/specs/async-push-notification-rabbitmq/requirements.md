# Requirements Document

## Introduction

This document specifies the requirements for refactoring the push notification system in a chat application backend to use RabbitMQ for asynchronous processing. Currently, push notifications via OneSignal are executed synchronously, blocking the main API and WebSocket flows. The refactored system will decouple notification delivery from the main request flow, improving system performance and responsiveness.

## Glossary

- **Notification_System**: The complete push notification subsystem including producer, consumer, and message broker
- **RabbitMQ_Producer**: The component that publishes notification messages to the RabbitMQ queue
- **RabbitMQ_Consumer**: The worker component that consumes notification messages from the queue and processes them
- **OneSignal_Service**: The external service integration that delivers push notifications to mobile devices
- **Message_Usecase**: The business logic layer that handles chat message operations
- **Notification_Queue**: The RabbitMQ queue named "notification_queue" used for notification messages
- **PushNotificationMessage**: The data structure containing PlayerIDs, Title, Content, and Data fields
- **Dead_Letter_Queue**: A RabbitMQ queue that stores messages that failed processing after retry attempts
- **Main_Application**: The primary API and WebSocket server process

## Requirements

### Requirement 1: Message Payload Structure

**User Story:** As a developer, I want a well-defined notification message structure, so that notification data is consistently formatted across the system.

#### Acceptance Criteria

1. THE Notification_System SHALL define a PushNotificationMessage structure with PlayerIDs field of type array of strings
2. THE Notification_System SHALL define a PushNotificationMessage structure with Title field of type string
3. THE Notification_System SHALL define a PushNotificationMessage structure with Content field of type string
4. THE Notification_System SHALL define a PushNotificationMessage structure with Data field of type map of string to interface

### Requirement 2: RabbitMQ Connection Management

**User Story:** As a system administrator, I want RabbitMQ connections to be properly managed, so that the system maintains reliable message broker connectivity.

#### Acceptance Criteria

1. WHEN the Main_Application starts, THE Notification_System SHALL establish a connection to RabbitMQ using the configured RabbitMQURL
2. WHEN the RabbitMQ connection fails, THE Notification_System SHALL log the connection error with details
3. WHEN the Main_Application shuts down, THE Notification_System SHALL close all RabbitMQ connections gracefully
4. THE Notification_System SHALL declare the Notification_Queue as durable during initialization

### Requirement 3: Asynchronous Notification Publishing

**User Story:** As a backend developer, I want to publish notifications asynchronously, so that message sending does not block the main application flow.

#### Acceptance Criteria

1. WHEN the Message_Usecase needs to send a push notification, THE RabbitMQ_Producer SHALL publish a PushNotificationMessage to the Notification_Queue
2. WHEN publishing a message, THE RabbitMQ_Producer SHALL serialize the PushNotificationMessage to JSON format
3. WHEN publishing fails, THE RabbitMQ_Producer SHALL log the error and return an error to the caller
4. WHEN publishing succeeds, THE RabbitMQ_Producer SHALL return without waiting for notification delivery

### Requirement 4: Notification Message Consumption

**User Story:** As a system operator, I want a worker to process notifications from the queue, so that notifications are delivered asynchronously without blocking the API.

#### Acceptance Criteria

1. WHEN the Main_Application starts, THE RabbitMQ_Consumer SHALL begin listening to the Notification_Queue
2. WHEN a message is received, THE RabbitMQ_Consumer SHALL deserialize the JSON payload into a PushNotificationMessage
3. WHEN deserialization succeeds, THE RabbitMQ_Consumer SHALL invoke the OneSignal_Service with the message data
4. WHEN the OneSignal_Service successfully delivers the notification, THE RabbitMQ_Consumer SHALL acknowledge the message
5. WHEN deserialization fails, THE RabbitMQ_Consumer SHALL log the error and negatively acknowledge the message without requeue

### Requirement 5: Error Handling and Retry Logic

**User Story:** As a system operator, I want failed notifications to be retried appropriately, so that transient failures do not result in lost notifications.

#### Acceptance Criteria

1. WHEN the OneSignal_Service returns a transient error, THE RabbitMQ_Consumer SHALL negatively acknowledge the message with requeue enabled
2. WHEN a message fails processing after maximum retry attempts, THE RabbitMQ_Consumer SHALL route the message to the Dead_Letter_Queue
3. WHEN any error occurs during message processing, THE RabbitMQ_Consumer SHALL log the error with message details and error context
4. THE Notification_Queue SHALL be configured with a Dead_Letter_Queue for failed messages

### Requirement 6: Message Usecase Integration

**User Story:** As a backend developer, I want the message usecase to use the new asynchronous notification system, so that message operations complete quickly without waiting for push notifications.

#### Acceptance Criteria

1. WHEN the Message_Usecase needs to send a notification, THE Message_Usecase SHALL call the RabbitMQ_Producer instead of the OneSignal_Service directly
2. WHEN the RabbitMQ_Producer returns an error, THE Message_Usecase SHALL log the error but continue processing the message operation
3. THE Message_Usecase SHALL NOT wait for notification delivery confirmation before completing the message operation

### Requirement 7: System Initialization and Lifecycle

**User Story:** As a system administrator, I want the notification system to initialize properly on startup, so that the application is ready to process notifications.

#### Acceptance Criteria

1. WHEN the Main_Application starts, THE Notification_System SHALL initialize the RabbitMQ connection before accepting API requests
2. WHEN the Main_Application starts, THE Notification_System SHALL start the RabbitMQ_Consumer worker in a separate goroutine
3. WHEN initialization fails, THE Main_Application SHALL log the error and exit with a non-zero status code
4. WHEN the Main_Application receives a shutdown signal, THE Notification_System SHALL stop accepting new messages before closing connections

### Requirement 8: Configuration Integration

**User Story:** As a system administrator, I want to configure the RabbitMQ connection via the existing config file, so that deployment settings can be managed centrally.

#### Acceptance Criteria

1. THE Notification_System SHALL read the RabbitMQ connection URL from the existing RabbitMQURL configuration field
2. THE Notification_System SHALL use the queue name "notification_queue" for all notification message operations
3. WHERE the RabbitMQURL is not configured, THE Main_Application SHALL log an error and fail to start

