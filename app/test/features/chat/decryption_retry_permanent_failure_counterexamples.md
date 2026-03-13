# Bug Condition Exploration: Decryption Retry Permanent Failure

## Test Execution Summary

**Date**: Task 4.1 Execution
**Status**: ✅ Bug Confirmed - All tests FAILED as expected on unfixed code
**Test File**: `decryption_retry_permanent_failure_exploration_test.dart`

## Bug Confirmation

All 5 property-based tests **FAILED** on the unfixed code, confirming the bug exists:

1. ❌ Property: Message should remain in decryptingRetry when sender offline > 10s
2. ❌ Property: Message should display waiting message when sender offline
3. ❌ Property: Multiple messages should all remain in decryptingRetry when sender offline
4. ❌ Property: Retry count should not cause permanent failure when sender offline
5. ❌ Counterexample: Verify bug exists with specific scenario

## Counterexamples Found

### Counterexample 1: Sender Offline for Various Durations

**Test Cases**: 6 scenarios with offline durations from 11 seconds to 2 minutes

**Bug Behavior**:
- Message marked as `MessageStatus.failed` after 20 seconds (2 retries × 10 second timeout)
- Happens regardless of how long sender is offline (11s, 15s, 20s, 30s, 60s, 120s)

**Expected Behavior**:
- Message should remain in `MessageStatus.decryptingRetry` state
- Should wait indefinitely for sender to come online
- UI should display: "🔒 等待對方上線以重新解密..."

**Error Message**:
```
Expected: MessageStatus:<MessageStatus.decryptingRetry>
  Actual: MessageStatus:<MessageStatus.failed>
Message should remain in decryptingRetry state when sender offline 11 seconds. 
Current behavior: marks as failed after 2 retries (20 seconds total). 
Expected behavior: should wait indefinitely for sender to come online.
```

### Counterexample 2: Waiting Message Not Displayed

**Scenario**: Sender offline after max retries reached

**Bug Behavior**:
- After 2 retries (20 seconds), message status changes to `MessageStatus.failed`
- User sees permanent failure message instead of waiting message

**Expected Behavior**:
- Message should remain in `MessageStatus.decryptingRetry`
- UI should display: "🔒 等待對方上線以重新解密..."
- Message should be recoverable when sender comes online

### Counterexample 3: Multiple Messages from Same Sender

**Scenario**: 5 messages from the same offline sender all fail decryption

**Bug Behavior**:
- All 5 messages marked as `MessageStatus.failed` after 20 seconds
- No way to recover messages when sender comes online

**Expected Behavior**:
- All messages should remain in `MessageStatus.decryptingRetry`
- When sender comes online, all messages should be recoverable

**Error Message**:
```
Expected: MessageStatus:<MessageStatus.decryptingRetry>
  Actual: MessageStatus:<MessageStatus.failed>
All messages from offline sender should remain in decryptingRetry state. 
Message msg-0 should wait for sender to come online.
```

### Counterexample 4: Retry Count Causes Permanent Failure

**Scenario**: Retry mechanism exhausts max retries while sender is offline

**Bug Behavior**:
- Retry count reaches 2 (max retries)
- Message marked as permanent failure even though sender is just offline
- No distinction between "decryption error" and "sender offline"

**Expected Behavior**:
- Retry count should not cause permanent failure when sender is offline
- Message should remain recoverable
- System should distinguish between decryption errors and sender availability

**Error Message**:
```
Expected: MessageStatus:<MessageStatus.decryptingRetry>
  Actual: MessageStatus:<MessageStatus.failed>
Retry count should not cause permanent failure when sender is offline. 
The message should remain recoverable until sender comes online. 
Current bug: marks as failed after 2 retries.
```

### Counterexample 5: Detailed Timeline Scenario

**Concrete Scenario**:
```
Step 1: Decryption failed, status = MessageStatus.decryptingRetry, retryCount = 1
Step 2: Timeout at 10s, sender offline, retryCount = 2
Step 3: Timeout at 20s, max retries reached, status = MessageStatus.failed (BUG!)
Step 4: Sender comes online at 30s, but message already marked as failed
```

**Bug Behavior**:
- Message marked as failed at 20 seconds
- Sender comes online at 30 seconds (only 10 seconds too late)
- Message cannot be recovered because it's already in failed state

**Expected Behavior**:
- Message should remain in `MessageStatus.decryptingRetry` at 20 seconds
- When sender comes online at 30 seconds, message should be recoverable
- System should automatically retry decryption when sender comes online

**Error Message**:
```
Expected: MessageStatus:<MessageStatus.decryptingRetry>
  Actual: MessageStatus:<MessageStatus.failed>
BUG CONFIRMED: Message was marked as failed at 20s (after 2 retries), 
but sender came online at 30s. Message should have remained in 
decryptingRetry state to allow recovery. 
Expected: MessageStatus.decryptingRetry, Actual: MessageStatus.failed
```

## Root Cause Analysis

Based on the counterexamples, the root cause is:

1. **Timeout Mechanism**: After sending `re_encrypt_request`, a 10-second timeout is set
2. **Retry Logic**: When timeout triggers, `_handleDecryptionFailure` is called again, incrementing retry count
3. **Max Retries**: After 2 retries (20 seconds total), message is marked as `MessageStatus.failed`
4. **No Sender Status Check**: The system doesn't distinguish between:
   - Decryption failure due to wrong key (should fail permanently)
   - Decryption failure due to sender being offline (should wait)

**Code Location**: `app/lib/features/chat/providers/chat_room_provider.dart`
- Lines 765-770: Max retry check marks message as failed
- Lines 824-832: Timeout mechanism triggers retry

## Expected Fix Behavior

After implementing the fix, these tests should **PASS** because:

1. Message will remain in `MessageStatus.decryptingRetry` state when sender is offline
2. No timeout-based permanent failure marking
3. UI will display waiting message: "🔒 等待對方上線以重新解密..."
4. Messages will be recoverable when sender comes online
5. System will distinguish between decryption errors and sender availability

## Next Steps

1. ✅ Task 4.1 Complete: Bug condition exploration test written and run
2. ⏭️ Task 4.2: Write preservation property tests (before implementing fix)
3. ⏭️ Task 4.3: Implement the fix
4. ⏭️ Task 4.3.2: Re-run this test to verify it passes after fix
