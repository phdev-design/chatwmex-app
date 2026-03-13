# E2EE Re-Encrypt Key Mismatch Bugfix Design

## Overview

This design addresses a JSON key mismatch bug in the E2EE Auto-Resend logic within the `ChatRoomViewModel` class. The sender uses `'re_encrypted_content'` when sending re-encrypted messages, but the receiver attempts to read from `'content'`, causing null value reads and "missing content" errors. This prevents successful message re-decryption after key rotation events, leaving messages stuck in `decryptingRetry` status.

The fix updates the receiver's key reading logic to prioritize `'re_encrypted_content'` while maintaining backward compatibility with `'content'` as a fallback.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug - when `_handleReEncryptResponse` receives a payload with `'re_encrypted_content'` but attempts to read from `'content'`
- **Property (P)**: The desired behavior - the receiver should successfully read re-encrypted content from the correct key and decrypt the message
- **Preservation**: All existing validation logic, error handling, and decryption flows that must remain unchanged
- **_handleReEncryptRequest**: The sender-side method in `chat_room_provider.dart` that re-encrypts messages and sends them with the `'re_encrypted_content'` key
- **_handleReEncryptResponse**: The receiver-side method in `chat_room_provider.dart` that processes re-encrypted messages (currently reads from wrong key)
- **re_encrypt_response**: WebSocket control message event containing the re-encrypted message payload
- **decryptingRetry**: Message status indicating a message failed to decrypt and is awaiting re-encryption

## Bug Details

### Bug Condition

The bug manifests when the receiver processes a `re_encrypt_response` payload in `_handleReEncryptResponse`. The sender attaches re-encrypted content using the key `'re_encrypted_content'` (line 906 in `_handleReEncryptRequest`), but the receiver reads from `'content'` (line 921 in `_handleReEncryptResponse`), resulting in a null value.

**Formal Specification:**
```
FUNCTION isBugCondition(payload)
  INPUT: payload of type Map<String, dynamic>
  OUTPUT: boolean
  
  RETURN payload['re_encrypted_content'] IS NOT NULL
         AND payload['content'] IS NULL
         AND payload['message_id'] IS NOT NULL
         AND receiverAttemptingToRead(payload)
END FUNCTION
```

### Examples

- **Scenario 1**: User A sends encrypted message to User B. User B rotates their key. User B's client sends `re_encrypt_request`. User A's client re-encrypts and sends `re_encrypt_response` with `'re_encrypted_content': '<encrypted_data>'`. User B's client reads `payload['content']` which is null, logs "missing content", and returns early. Message remains in `decryptingRetry` status.

- **Scenario 2**: In a group chat, User C cannot decrypt a message after key rotation. The sender re-encrypts with fan-out encryption and sends `'re_encrypted_content': '{"is_fanout":true,"ciphertexts":{...}}'`. User C's client reads null from `'content'` key and fails to process the response.

- **Edge Case**: If an older version of the code (or a different implementation) sends `'content'` instead of `'re_encrypted_content'`, the current code would work, but the new code should handle both keys for backward compatibility.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Validation of `message_id` presence must continue to work (early return if missing)
- Validation of `receiver_id` matching current user must continue to work (security check)
- Validation of message status being `decryptingRetry` must continue to work
- Decryption logic for both one-on-one and group messages must remain unchanged
- LocalDB update logic must remain unchanged
- UI state update logic must remain unchanged
- Error handling for decryption failures must remain unchanged (maintain `decryptingRetry` status)

**Scope:**
All inputs that do NOT involve the `re_encrypt_response` payload processing should be completely unaffected by this fix. This includes:
- All other WebSocket event handlers
- The `_handleReEncryptRequest` sender-side logic
- Message sending and receiving flows
- Initial message decryption attempts

## Hypothesized Root Cause

Based on the bug description and code analysis, the root cause is clear:

1. **Key Name Inconsistency**: The sender (`_handleReEncryptRequest` at line 906) explicitly uses `'re_encrypted_content'` as the JSON key when sending the WebSocket message, but the receiver (`_handleReEncryptResponse` at line 921) reads from `'content'`, creating a direct mismatch.

2. **No Fallback Logic**: The receiver has no fallback mechanism to check alternative key names, so when `payload['content']` returns null, it immediately fails validation and returns early.

3. **Development Evolution**: This likely occurred during development when the key name was changed in the sender but not updated in the receiver, or when the two methods were developed independently without coordination.

## Correctness Properties

Property 1: Bug Condition - Re-Encrypted Content Reading

_For any_ `re_encrypt_response` payload where `'re_encrypted_content'` is present (regardless of whether `'content'` is present), the fixed `_handleReEncryptResponse` function SHALL successfully read the re-encrypted content, proceed with decryption, and update the message status to `delivered`.

**Validates: Requirements 2.1, 2.2**

Property 2: Preservation - Backward Compatibility

_For any_ `re_encrypt_response` payload where `'re_encrypted_content'` is NOT present but `'content'` IS present (legacy format), the fixed `_handleReEncryptResponse` function SHALL successfully read from the `'content'` key and process the message identically to the current implementation, preserving backward compatibility.

**Validates: Requirements 2.3**

Property 3: Preservation - Validation and Error Handling

_For any_ input to `_handleReEncryptResponse` where validation checks fail (missing `message_id`, wrong `receiver_id`, wrong message status, decryption errors), the fixed function SHALL produce exactly the same behavior as the original function, preserving all validation logic and error handling paths.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

## Fix Implementation

### Changes Required

**File**: `app/lib/features/chat/providers/chat_room_provider.dart`

**Function**: `_handleReEncryptResponse`

**Specific Changes**:

1. **Update Content Reading Logic** (Line 921):
   - Current: `final content = payload['content'] as String?;`
   - Fixed: `final content = (payload['re_encrypted_content'] ?? payload['content']) as String?;`
   - This reads from `'re_encrypted_content'` first, falling back to `'content'` if not present

**Rationale**:
- The null-coalescing operator (`??`) provides clean fallback logic
- Prioritizes the correct key (`'re_encrypted_content'`) that the sender uses
- Maintains backward compatibility with any legacy payloads using `'content'`
- Minimal change with no impact on surrounding code
- No changes needed to validation, decryption, or state update logic

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code, then verify the fix works correctly and preserves existing behavior.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm the root cause analysis by observing the null value read and early return.

**Test Plan**: Write tests that simulate receiving a `re_encrypt_response` payload with `'re_encrypted_content'` but no `'content'` key. Run these tests on the UNFIXED code to observe the "missing content" error and early return behavior.

**Test Cases**:
1. **One-on-One Message Re-Encryption**: Simulate receiving `re_encrypt_response` with `'re_encrypted_content'` for a one-on-one message (will fail on unfixed code with "missing content" log)
2. **Group Message Re-Encryption**: Simulate receiving `re_encrypt_response` with fan-out encrypted `'re_encrypted_content'` for a group message (will fail on unfixed code)
3. **Valid Message ID and Receiver**: Ensure all other validations pass, isolating the key mismatch as the sole failure point (will fail on unfixed code)
4. **Message in decryptingRetry Status**: Verify the message is in the correct status for processing (will still fail due to key mismatch on unfixed code)

**Expected Counterexamples**:
- `payload['content']` returns null when `'re_encrypted_content'` is present
- Log message: "Invalid re_encrypt_response: missing content"
- Function returns early without attempting decryption
- Message remains in `decryptingRetry` status

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds (payload contains `'re_encrypted_content'`), the fixed function successfully reads the content and processes the message.

**Pseudocode:**
```
FOR ALL payload WHERE isBugCondition(payload) DO
  content := _handleReEncryptResponse_fixed(payload)
  ASSERT content IS NOT NULL
  ASSERT content = payload['re_encrypted_content']
  ASSERT message_status_updated_to_delivered()
END FOR
```

**Test Cases**:
1. **Re-Encrypted Content Present**: Verify content is read from `'re_encrypted_content'` when present
2. **Successful Decryption**: Verify decryption proceeds with the correctly read content
3. **Status Update**: Verify message status changes from `decryptingRetry` to `delivered`
4. **UI Update**: Verify UI state reflects the decrypted message content

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL payload WHERE NOT isBugCondition(payload) DO
  ASSERT _handleReEncryptResponse_original(payload) = _handleReEncryptResponse_fixed(payload)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain
- It catches edge cases that manual unit tests might miss
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Observe behavior on UNFIXED code first for various validation failures and edge cases, then write property-based tests capturing that behavior.

**Test Cases**:
1. **Missing message_id**: Verify early return with error log (unchanged behavior)
2. **Wrong receiver_id**: Verify security warning and early return (unchanged behavior)
3. **Message not in decryptingRetry**: Verify skip processing with status log (unchanged behavior)
4. **Decryption failure**: Verify message remains in `decryptingRetry` status (unchanged behavior)
5. **Legacy 'content' key**: Verify backward compatibility when only `'content'` is present (fallback behavior)
6. **Both keys present**: Verify `'re_encrypted_content'` takes priority over `'content'`
7. **Empty content string**: Verify validation catches empty strings regardless of key name

### Unit Tests

- Test payload with `'re_encrypted_content'` only (bug condition)
- Test payload with `'content'` only (backward compatibility)
- Test payload with both keys (priority verification)
- Test payload with neither key (validation failure)
- Test all validation edge cases (missing message_id, wrong receiver_id, wrong status)
- Test decryption success and failure paths
- Test LocalDB and UI state updates

### Property-Based Tests

- Generate random payloads with various key combinations and verify correct content reading
- Generate random message states and verify preservation of validation logic
- Generate random decryption scenarios and verify error handling remains unchanged
- Test that all non-re_encrypt_response flows are completely unaffected

### Integration Tests

- Test full E2EE Auto-Resend flow: message fails to decrypt → sends re_encrypt_request → receives re_encrypt_response with `'re_encrypted_content'` → successfully decrypts
- Test key rotation scenario: user rotates key → existing messages trigger re-encryption → messages successfully decrypt with new key
- Test group chat re-encryption with fan-out encryption
- Test backward compatibility with older clients that might send `'content'` key
