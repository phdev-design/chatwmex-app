# Two-Device Sync Issues Bugfix Design

## Overview

This bugfix addresses two critical synchronization issues preventing proper multi-device functionality in the Flutter E2EE chat application. The first bug causes complete initialization failure when JWT tokens expire, leaving users with blank chat lists. The second bug incorrectly conflates message read status with decryption status, causing unnecessary re-encryption requests for already-decrypted messages. The fix implements automatic token refresh across all network layers and adds proper decryption state tracking in the local database.

## Glossary

- **Bug_Condition_1 (C1)**: JWT token has expired (typically after one week) and any network operation (WebSocket connection, API call, or initialization) receives a 401 Unauthorized response
- **Bug_Condition_2 (C2)**: Message has `status = MessageStatus.read` but lacks a separate `is_decrypted` field, causing the system to incorrectly assume the message is decrypted when it may not be
- **Property_1 (P1)**: When token expires, the system automatically refreshes the token and retries the failed operation without user intervention or data loss
- **Property_2 (P2)**: Messages are tracked with independent `is_decrypted` state, allowing the system to correctly identify which messages need re-encryption regardless of their read status
- **Preservation**: All existing authentication flows, message handling, and WebSocket behavior for valid tokens must remain unchanged
- **Token Refresh**: Process of obtaining a new JWT token using the existing (expired) token or refresh token mechanism
- **Dio Interceptor**: Middleware that intercepts HTTP requests/responses to add authentication headers and handle errors
- **WebSocket 401 Handler**: Logic that detects authentication failures on WebSocket connections and triggers reconnection
- **LocalDB Schema Migration**: Process of upgrading the SQLite database structure from version 5 to version 6 to add the `is_decrypted` column
- **E2EE Auto-Resend**: Mechanism that automatically requests message re-encryption when decryption fails, ensuring messages are recoverable across devices

## Bug Details

### Bug Condition 1: JWT Token Expiration

The first bug manifests when the JWT token expires (typically after one week of inactivity) and the app attempts any network operation. The system receives a 401 Unauthorized response but fails to attempt token refresh, instead immediately stopping all operations.

**Formal Specification:**
```
FUNCTION isBugCondition1(networkOperation)
  INPUT: networkOperation of type {WebSocketConnect | HttpRequest | InitializationFlow}
  OUTPUT: boolean
  
  RETURN networkOperation.response.statusCode == 401
         AND jwtToken.isExpired == true
         AND NOT tokenRefreshAttempted
         AND operationFailed == true
END FUNCTION
```

### Bug Condition 2: Read vs Decrypted Conflation

The second bug manifests when messages have been marked as read (`status = MessageStatus.read`) but the E2EE Auto-Resend logic uses this status field to determine whether to skip re-encryption requests, incorrectly assuming that read messages are also successfully decrypted.

**Formal Specification:**
```
FUNCTION isBugCondition2(message)
  INPUT: message of type Message
  OUTPUT: boolean
  
  RETURN message.status == MessageStatus.read
         AND message.content.startsWith("🔐 解密失敗")
         AND NOT EXISTS(message.is_decrypted)
         AND e2eeAutoResendSkipsMessage(message) == true
END FUNCTION
```

### Examples

**Bug 1 Examples:**
- User opens app after one week of inactivity → WebSocket connection receives 401 → System stops retry attempts → Chat list remains blank
- User switches to secondary device → SplashScreen initialization calls `/api/v1/rooms/my` → Receives 401 → DioException displayed → User cannot access app
- User sends message with expired token → API call fails with 401 → Message stuck in pending state → No automatic retry

**Bug 2 Examples:**
- Device A sends 30 messages to Device B → Device B receives messages but cannot decrypt (missing private key) → All 30 messages show "🔐 解密失敗" → Device B marks messages as read → E2EE Auto-Resend skips all 30 messages because `status = read` → Messages never recovered
- User restores private key on Device B → E2EE Auto-Resend initialization runs → Checks `status` field instead of `is_decrypted` → Skips messages that should be re-encrypted → User still sees "🔐 解密失敗"

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Valid token authentication must continue to work exactly as before (login, WebSocket connection, API calls)
- Messages that decrypt successfully on first attempt must continue to display correctly without re-encryption
- User logout flow must continue to clear tokens and disconnect WebSocket properly
- Message sending with valid tokens must continue to work without interference
- WebSocket connection stability with valid tokens must remain unchanged
- E2EE Auto-Resend for genuinely failed decryptions must continue to work correctly

**Scope:**
All inputs that do NOT involve expired tokens (Bug 1) or read-but-not-decrypted messages (Bug 2) should be completely unaffected by this fix. This includes:
- Normal login and authentication flows with valid credentials
- Message sending and receiving with valid tokens
- WebSocket connections that authenticate successfully
- Messages that decrypt successfully on first attempt
- User-initiated logout operations

## Hypothesized Root Cause

Based on the bug description and code analysis, the most likely issues are:

### Bug 1: JWT Token Expiration

1. **Missing Dio Interceptor Logic**: The `network_service.dart` file has a placeholder comment `// Trigger logout or refresh` in the `onError` handler for 401 responses, but no actual implementation exists to refresh the token and retry the request.

2. **No WebSocket 401 Handling**: The `websocket_service.dart` file does not detect 401 responses during WebSocket authentication and does not trigger token refresh before stopping retry attempts.

3. **No SplashScreen Error Recovery**: The `splash_screen.dart` file's `_loadHeavyDataInBackground()` method catches errors with `debugPrint` but does not attempt token refresh when 401 errors occur during initialization.

4. **Missing Token Refresh Method**: The `auth_provider.dart` file does not expose a `refreshToken()` method that can be called by the Dio interceptor, WebSocket service, or SplashScreen to obtain a new token.

### Bug 2: Read vs Decrypted Conflation

1. **Missing Database Column**: The `local_db_service.dart` schema (version 5) does not include an `is_decrypted` column in the messages table, making it impossible to track decryption state independently from read status.

2. **Incorrect Skip Logic**: The `chat_room_provider.dart` E2EE Auto-Resend initialization likely checks `message.status == MessageStatus.read` to decide whether to skip re-encryption, when it should check a separate `is_decrypted` field.

3. **No Decryption State Update**: When `re_encrypt_response` is received and decryption succeeds, the system updates `message.content` and `message.status` but does not set `is_decrypted = true`, perpetuating the conflation.

4. **Schema Migration Not Planned**: No migration path exists from version 5 to version 6 to add the `is_decrypted` column and backfill existing messages.

## Correctness Properties

Property 1: Bug Condition 1 - Automatic Token Refresh on 401

_For any_ network operation (WebSocket connection, HTTP request, or initialization flow) where the JWT token has expired and a 401 Unauthorized response is received, the fixed system SHALL automatically attempt to refresh the token using the refresh mechanism, retry the original operation with the new token, and only display an error to the user if the refresh itself fails.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

Property 2: Bug Condition 2 - Independent Decryption State Tracking

_For any_ message where the decryption status needs to be determined, the fixed system SHALL check the `is_decrypted` column (not the `status` column) to decide whether to send a re_encrypt_request, ensuring that read-but-not-decrypted messages are correctly identified and recovered.

**Validates: Requirements 2.5, 2.6, 2.7, 2.8**

Property 3: Preservation - Valid Token Operations

_For any_ network operation where the JWT token is valid and not expired, the fixed system SHALL produce exactly the same behavior as the original system, preserving all existing authentication flows, message handling, and WebSocket connection behavior.

**Validates: Requirements 3.1, 3.2, 3.3, 3.7, 3.8, 3.9**

Property 4: Preservation - E2EE Auto-Resend for Genuine Failures

_For any_ message where decryption genuinely fails and `is_decrypted = false`, the fixed system SHALL continue to send re_encrypt_request and handle re_encrypt_response exactly as the original system, preserving the E2EE Auto-Resend recovery mechanism.

**Validates: Requirements 3.4, 3.5, 3.6**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File 1**: `app/lib/features/auth/providers/auth_provider.dart`

**Function**: Add `refreshToken()` method to `AuthViewModel`

**Specific Changes**:
1. **Add Token Refresh Method**: Implement `Future<bool> refreshToken()` that calls the backend `/api/v1/auth/refresh` endpoint (or equivalent) with the current expired token, receives a new token, saves it to storage, and returns true on success.
   - Extract current token from `StorageService`
   - Make POST request to refresh endpoint
   - Save new token to storage
   - Update App Group token for iOS notification extension
   - Return true if successful, false if refresh fails

2. **Add Refresh Lock**: Implement a `_refreshLock` mutex to prevent multiple simultaneous refresh attempts when multiple 401 errors occur concurrently.

**File 2**: `app/lib/core/network/network_service.dart`

**Function**: `onError` handler in Dio interceptor

**Specific Changes**:
1. **Implement 401 Handler**: Replace the placeholder comment with actual token refresh logic:
   - Detect `e.response?.statusCode == 401`
   - Call `ref.read(authViewModelProvider.notifier).refreshToken()`
   - If refresh succeeds, clone the original request with new token and retry using `handler.resolve()`
   - If refresh fails, proceed with error using `handler.next(e)`

2. **Add Refresh Lock Check**: Ensure only one refresh attempt happens at a time by checking the refresh lock before attempting refresh.

3. **Add Retry Logic**: Clone the failed request options, update the Authorization header with the new token, and retry the request using `_dio.fetch(options)`.

**File 3**: `app/lib/core/websocket/websocket_service.dart`

**Function**: WebSocket connection and authentication handling

**Specific Changes**:
1. **Add 401 Detection**: In the WebSocket message handler, detect when the server sends a 401 authentication failure message (likely in the initial handshake or as a specific error message format).

2. **Trigger Token Refresh**: When 401 is detected, call `ref.read(authViewModelProvider.notifier).refreshToken()` before stopping retry attempts.

3. **Retry Connection**: If token refresh succeeds, attempt to reconnect the WebSocket with the new token instead of immediately stopping retries.

4. **Fallback to Error**: Only display connection error to user if token refresh fails or max retries are exceeded.

**File 4**: `app/lib/features/splash/ui/splash_screen.dart`

**Function**: `_loadHeavyDataInBackground()` method

**Specific Changes**:
1. **Add 401 Error Detection**: Wrap the initialization calls in a try-catch that specifically detects `DioException` with `response?.statusCode == 401`.

2. **Attempt Token Refresh**: When 401 is detected, call `ref.read(authViewModelProvider.notifier).refreshToken()` and retry the initialization sequence.

3. **Retry Initialization**: If token refresh succeeds, recursively call `_loadHeavyDataInBackground()` to retry the initialization with the new token.

4. **Graceful Degradation**: If token refresh fails, log the user out and redirect to login screen instead of showing a generic error.

**File 5**: `app/lib/core/storage/local_db_service.dart`

**Function**: Database schema and migration

**Specific Changes**:
1. **Bump Database Version**: Change `version: 5` to `version: 6` in the `_openDatabase()` method.

2. **Add is_decrypted Column**: In `_createMessagesTable()`, add `'is_decrypted INTEGER DEFAULT 0, '` to the CREATE TABLE statement.

3. **Update Migration Logic**: In `onUpgrade()`, add a check for `oldVersion < 6` and execute `ALTER TABLE messages ADD COLUMN is_decrypted INTEGER DEFAULT 0` to add the column to existing databases.

4. **Update _ensureMessagesColumns**: Add `'is_decrypted': 'ALTER TABLE messages ADD COLUMN is_decrypted INTEGER DEFAULT 0'` to the `missing` map to ensure the column exists even if migration is skipped.

5. **Add Helper Methods**: Implement `Future<void> markMessageAsDecrypted(String messageId)` to set `is_decrypted = 1` when decryption succeeds, and `Future<List<Message>> getUndecryptedMessages()` to retrieve messages where `is_decrypted = 0`.

**File 6**: `app/lib/features/chat/providers/chat_room_provider.dart`

**Function**: E2EE Auto-Resend initialization logic

**Specific Changes**:
1. **Update Skip Logic**: Change the condition that checks `message.status == MessageStatus.read` to instead check `message.isDecrypted == true` (assuming the Message model is updated to include this field).

2. **Update Message Model**: Ensure the `Message` model in `app/lib/models/message.dart` includes an `isDecrypted` boolean field that maps to the `is_decrypted` column in the database.

3. **Update Decryption Success Handler**: When `re_encrypt_response` is received and decryption succeeds, call `localDbService.markMessageAsDecrypted(messageId)` to set `is_decrypted = 1` in the database.

4. **Update Initialization Query**: Change the E2EE Auto-Resend initialization to query `localDbService.getUndecryptedMessages()` instead of filtering by status.

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate both bugs on unfixed code, then verify the fixes work correctly and preserve existing behavior. Testing will cover token expiration scenarios across all network layers and message decryption state tracking across device synchronization scenarios.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate both bugs BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan for Bug 1**: Manually expire the JWT token (or wait one week), then attempt various network operations (WebSocket connection, API calls, app initialization) and observe that they fail with 401 without attempting token refresh. Run these tests on the UNFIXED code to observe failures and understand the root cause.

**Test Cases for Bug 1**:
1. **Expired Token WebSocket Test**: Set JWT token to an expired value, attempt WebSocket connection, observe 401 response and immediate retry stop (will fail on unfixed code)
2. **Expired Token API Call Test**: Set JWT token to an expired value, call `/api/v1/rooms/my`, observe 401 response without retry (will fail on unfixed code)
3. **Expired Token Splash Test**: Set JWT token to an expired value, launch app and observe SplashScreen initialization failure with DioException (will fail on unfixed code)
4. **Valid Token Test**: Use a valid token for all operations, observe successful authentication (should pass on unfixed code - preservation check)

**Test Plan for Bug 2**: Create a scenario where Device B receives 30 encrypted messages but cannot decrypt them (simulate missing private key), mark all messages as read, then observe that E2EE Auto-Resend skips all messages despite them showing "🔐 解密失敗". Run these tests on the UNFIXED code to observe the conflation bug.

**Test Cases for Bug 2**:
1. **Read But Not Decrypted Test**: Create messages with `status = MessageStatus.read` and `content = "🔐 解密失敗"`, run E2EE Auto-Resend initialization, observe that messages are skipped (will fail on unfixed code)
2. **Database Schema Test**: Query the messages table schema, observe that `is_decrypted` column does not exist (will fail on unfixed code)
3. **Decryption Success Test**: Simulate successful decryption, observe that only `content` and `status` are updated, not a separate `is_decrypted` field (will fail on unfixed code)
4. **Genuine Decryption Failure Test**: Create messages that genuinely fail decryption, observe that E2EE Auto-Resend correctly sends re_encrypt_request (should pass on unfixed code - preservation check)

**Expected Counterexamples**:
- Bug 1: Network operations fail with 401 and no token refresh is attempted, leaving users unable to access the app
- Bug 2: Messages with `status = read` are skipped by E2EE Auto-Resend even when they are not decrypted, preventing message recovery
- Possible causes: Missing Dio interceptor logic, no WebSocket 401 handler, missing database column, incorrect skip logic in E2EE Auto-Resend

### Fix Checking

**Goal**: Verify that for all inputs where the bug conditions hold, the fixed functions produce the expected behavior.

**Pseudocode for Bug 1:**
```
FOR ALL networkOperation WHERE isBugCondition1(networkOperation) DO
  result := performNetworkOperation_fixed(networkOperation)
  ASSERT result.tokenRefreshAttempted == true
  ASSERT result.operationRetried == true
  ASSERT (result.success == true) OR (result.refreshFailed == true AND result.userNotified == true)
END FOR
```

**Pseudocode for Bug 2:**
```
FOR ALL message WHERE isBugCondition2(message) DO
  result := e2eeAutoResendInitialization_fixed(message)
  ASSERT result.messageSkipped == false
  ASSERT result.reEncryptRequestSent == true
  ASSERT message.isDecrypted == false
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug conditions do NOT hold, the fixed functions produce the same result as the original functions.

**Pseudocode for Bug 1:**
```
FOR ALL networkOperation WHERE NOT isBugCondition1(networkOperation) DO
  ASSERT performNetworkOperation_original(networkOperation) = performNetworkOperation_fixed(networkOperation)
END FOR
```

**Pseudocode for Bug 2:**
```
FOR ALL message WHERE NOT isBugCondition2(message) DO
  ASSERT e2eeAutoResendInitialization_original(message) = e2eeAutoResendInitialization_fixed(message)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain (various token states, message states, network conditions)
- It catches edge cases that manual unit tests might miss (concurrent 401 errors, race conditions, partial decryption)
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs (valid tokens, successfully decrypted messages)

**Test Plan**: Observe behavior on UNFIXED code first for valid token operations and successfully decrypted messages, then write property-based tests capturing that behavior.

**Test Cases for Preservation**:
1. **Valid Token Preservation**: Observe that login, WebSocket connection, and API calls work correctly with valid tokens on unfixed code, then write tests to verify this continues after fix
2. **Message Sending Preservation**: Observe that message sending works correctly with valid tokens on unfixed code, then write tests to verify this continues after fix
3. **Successful Decryption Preservation**: Observe that messages that decrypt successfully on first attempt display correctly on unfixed code, then write tests to verify this continues after fix
4. **Logout Preservation**: Observe that user logout clears tokens and disconnects WebSocket on unfixed code, then write tests to verify this continues after fix

### Unit Tests

- Test `refreshToken()` method in isolation with mock backend responses (success, failure, network error)
- Test Dio interceptor 401 handler with various error scenarios (401, 403, 500, network timeout)
- Test WebSocket 401 detection and reconnection logic with mock WebSocket server
- Test SplashScreen initialization retry logic with mock API responses
- Test database migration from version 5 to version 6 with sample data
- Test `markMessageAsDecrypted()` and `getUndecryptedMessages()` methods in isolation
- Test E2EE Auto-Resend skip logic with various message states (read/unread, decrypted/not decrypted)

### Property-Based Tests

- Generate random token expiration scenarios (expired, valid, missing) and verify correct handling across all network layers
- Generate random message states (status, is_decrypted combinations) and verify E2EE Auto-Resend correctly identifies which messages need re-encryption
- Generate random concurrent 401 errors and verify only one token refresh attempt occurs (refresh lock test)
- Generate random database migration scenarios (version 4→6, 5→6, fresh install) and verify schema correctness
- Test that all non-expired token operations continue to work across many scenarios (preservation)

### Integration Tests

- Test full flow: expire token → open app → observe automatic token refresh → verify chat list loads correctly
- Test full flow: Device A sends messages → Device B receives but cannot decrypt → mark as read → restore private key → verify E2EE Auto-Resend recovers all messages
- Test multi-device scenario: expire token on Device A → send message from Device B → verify Device A refreshes token and receives message
- Test WebSocket reconnection: expire token during active session → send message → verify WebSocket reconnects with new token and message is delivered
- Test database migration: install app with version 5 schema → upgrade to version 6 → verify `is_decrypted` column exists and existing messages have default value
- Test concurrent operations: trigger multiple 401 errors simultaneously → verify only one token refresh occurs → verify all operations retry successfully
