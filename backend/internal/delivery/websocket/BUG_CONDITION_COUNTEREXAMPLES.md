# Bug Condition Exploration - Counterexamples Found

## Bug: WebSocket Read Limit Exceeded

### Test File
`backend/internal/delivery/websocket/websocket_large_payload_test.go`

### Test Execution Date
Task 1.1 - Bug Condition Exploration Test

### Bug Confirmation
✅ **Bug Confirmed** - The test successfully detected the bug on unfixed code.

### Root Cause
The current `maxMessageSize` in `backend/internal/delivery/websocket/client.go` is set to **8192 bytes (8KB)**. This limit is insufficient for group messages using Fan-out E2EE encryption, where each member receives their own encrypted content.

### Counterexamples Found

The property-based test generated multiple counterexamples demonstrating the bug:

#### 1. 10 Members Group (~10.39 KB)
- **Payload Size**: 10,635 bytes (10.39 KB)
- **Error**: `websocket: close 1009 (message too big)`
- **Server Log**: `websocket: read limit exceeded`
- **Result**: Connection disconnected, message not delivered

#### 2. 20 Members Group (~20.51 KB)
- **Payload Size**: 21,005 bytes (20.51 KB)
- **Error**: `websocket: close 1009 (message too big)`
- **Server Log**: `websocket: read limit exceeded`
- **Result**: Connection disconnected, message not delivered

#### 3. 50 Members Group (~50.89 KB)
- **Payload Size**: 52,115 bytes (50.89 KB)
- **Error**: `websocket: close 1009 (message too big)`
- **Server Log**: `websocket: read limit exceeded`
- **Result**: Connection disconnected, message not delivered

#### 4. 100 Members Group (~101.53 KB)
- **Payload Size**: 103,965 bytes (101.53 KB)
- **Error**: `write tcp: broken pipe` (connection broken before message could be sent)
- **Server Log**: `websocket: read limit exceeded`
- **Result**: Connection broken, message not delivered

#### 5. 10 Members with Link Preview (~12.10 KB)
- **Payload Size**: 12,395 bytes (12.10 KB)
- **Error**: `websocket: close 1009 (message too big)`
- **Server Log**: `websocket: read limit exceeded`
- **Result**: Connection disconnected, message not delivered

### Analysis

All test cases with payloads exceeding 8KB failed with the same pattern:
1. Client sends message > 8KB
2. Server's `conn.SetReadLimit(maxMessageSize)` rejects the message
3. Server logs "read limit exceeded"
4. WebSocket connection closes with code 1009 (message too big)
5. Subsequent messages cannot be sent (connection is broken)

### Impact

This bug affects:
- **Group chats with 10+ members**: Even small messages become large when encrypted for each member
- **Messages with Link Preview**: Additional metadata increases payload size
- **Long text messages in groups**: Content + Fan-out E2EE encryption exceeds 8KB
- **User experience**: Messages fail to send, connections drop, users must reconnect

### Expected Behavior (After Fix)

According to the design document (Requirements 2.1):
- WebSocket should accept messages up to **1MB (1,048,576 bytes)**
- Group messages with Fan-out E2EE should transmit successfully
- Connection should remain stable after sending large payloads
- Follow-up messages should continue to work

### Fix Required

Update `maxMessageSize` in `backend/internal/delivery/websocket/client.go`:
```go
// Current (causes bug)
maxMessageSize = 8192

// Fixed (supports up to ~100 member groups)
maxMessageSize = 1048576  // 1MB
```

### Test Validation

After implementing the fix, re-run the same test:
```bash
go test -v -run TestProperty_LargePayloadWebSocketConnection ./internal/delivery/websocket/
```

**Expected outcome**: All test cases should PASS, confirming:
- Large payloads (10KB - 200KB) are accepted
- WebSocket connection remains alive
- Follow-up messages can be sent successfully
