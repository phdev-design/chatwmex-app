# E2EE Re-encrypt Offline Persistence - Preservation Test Summary

## Overview

This document summarizes the preservation property tests written for Task 2 of the e2ee-reencrypt-offline-persistence bugfix spec. These tests verify baseline behavior on UNFIXED code that must be preserved after implementing the fix.

## Test File

`e2ee_reencrypt_preservation_test.go`

## Test Results

**Status**: ✅ ALL TESTS PASSING on unfixed code

**Total Tests**: 6 preservation tests
- 5 unit/integration tests
- 1 property-based test (20 random scenarios)

## Tests Implemented

### 1. TestPreservation_OnlineReEncryptRequestDirectForwarding
**Validates**: Requirement 3.1

**Property**: When sender is ONLINE, re_encrypt_request is forwarded directly via WebSocket without database persistence.

**Test Scenario**:
- Sender (user-A) is registered and online
- Receiver (user-B) sends re_encrypt_request
- Verify request is NOT persisted to database
- Verify sender receives request via WebSocket immediately

**Result**: ✅ PASS
- Request was NOT persisted (count = 0)
- Sender received re_encrypt_request via WebSocket immediately
- Confirms direct forwarding without database persistence

---

### 2. TestPreservation_ReEncryptResponseFlow
**Validates**: Requirements 3.1, 3.2, 3.3

**Property**: When sender is online, complete re-encryption flow works correctly.

**Test Scenario**:
1. Receiver sends re_encrypt_request
2. Sender receives request via WebSocket
3. Sender processes and sends re_encrypt_response
4. Receiver receives response with re-encrypted content

**Result**: ✅ PASS
- Complete flow: Request → Process → Response → Decrypt
- All communication via WebSocket (no database involved)
- Receiver can successfully decrypt message

---

### 3. TestPreservation_NormalMessageFlow
**Validates**: Requirement 3.4

**Property**: Normal message sending and receiving works correctly, unaffected by re-encryption mechanism.

**Test Scenario**:
- Sender sends normal text message
- Receiver receives message correctly
- Message is persisted to database

**Result**: ✅ PASS
- Receiver received normal message correctly
- Message persisted to database
- Message flow unaffected by re-encryption changes

---

### 4. TestPreservation_OtherWebSocketEvents
**Validates**: Requirement 3.5

**Property**: Other WebSocket events (typing indicators, read receipts) work normally.

**Test Scenarios**:
1. Typing indicator event
2. Read receipt event

**Result**: ✅ PASS
- Typing indicators work correctly
- Read receipts work correctly
- Other WebSocket events unaffected by re-encryption changes

---

### 5. TestPreservation_PropertyBased_OnlineReEncryptForwarding
**Validates**: Requirements 3.1, 3.2

**Property**: For ANY re_encrypt_request where sender is online, request is forwarded directly via WebSocket without database persistence.

**Test Approach**: Property-based testing with 20 random scenarios
- Generates random message IDs, sender IDs, receiver IDs
- Tests across many different user combinations
- Verifies both properties:
  1. Request NOT persisted to database
  2. Request forwarded to sender via WebSocket

**Result**: ✅ PASS
- Property verified across 20 random test cases
- All online re_encrypt_requests were forwarded directly
- No requests were persisted to database

---

## Preservation Requirements Coverage

| Requirement | Description | Test Coverage |
|-------------|-------------|---------------|
| 3.1 | Direct WebSocket forwarding when sender online | ✅ Tests 1, 2, 5 |
| 3.2 | Sender processes and replies with re_encrypt_response | ✅ Test 2 |
| 3.3 | Receiver successfully decrypts message | ✅ Test 2 |
| 3.4 | Normal message flow unaffected | ✅ Test 3 |
| 3.5 | Other WebSocket events work normally | ✅ Test 4 |

## Key Observations

### Baseline Behavior (to be preserved after fix)

1. **Online Sender Scenario**:
   - re_encrypt_request is forwarded immediately via WebSocket
   - No database persistence occurs
   - Real-time communication works correctly

2. **Normal Message Flow**:
   - Text messages sent and received normally
   - Messages persisted to database
   - Unaffected by re-encryption mechanism

3. **Other WebSocket Events**:
   - Typing indicators work correctly
   - Read receipts work correctly
   - All event types function normally

### What Must NOT Change After Fix

- When sender is ONLINE, the system must continue to use direct WebSocket forwarding
- No database persistence should occur for online sender scenarios
- Normal message flow must remain unchanged
- Other WebSocket events must continue to work normally

### What WILL Change After Fix (Bug Condition)

- When sender is OFFLINE, re_encrypt_request will be persisted to database
- System will automatically deliver pending requests when sender reconnects
- Receiver will be able to retry beyond 2 attempts (until 7-day TTL)

## Test Execution

```bash
# Run all preservation tests
go test -v -run TestPreservation ./internal/delivery/websocket/

# Run specific preservation test
go test -v -run TestPreservation_OnlineReEncryptRequestDirectForwarding ./internal/delivery/websocket/

# Run property-based test
go test -v -run TestPreservation_PropertyBased ./internal/delivery/websocket/
```

## Next Steps

1. ✅ Task 2 Complete: Preservation tests written and passing on unfixed code
2. ⏭️ Task 3: Implement the fix for offline re-encrypt request persistence
3. ⏭️ Task 3.5: Verify bug condition exploration test passes (from Task 1)
4. ⏭️ Task 3.6: Re-run these preservation tests to ensure no regressions

## Conclusion

All preservation property tests are passing on the unfixed code, establishing a clear baseline of behavior that must be preserved after implementing the fix. The tests cover all preservation requirements (3.1-3.5) and use both unit/integration testing and property-based testing for comprehensive coverage.

The fix should ONLY affect the offline sender scenario (bug condition) and must NOT change any of the behaviors verified by these tests.
