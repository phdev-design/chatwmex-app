# Message Bubble Decryption Safeguards Bugfix Design

## Overview

The MessageBubble widget currently only checks for E2EE decryption failures when the message type is an image (line 73-75). This narrow check causes the system to incorrectly process encrypted text and other message types as normal content, leading to Regex errors when evaluating `msg.linkPreview` and empty URL warnings in ImageCacheService when attempting to resolve image URLs from encrypted content.

The fix broadens the decryption failure detection to apply to all message types by checking for the `🔒` prefix OR `MessageStatus.failed` status regardless of message type. This ensures that all failed or retrying decryption messages are handled in a dedicated branch before normal message type processing, preventing the system from attempting to parse or render encrypted content.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug - when text or non-image messages fail decryption but are not detected as decryption failures
- **Property (P)**: The desired behavior when decryption fails - display lock icon with error text and skip all content processing (link preview, image URL resolution)
- **Preservation**: Existing behavior for successfully decrypted messages, unsent messages, and decryptingRetry status that must remain unchanged
- **isDecryptionFailure**: Boolean flag that currently only checks `msg.type == MessageType.image && msg.content.startsWith('🔒')` (line 73-75)
- **hasPreview**: Boolean flag that determines whether link preview processing occurs (line 286-291)
- **linkPreview evaluation**: The system's attempt to access `msg.linkPreview` which triggers Regex operations on the content

## Bug Details

### Bug Condition

The bug manifests when a message has failed decryption or is in a failed state, but the message type is NOT an image. The current `isDecryptionFailure` check (line 73-75) only detects image decryption failures, causing text and other message types to bypass the decryption failure handling branch and proceed to normal content processing.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type Message
  OUTPUT: boolean
  
  RETURN (input.content.startsWith('🔒') OR input.status == MessageStatus.failed)
         AND input.type != MessageType.image
         AND NOT input.status == MessageStatus.decryptingRetry
END FUNCTION
```

### Examples

- **Text message decryption failure**: Message with `type == MessageType.text`, `content == '🔒 encrypted_data'`, `status == MessageStatus.failed` → System evaluates `msg.linkPreview` on encrypted content, causing Regex errors
- **Voice message decryption failure**: Message with `type == MessageType.voice`, `content.startsWith('🔒')` → System attempts to render AudioMessageBubble with encrypted content
- **File message decryption failure**: Message with `type == MessageType.file`, `status == MessageStatus.failed` → System attempts to parse file URL from encrypted content, causing empty URL warnings
- **Edge case - decryptingRetry status**: Message with `status == MessageStatus.decryptingRetry` → Should display loading spinner with "等待對方上線以重新解密..." message (already working correctly, must preserve)

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Messages with `status == MessageStatus.decryptingRetry` must continue to display the loading spinner with "🔒 等待對方上線以重新解密..." message (lines 80-97)
- Successfully decrypted image messages must continue to render with tap-to-view functionality (lines 98-141)
- Successfully decrypted voice messages must continue to render AudioMessageBubble widget (lines 142-143)
- Successfully decrypted file messages must continue to render with tap-to-open functionality (lines 144-217)
- Successfully decrypted text messages with valid URLs must continue to evaluate and display link previews (lines 286-291, 293-382)
- Unsent messages (`isUnsent == true`) must continue to display "此訊息已收回" regardless of decryption status (lines 656-663)
- Successfully decrypted messages must continue to display reactions, reply content, timestamp, and status icons (lines 383-788)

**Scope:**
All inputs that do NOT involve decryption failure (content does NOT start with '🔒' AND status is NOT MessageStatus.failed) should be completely unaffected by this fix. This includes:
- Successfully decrypted messages of all types
- Messages in decryptingRetry status (already handled separately)
- Unsent messages
- Normal message interactions (long press, reactions, replies, delete, unsend)

## Hypothesized Root Cause

Based on the bug description and code analysis, the root cause is:

1. **Narrow Decryption Failure Check**: The `isDecryptionFailure` flag (line 73-75) only checks for `msg.type == MessageType.image && msg.content.startsWith('🔒')`, missing text and other message types that fail decryption

2. **Missing Status Check**: The decryption failure check does not include `msg.status == MessageStatus.failed`, which is another indicator of decryption failure regardless of message type

3. **No Dedicated Failure Branch**: There is no `else if (isDecryptionFailure)` branch in the message type processing logic (lines 80-218), so failed text/voice/file messages fall through to their respective type handlers

4. **Link Preview Evaluated on Encrypted Content**: The `hasPreview` calculation (lines 286-291) evaluates `msg.linkPreview` on all non-unsent messages, including those with encrypted content, triggering Regex operations that fail on encrypted data

5. **Image URL Resolution on Encrypted Content**: The link preview card (lines 293-382) attempts to resolve image URLs from `preview.imageUrl` even when the content is encrypted, causing ImageCacheService to log empty URL warnings

## Correctness Properties

Property 1: Bug Condition - Decryption Failure Detection for All Message Types

_For any_ message where the content starts with '🔒' OR the status is MessageStatus.failed (regardless of message type), the fixed MessageBubble widget SHALL display a lock icon with error text in subtle/error color, and SHALL NOT evaluate msg.linkPreview, SHALL NOT attempt to resolve or render image URLs, and SHALL set hasPreview = false to completely disable link preview processing.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5**

Property 2: Preservation - Successfully Decrypted Message Behavior

_For any_ message where the content does NOT start with '🔒' AND the status is NOT MessageStatus.failed AND the status is NOT MessageStatus.decryptingRetry, the fixed MessageBubble widget SHALL produce exactly the same rendering and behavior as the original code, preserving all existing functionality for successfully decrypted messages including image rendering, voice playback, file attachments, link previews, reactions, replies, and message actions.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `app/lib/features/chat/ui/widgets/message_bubble.dart`

**Function**: `build(BuildContext context)` in `_MessageBubbleState`

**Specific Changes**:

1. **Broaden Decryption Failure Detection** (lines 73-75):
   - Change from: `final isDecryptionFailure = msg.type == MessageType.image && msg.content.startsWith(decryptionFailurePrefix);`
   - Change to: `final isDecryptionFailure = msg.content.startsWith(decryptionFailurePrefix) || msg.status == MessageStatus.failed;`
   - This detects decryption failures for ALL message types, not just images

2. **Add Dedicated Decryption Failure Branch** (after line 97, before line 98):
   - Insert new `else if (isDecryptionFailure)` branch to handle all decryption failures
   - Display lock icon with error text: `Row(children: [Icon(Icons.lock_outline, size: 16, color: subtleTextColor), SizedBox(width: 6), Text('🔒 解密失敗', style: TextStyle(fontSize: 13, color: subtleTextColor))])`
   - This ensures failed messages are handled before normal type processing

3. **Prevent Link Preview Evaluation on Encrypted Content** (line 286):
   - Change from: `final hasPreview = !msg.isUnsent && preview != null && (...);`
   - Change to: `final hasPreview = !msg.isUnsent && !isDecryptionFailure && !isDecryptingRetry && preview != null && (...);`
   - This prevents `msg.linkPreview` evaluation and Regex operations on encrypted content

4. **Update Conditional Logic Order**:
   - Ensure the order is: `isDecryptingRetry` → `isDecryptionFailure` → normal message type processing
   - This guarantees encrypted/failed messages are caught before attempting to render content

5. **Add Safety Comments**:
   - Add comment above `isDecryptionFailure` explaining it applies to all message types
   - Add comment above `hasPreview` explaining it skips encrypted/failed messages

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code, then verify the fix works correctly and preserves existing behavior.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Write tests that create messages with decryption failures for different message types and observe the system's behavior. Run these tests on the UNFIXED code to observe failures and understand the root cause.

**Test Cases**:
1. **Text Message Decryption Failure**: Create message with `type == MessageType.text`, `content == '🔒 encrypted_data'`, observe that system evaluates `msg.linkPreview` (will fail on unfixed code with Regex errors)
2. **Voice Message Decryption Failure**: Create message with `type == MessageType.voice`, `content.startsWith('🔒')`, observe that system attempts to render AudioMessageBubble (will fail on unfixed code)
3. **File Message Failed Status**: Create message with `type == MessageType.file`, `status == MessageStatus.failed`, observe that system attempts to parse file URL (will fail on unfixed code with empty URL warnings)
4. **Image Message Decryption Failure**: Create message with `type == MessageType.image`, `content.startsWith('🔒')`, observe that system correctly displays lock icon (should work on unfixed code - this is the only case that works)

**Expected Counterexamples**:
- Text/voice/file messages with decryption failures are not detected by `isDecryptionFailure` check
- System evaluates `msg.linkPreview` on encrypted content, causing Regex errors
- System attempts to resolve image URLs from encrypted content, causing empty URL warnings
- Possible causes: narrow type check in `isDecryptionFailure`, missing status check, no dedicated failure branch

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**
```
FOR ALL message WHERE isBugCondition(message) DO
  widget := MessageBubble_fixed(message)
  ASSERT widget displays lock icon with error text
  ASSERT widget does NOT evaluate msg.linkPreview
  ASSERT widget does NOT attempt to resolve image URLs
  ASSERT hasPreview == false
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL message WHERE NOT isBugCondition(message) DO
  ASSERT MessageBubble_original(message) = MessageBubble_fixed(message)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain (different message types, statuses, content variations)
- It catches edge cases that manual unit tests might miss (e.g., messages with both decryptingRetry status and 🔒 prefix)
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Observe behavior on UNFIXED code first for successfully decrypted messages, then write property-based tests capturing that behavior.

**Test Cases**:
1. **Successfully Decrypted Image Messages**: Observe that images render with tap-to-view on unfixed code, then verify this continues after fix
2. **Successfully Decrypted Text with Link Preview**: Observe that link previews display correctly on unfixed code, then verify this continues after fix
3. **DecryptingRetry Status Messages**: Observe that loading spinner displays on unfixed code, then verify this continues after fix
4. **Unsent Messages**: Observe that "此訊息已收回" displays on unfixed code, then verify this continues after fix

### Unit Tests

- Test decryption failure detection for each message type (text, image, voice, file)
- Test decryption failure detection with `status == MessageStatus.failed`
- Test that `hasPreview` is false when `isDecryptionFailure` is true
- Test that decryption failure branch displays lock icon with error text
- Test edge cases (empty content, null status, decryptingRetry + 🔒 prefix)

### Property-Based Tests

- Generate random messages with decryption failures (various types, 🔒 prefix or failed status) and verify lock icon displays and no link preview evaluation occurs
- Generate random successfully decrypted messages (various types, valid content) and verify rendering matches original behavior
- Generate random message states (combinations of type, status, content, isUnsent) and verify preservation of existing behavior for non-buggy inputs

### Integration Tests

- Test full message flow with decryption failure in a chat room context
- Test switching between successfully decrypted and failed messages
- Test that user interactions (long press, reactions, replies) work correctly on successfully decrypted messages after fix
- Test that decryptingRetry messages continue to show loading spinner and transition correctly when decryption succeeds or fails
