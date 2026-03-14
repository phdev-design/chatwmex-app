# Bugfix Requirements Document

## Introduction

Testing with two iPhone 16 simulators revealed critical synchronization issues that prevent proper multi-device functionality in the Flutter E2EE chat application:

- **iPhone 16e**: Displays completely blank chat list due to expired JWT token causing initialization failure
- **iPhone 16 (test2)**: Shows all 30 messages with "🔐 解密失敗" (decryption failed) due to incorrect logic conflating `is_read` and `is_decrypted` states

These bugs prevent users from accessing their chat history on secondary devices and after token expiration, severely impacting the multi-device user experience.

## Bug Analysis

### Current Behavior (Defect)

**Bug 1: JWT Token Expiration Causes Complete Initialization Failure**

1.1 WHEN JWT token expires (e.g., after one week) and app attempts WebSocket connection THEN the system receives 401 response and immediately stops all retry attempts without attempting token refresh

1.2 WHEN WebSocket authentication fails with 401 THEN the entire initialization flow is interrupted, resulting in blank chat list with no conversations visible

1.3 WHEN expired token is used for API calls (e.g., GET /api/v1/rooms/my, PUT /api/v1/users/public_key) THEN all requests fail with 401 and no automatic token refresh is attempted

1.4 WHEN SplashScreen initialization encounters 401 errors THEN the app displays DioException without fallback handling, leaving user unable to access any functionality

**Bug 2: Message Read Status Conflated with Decryption Status**

1.5 WHEN E2EE Auto-Resend initialization loads messages from LocalDB THEN the system skips all 30 messages because their status is MessageStatus.read, even though they are not successfully decrypted

1.6 WHEN messages with MessageStatus.read are not decrypted THEN the system immediately sends re_encrypt_request for all 30 messages after claiming to skip them, revealing contradictory logic

1.7 WHEN LocalDB schema lacks is_decrypted column THEN the system cannot distinguish between "message has been read" and "message has been successfully decrypted", causing incorrect skip logic

1.8 WHEN re_encrypt_response is received and decryption succeeds THEN the system updates message status but does not mark the message as decrypted in a separate field, perpetuating the conflation

### Expected Behavior (Correct)

**Bug 1: JWT Token Expiration Should Trigger Automatic Refresh**

2.1 WHEN JWT token expires and WebSocket connection receives 401 THEN the system SHALL attempt to refresh the token before stopping retry attempts

2.2 WHEN any API call receives 401 response THEN Dio interceptor SHALL automatically refresh the token and retry the original request

2.3 WHEN WebSocket authentication fails with 401 THEN the system SHALL refresh the token and attempt reconnection with the new token before displaying error to user

2.4 WHEN SplashScreen initialization encounters 401 errors THEN the system SHALL handle the error gracefully by attempting token refresh and retrying initialization, only showing error if refresh fails

**Bug 2: Decryption Status Should Be Tracked Independently**

2.5 WHEN E2EE Auto-Resend initialization loads messages from LocalDB THEN the system SHALL check the is_decrypted field (not status field) to determine whether to skip the message

2.6 WHEN messages have is_decrypted = false THEN the system SHALL send re_encrypt_request regardless of the message status (read/delivered/sent)

2.7 WHEN LocalDB is upgraded to version 6 THEN the system SHALL add is_decrypted column (boolean, default false) to the messages table

2.8 WHEN re_encrypt_response is received and decryption succeeds THEN the system SHALL set is_decrypted = true in LocalDB to prevent future unnecessary re-encryption requests

### Unchanged Behavior (Regression Prevention)

**General Message Handling**

3.1 WHEN messages are successfully decrypted on first attempt THEN the system SHALL CONTINUE TO display message content correctly without requiring re-encryption

3.2 WHEN user sends a new message THEN the system SHALL CONTINUE TO encrypt and send the message normally without interference from token refresh logic

3.3 WHEN WebSocket connection is stable and token is valid THEN the system SHALL CONTINUE TO maintain connection without unnecessary reconnection attempts

**E2EE Auto-Resend Mechanism**

3.4 WHEN message genuinely fails decryption and is_decrypted = false THEN the system SHALL CONTINUE TO send re_encrypt_request to recover the message

3.5 WHEN re_encrypt_request is received by sender THEN the system SHALL CONTINUE TO fetch original message from LocalDB and send re_encrypt_response

3.6 WHEN message retry count exceeds limit THEN the system SHALL CONTINUE TO mark message as failed and stop retry attempts

**Authentication Flow**

3.7 WHEN user logs in with valid credentials THEN the system SHALL CONTINUE TO receive valid JWT token and establish WebSocket connection successfully

3.8 WHEN token is valid and not expired THEN the system SHALL CONTINUE TO use existing token without unnecessary refresh attempts

3.9 WHEN user explicitly logs out THEN the system SHALL CONTINUE TO clear token and disconnect WebSocket properly
