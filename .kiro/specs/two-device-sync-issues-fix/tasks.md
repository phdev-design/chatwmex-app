# Implementation Plan

- [x] 1. Write bug condition exploration tests
  - **Property 1: Bug Condition** - JWT Token Expiration and Read vs Decrypted Conflation
  - **CRITICAL**: These tests MUST FAIL on unfixed code - failure confirms the bugs exist
  - **DO NOT attempt to fix the tests or the code when they fail**
  - **NOTE**: These tests encode the expected behavior - they will validate the fixes when they pass after implementation
  - **GOAL**: Surface counterexamples that demonstrate both bugs exist
  - **Scoped PBT Approach**: Scope properties to concrete failing cases for reproducibility
  
  - [x] 1.1 Bug 1: Expired Token WebSocket Test
    - Set JWT token to an expired value in storage
    - Attempt WebSocket connection via `websocket_service.dart`
    - Assert that 401 response is received
    - Assert that token refresh is NOT attempted (will fail - confirms bug)
    - Assert that retry attempts stop immediately (will fail - confirms bug)
    - Document counterexample: "WebSocket connection with expired token fails without refresh attempt"
    - _Requirements: 2.1_
  
  - [x] 1.2 Bug 1: Expired Token API Call Test
    - Set JWT token to an expired value in storage
    - Call `/api/v1/rooms/my` via `network_service.dart`
    - Assert that 401 DioException is thrown
    - Assert that token refresh is NOT attempted (will fail - confirms bug)
    - Assert that request is NOT retried (will fail - confirms bug)
    - Document counterexample: "API call with expired token fails without refresh attempt"
    - _Requirements: 2.2_
  
  - [x] 1.3 Bug 1: Expired Token Splash Test
    - Set JWT token to an expired value in storage
    - Launch app and trigger `_loadHeavyDataInBackground()` in splash_screen.dart
    - Assert that initialization fails with DioException
    - Assert that token refresh is NOT attempted (will fail - confirms bug)
    - Assert that user sees error instead of automatic recovery (will fail - confirms bug)
    - Document counterexample: "SplashScreen initialization with expired token fails without refresh attempt"
    - _Requirements: 2.4_
  
  - [x] 1.4 Bug 2: Read But Not Decrypted Test
    - Create test messages with `status = MessageStatus.read` and `content = "🔐 解密失敗"`
    - Insert messages into local database via `local_db_service.dart`
    - Run E2EE Auto-Resend initialization in `chat_room_provider.dart`
    - Assert that messages are skipped (will fail - confirms bug)
    - Assert that no re_encrypt_request is sent (will fail - confirms bug)
    - Document counterexample: "Read but undecrypted messages are skipped by E2EE Auto-Resend"
    - _Requirements: 2.5_
  
  - [x] 1.5 Bug 2: Database Schema Test
    - Query the messages table schema in `local_db_service.dart`
    - Assert that `is_decrypted` column does NOT exist (will fail - confirms bug)
    - Assert that only `status` column is available for tracking state (will fail - confirms bug)
    - Document counterexample: "Database schema lacks is_decrypted column for independent state tracking"
    - _Requirements: 2.6_
  
  - [x] 1.6 Bug 2: Decryption Success Handler Test
    - Simulate receiving `re_encrypt_response` with successfully decrypted content
    - Observe message update in `chat_room_provider.dart`
    - Assert that only `content` and `status` are updated (will fail - confirms bug)
    - Assert that no separate `is_decrypted` field is set (will fail - confirms bug)
    - Document counterexample: "Decryption success does not mark message as decrypted independently"
    - _Requirements: 2.7_
  
  - [x] 1.7 Run all exploration tests on UNFIXED code
    - **EXPECTED OUTCOME**: All tests FAIL (this is correct - it proves the bugs exist)
    - Mark task complete when all tests are written, run, and failures are documented

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Valid Token Operations and Genuine Decryption Failures
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-buggy inputs
  - Write property-based tests capturing observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  
  - [x] 2.1 Valid Token Authentication Preservation
    - Observe: Login with valid credentials succeeds on unfixed code
    - Observe: WebSocket connection with valid token succeeds on unfixed code
    - Observe: API calls with valid token succeed on unfixed code
    - Write property-based test: for all operations with valid tokens, authentication succeeds
    - Verify test passes on UNFIXED code
    - _Requirements: 3.1, 3.7_
  
  - [x] 2.2 Message Sending Preservation
    - Observe: Sending messages with valid token succeeds on unfixed code
    - Observe: Messages are delivered and stored correctly on unfixed code
    - Write property-based test: for all message sends with valid tokens, delivery succeeds
    - Verify test passes on UNFIXED code
    - _Requirements: 3.2, 3.8_
  
  - [x] 2.3 Successful Decryption Preservation
    - Observe: Messages that decrypt successfully on first attempt display correctly on unfixed code
    - Observe: No re_encrypt_request is sent for successfully decrypted messages on unfixed code
    - Write property-based test: for all messages that decrypt successfully, content displays without re-encryption
    - Verify test passes on UNFIXED code
    - _Requirements: 3.3, 3.4_
  
  - [x] 2.4 Logout Flow Preservation
    - Observe: User logout clears tokens from storage on unfixed code
    - Observe: WebSocket disconnects properly on logout on unfixed code
    - Write property-based test: for all logout operations, tokens are cleared and connections closed
    - Verify test passes on UNFIXED code
    - _Requirements: 3.9_
  
  - [x] 2.5 E2EE Auto-Resend for Genuine Failures Preservation
    - Observe: Messages that genuinely fail decryption trigger re_encrypt_request on unfixed code
    - Observe: re_encrypt_response is handled correctly on unfixed code
    - Write property-based test: for all genuinely failed decryptions, E2EE Auto-Resend recovery works
    - Verify test passes on UNFIXED code
    - _Requirements: 3.5, 3.6_
  
  - [x] 2.6 Run all preservation tests on UNFIXED code
    - **EXPECTED OUTCOME**: All tests PASS (this confirms baseline behavior to preserve)
    - Mark task complete when all tests are written, run, and passing on unfixed code

- [x] 3. Fix for Bug 1: JWT Token Expiration

  - [x] 3.1 Add refreshToken() method to AuthViewModel
    - Open `app/lib/features/auth/providers/auth_provider.dart`
    - Add `Future<bool> refreshToken()` method to `AuthViewModel` class
    - Extract current token from `StorageService`
    - Make POST request to `/api/v1/auth/refresh` endpoint (or equivalent)
    - Save new token to storage on success
    - Update App Group token for iOS notification extension
    - Return true if successful, false if refresh fails
    - Add `_refreshLock` mutex to prevent concurrent refresh attempts
    - _Bug_Condition: isBugCondition1(networkOperation) where networkOperation.response.statusCode == 401 AND jwtToken.isExpired == true_
    - _Expected_Behavior: Token refresh is attempted automatically and operation is retried_
    - _Preservation: Valid token operations continue to work unchanged_
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 3.1, 3.7_
  
  - [x] 3.2 Implement Dio interceptor 401 handler with token refresh
    - Open `app/lib/core/network/network_service.dart`
    - Locate the `onError` handler in Dio interceptor
    - Replace placeholder comment `// Trigger logout or refresh` with actual implementation
    - Detect `e.response?.statusCode == 401`
    - Call `ref.read(authViewModelProvider.notifier).refreshToken()`
    - If refresh succeeds, clone original request with new token
    - Retry request using `handler.resolve()` with updated options
    - If refresh fails, proceed with error using `handler.next(e)`
    - Add refresh lock check to prevent concurrent refreshes
    - _Bug_Condition: isBugCondition1(networkOperation) where networkOperation is HttpRequest_
    - _Expected_Behavior: 401 errors trigger token refresh and request retry_
    - _Preservation: Non-401 errors and valid token requests unchanged_
    - _Requirements: 2.2, 3.1, 3.2, 3.7, 3.8_
  
  - [x] 3.3 Add WebSocket 401 detection and token refresh
    - Open `app/lib/core/websocket/websocket_service.dart`
    - Add 401 detection in WebSocket message handler (initial handshake or error message)
    - When 401 is detected, call `ref.read(authViewModelProvider.notifier).refreshToken()`
    - If token refresh succeeds, attempt to reconnect WebSocket with new token
    - Only stop retry attempts if token refresh fails or max retries exceeded
    - Update connection state to reflect token refresh attempt
    - _Bug_Condition: isBugCondition1(networkOperation) where networkOperation is WebSocketConnect_
    - _Expected_Behavior: WebSocket 401 errors trigger token refresh and reconnection_
    - _Preservation: Valid token WebSocket connections unchanged_
    - _Requirements: 2.1, 3.1, 3.7, 3.9_
  
  - [x] 3.4 Update SplashScreen initialization with 401 error handling
    - Open `app/lib/features/splash/ui/splash_screen.dart`
    - Locate `_loadHeavyDataInBackground()` method
    - Wrap initialization calls in try-catch that detects `DioException` with `response?.statusCode == 401`
    - When 401 is detected, call `ref.read(authViewModelProvider.notifier).refreshToken()`
    - If token refresh succeeds, recursively call `_loadHeavyDataInBackground()` to retry
    - If token refresh fails, log user out and redirect to login screen
    - Remove generic `debugPrint` error handling in favor of specific 401 handling
    - _Bug_Condition: isBugCondition1(networkOperation) where networkOperation is InitializationFlow_
    - _Expected_Behavior: Initialization 401 errors trigger token refresh and retry_
    - _Preservation: Successful initialization with valid tokens unchanged_
    - _Requirements: 2.4, 3.1, 3.7_
  
  - [x] 3.5 Verify Bug 1 exploration tests now pass
    - **Property 1: Expected Behavior** - Automatic Token Refresh on 401
    - **IMPORTANT**: Re-run the SAME tests from task 1.1-1.3 - do NOT write new tests
    - The tests from task 1 encode the expected behavior
    - When these tests pass, it confirms the expected behavior is satisfied
    - Run expired token WebSocket test from step 1.1
    - Run expired token API call test from step 1.2
    - Run expired token Splash test from step 1.3
    - **EXPECTED OUTCOME**: All tests PASS (confirms Bug 1 is fixed)
    - _Requirements: 2.1, 2.2, 2.4_

- [x] 4. Fix for Bug 2: Read vs Decrypted Conflation

  - [x] 4.1 Upgrade LocalDB schema to version 6 with is_decrypted column
    - Open `app/lib/core/storage/local_db_service.dart`
    - Change `version: 5` to `version: 6` in `_openDatabase()` method
    - Add `'is_decrypted INTEGER DEFAULT 0, '` to `_createMessagesTable()` CREATE TABLE statement
    - Update `onUpgrade()` to add migration for `oldVersion < 6`
    - Execute `ALTER TABLE messages ADD COLUMN is_decrypted INTEGER DEFAULT 0` in migration
    - Update `_ensureMessagesColumns()` to include `'is_decrypted': 'ALTER TABLE messages ADD COLUMN is_decrypted INTEGER DEFAULT 0'`
    - Test migration from version 5 to version 6 with sample data
    - _Bug_Condition: isBugCondition2(message) where NOT EXISTS(message.is_decrypted)_
    - _Expected_Behavior: Database schema includes is_decrypted column for independent state tracking_
    - _Preservation: Existing database operations and queries unchanged_
    - _Requirements: 2.6, 3.3_
  
  - [x] 4.2 Add helper methods for is_decrypted tracking
    - In `app/lib/core/storage/local_db_service.dart`
    - Implement `Future<void> markMessageAsDecrypted(String messageId)` method
    - Method should execute `UPDATE messages SET is_decrypted = 1 WHERE id = ?`
    - Implement `Future<List<Message>> getUndecryptedMessages()` method
    - Method should query `SELECT * FROM messages WHERE is_decrypted = 0`
    - Add error handling for database operations
    - _Bug_Condition: isBugCondition2(message) where message.is_decrypted state cannot be updated_
    - _Expected_Behavior: Helper methods allow independent decryption state tracking_
    - _Preservation: Existing database query methods unchanged_
    - _Requirements: 2.6, 2.7, 3.3_
  
  - [x] 4.3 Update Message model to include isDecrypted field
    - Open `app/lib/models/message.dart`
    - Add `bool isDecrypted` field to `Message` class
    - Update `fromJson()` to map `is_decrypted` column to `isDecrypted` field
    - Update `toJson()` to map `isDecrypted` field to `is_decrypted` column
    - Set default value to `false` for new messages
    - Update copyWith() method to include isDecrypted parameter
    - _Bug_Condition: isBugCondition2(message) where Message model lacks isDecrypted field_
    - _Expected_Behavior: Message model includes isDecrypted for state tracking_
    - _Preservation: Existing Message model fields and methods unchanged_
    - _Requirements: 2.6, 2.7, 3.3_
  
  - [x] 4.4 Fix E2EE Auto-Resend skip logic to use is_decrypted
    - Open `app/lib/features/chat/providers/chat_room_provider.dart`
    - Locate E2EE Auto-Resend initialization logic
    - Change skip condition from `message.status == MessageStatus.read` to `message.isDecrypted == true`
    - Update initialization query to use `localDbService.getUndecryptedMessages()`
    - Ensure re_encrypt_request is sent for all messages where `isDecrypted == false`
    - Add logging to track which messages are being processed
    - _Bug_Condition: isBugCondition2(message) where e2eeAutoResendSkipsMessage(message) == true_
    - _Expected_Behavior: E2EE Auto-Resend checks isDecrypted instead of status_
    - _Preservation: E2EE Auto-Resend for genuine failures unchanged_
    - _Requirements: 2.5, 2.8, 3.4, 3.5_
  
  - [x] 4.5 Update re_encrypt_response handler to mark messages as decrypted
    - In `app/lib/features/chat/providers/chat_room_provider.dart`
    - Locate the handler for `re_encrypt_response` WebSocket messages
    - After successful decryption and content update, call `localDbService.markMessageAsDecrypted(messageId)`
    - Ensure `isDecrypted` is set to `true` in the Message object
    - Update local state to reflect decryption status
    - Add error handling for database update failures
    - _Bug_Condition: isBugCondition2(message) where decryption success does not update is_decrypted_
    - _Expected_Behavior: Successful decryption marks message as decrypted independently_
    - _Preservation: Existing re_encrypt_response handling unchanged_
    - _Requirements: 2.7, 2.8, 3.5, 3.6_
  
  - [x] 4.6 Verify Bug 2 exploration tests now pass
    - **Property 1: Expected Behavior** - Independent Decryption State Tracking
    - **IMPORTANT**: Re-run the SAME tests from task 1.4-1.6 - do NOT write new tests
    - The tests from task 1 encode the expected behavior
    - When these tests pass, it confirms the expected behavior is satisfied
    - Run read but not decrypted test from step 1.4
    - Run database schema test from step 1.5
    - Run decryption success handler test from step 1.6
    - **EXPECTED OUTCOME**: All tests PASS (confirms Bug 2 is fixed)
    - _Requirements: 2.5, 2.6, 2.7_

- [x] 5. Verify preservation tests still pass

  - [x] 5.1 Re-run valid token authentication preservation tests
    - **Property 2: Preservation** - Valid Token Operations
    - **IMPORTANT**: Re-run the SAME tests from task 2.1 - do NOT write new tests
    - Run property-based tests for login, WebSocket, and API calls with valid tokens
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - _Requirements: 3.1, 3.7_
  
  - [x] 5.2 Re-run message sending preservation tests
    - **Property 2: Preservation** - Message Sending
    - **IMPORTANT**: Re-run the SAME tests from task 2.2 - do NOT write new tests
    - Run property-based tests for message sending with valid tokens
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - _Requirements: 3.2, 3.8_
  
  - [x] 5.3 Re-run successful decryption preservation tests
    - **Property 2: Preservation** - Successful Decryption
    - **IMPORTANT**: Re-run the SAME tests from task 2.3 - do NOT write new tests
    - Run property-based tests for messages that decrypt successfully
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - _Requirements: 3.3, 3.4_
  
  - [x] 5.4 Re-run logout flow preservation tests
    - **Property 2: Preservation** - Logout Flow
    - **IMPORTANT**: Re-run the SAME tests from task 2.4 - do NOT write new tests
    - Run property-based tests for logout operations
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - _Requirements: 3.9_
  
  - [x] 5.5 Re-run E2EE Auto-Resend preservation tests
    - **Property 2: Preservation** - E2EE Auto-Resend for Genuine Failures
    - **IMPORTANT**: Re-run the SAME tests from task 2.5 - do NOT write new tests
    - Run property-based tests for genuinely failed decryptions
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - _Requirements: 3.5, 3.6_

- [ ] 6. Write unit tests for modified functions

  - [x] 6.1 Unit test for refreshToken() method
    - Test successful token refresh with mock backend response
    - Test token refresh failure (401, 403, network error)
    - Test concurrent refresh attempts (verify refresh lock works)
    - Test token storage update after successful refresh
    - Test App Group token update for iOS
    - _Requirements: 2.1, 2.2, 2.3, 2.4_
  
  - [~] 6.2 Unit test for Dio interceptor 401 handler
    - Test 401 error triggers token refresh
    - Test request retry after successful refresh
    - Test error propagation after failed refresh
    - Test non-401 errors are not intercepted
    - Test concurrent 401 errors use same refresh
    - _Requirements: 2.2, 3.2_
  
  - [~] 6.3 Unit test for WebSocket 401 detection
    - Test 401 detection in WebSocket handshake
    - Test token refresh trigger on 401
    - Test reconnection after successful refresh
    - Test retry stop after failed refresh
    - Test valid token connections unchanged
    - _Requirements: 2.1, 3.7_
  
  - [~] 6.4 Unit test for SplashScreen initialization retry
    - Test 401 detection in initialization flow
    - Test token refresh trigger on 401
    - Test initialization retry after successful refresh
    - Test logout redirect after failed refresh
    - Test successful initialization unchanged
    - _Requirements: 2.4, 3.7_
  
  - [x] 6.5 Unit test for database migration to version 6
    - Test migration from version 5 to version 6
    - Test is_decrypted column is added correctly
    - Test existing messages have default value (0)
    - Test fresh install creates version 6 schema
    - Test _ensureMessagesColumns adds missing column
    - _Requirements: 2.6, 3.3_
  
  - [x] 6.6 Unit test for markMessageAsDecrypted() method
    - Test message is marked as decrypted (is_decrypted = 1)
    - Test database update executes correctly
    - Test error handling for invalid message ID
    - Test concurrent updates to same message
    - _Requirements: 2.7, 3.3_
  
  - [x] 6.7 Unit test for getUndecryptedMessages() method
    - Test returns only messages where is_decrypted = 0
    - Test excludes messages where is_decrypted = 1
    - Test handles empty result set
    - Test query performance with large datasets
    - _Requirements: 2.6, 3.3_
  
  - [~] 6.8 Unit test for E2EE Auto-Resend skip logic
    - Test messages with isDecrypted = true are skipped
    - Test messages with isDecrypted = false trigger re_encrypt_request
    - Test status field is ignored in skip decision
    - Test read but undecrypted messages are processed
    - _Requirements: 2.5, 2.8, 3.4_
  
  - [~] 6.9 Unit test for re_encrypt_response handler
    - Test successful decryption updates content
    - Test successful decryption calls markMessageAsDecrypted()
    - Test isDecrypted field is set to true
    - Test failed decryption does not mark as decrypted
    - Test database update error handling
    - _Requirements: 2.7, 2.8, 3.5, 3.6_

- [ ] 7. Write integration tests for full flows

  - [~] 7.1 Integration test: Expired token app launch flow
    - Set JWT token to expired value
    - Launch app and trigger SplashScreen initialization
    - Verify automatic token refresh occurs
    - Verify initialization retries with new token
    - Verify chat list loads correctly
    - Verify no error is shown to user
    - _Requirements: 2.1, 2.2, 2.4, 3.1, 3.7_
  
  - [~] 7.2 Integration test: Multi-device message recovery flow
    - Device A sends 30 messages to Device B
    - Device B receives messages but cannot decrypt (simulate missing private key)
    - Mark all 30 messages as read on Device B
    - Restore private key on Device B
    - Trigger E2EE Auto-Resend initialization
    - Verify all 30 messages are re-encrypted and recovered
    - Verify messages display correctly after recovery
    - _Requirements: 2.5, 2.6, 2.7, 2.8, 3.3, 3.4, 3.5, 3.6_
  
  - [~] 7.3 Integration test: Expired token during active session
    - Establish WebSocket connection with valid token
    - Simulate token expiration during session
    - Send message from another device
    - Verify WebSocket detects 401 and refreshes token
    - Verify WebSocket reconnects with new token
    - Verify message is received correctly
    - _Requirements: 2.1, 3.1, 3.7, 3.9_
  
  - [~] 7.4 Integration test: Concurrent 401 errors
    - Trigger multiple API calls simultaneously with expired token
    - Verify only one token refresh attempt occurs (refresh lock)
    - Verify all API calls retry with new token
    - Verify all operations complete successfully
    - _Requirements: 2.2, 3.1, 3.2_
  
  - [~] 7.5 Integration test: Database migration with existing data
    - Install app with version 5 database schema
    - Add sample messages to database
    - Upgrade app to version 6
    - Verify is_decrypted column is added
    - Verify existing messages have is_decrypted = 0
    - Verify new messages can be marked as decrypted
    - Verify E2EE Auto-Resend works with migrated data
    - _Requirements: 2.6, 2.7, 3.3_
  
  - [~] 7.6 Integration test: WebSocket reconnection with token refresh
    - Establish WebSocket connection with valid token
    - Simulate token expiration
    - Trigger WebSocket disconnection (network issue or server restart)
    - Verify WebSocket detects 401 on reconnection attempt
    - Verify token refresh is triggered
    - Verify WebSocket reconnects with new token
    - Verify message delivery resumes correctly
    - _Requirements: 2.1, 3.1, 3.7, 3.9_

- [x] 8. Checkpoint - Ensure all tests pass
  - Run all exploration tests (should pass after fixes)
  - Run all preservation tests (should still pass)
  - Run all unit tests (should pass)
  - Run all integration tests (should pass)
  - Verify no regressions in existing functionality
  - Ask user if any questions or issues arise
  - _Requirements: All requirements 2.1-2.8, 3.1-3.9_
