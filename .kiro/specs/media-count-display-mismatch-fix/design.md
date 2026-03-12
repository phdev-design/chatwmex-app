# Media Count Display Mismatch Fix - Bugfix Design

## Overview

The Room Media page displays an incorrect count of media items because the total includes all messages from the backend, regardless of whether they can be successfully decrypted and rendered. When decryption fails (due to missing encryption keys, 404 errors, or invalid content), `resolveFullUrl()` returns an empty string, causing the UI to filter out these items from the grid while still counting them in the total. This fix will filter out invalid messages in `room_media_provider.dart` after decryption, ensuring the count matches what users actually see.

## Glossary

- **Bug_Condition (C)**: A media message where decryption fails or `resolveFullUrl(content)` returns an empty string
- **Property (P)**: The displayed count must equal the number of renderable media items in the grid
- **Preservation**: Existing decryption logic, pagination, plaintext handling, and grouping behavior must remain unchanged
- **RoomMediaNotifier**: The provider in `app/lib/features/chat/providers/room_media_provider.dart` that manages media state and decryption
- **resolveFullUrl**: The function in `app/lib/features/chat/utils/chat_url_utils.dart` that converts content to full URLs, returning empty string for invalid content
- **_decryptMediaContent**: The method that processes and decrypts media messages using ECDH encryption
- **RoomMediaState.messages**: The list of media messages stored in state, used for both counting and rendering

## Bug Details

### Bug Condition

The bug manifests when the backend returns media messages that fail decryption or validation. The `_decryptMediaContent` method processes messages but keeps invalid ones in the state with their original encrypted content. Later, `resolveFullUrl()` in `media_tab_content.dart` returns empty strings for these invalid messages, causing them to be filtered from the grid display but still counted in the total.

**Formal Specification:**
```
FUNCTION isBugCondition(message)
  INPUT: message of type Message
  OUTPUT: boolean
  
  decryptedContent := _decryptMediaContent([message])[0].content
  fullUrl := resolveFullUrl(decryptedContent)
  
  RETURN fullUrl.isEmpty
         AND message is included in RoomMediaState.messages
         AND message is not rendered in the grid
END FUNCTION
```

### Examples

- Backend returns 10 media messages, 3 have missing encryption keys → `resolveFullUrl()` returns empty string for those 3 → UI shows "10 media files" but only renders 7 items in grid
- A media message has invalid encrypted content (Base64 string ≥40 chars with +/= characters) → decryption fails → content remains encrypted → `resolveFullUrl()` detects Base64 and returns empty string → counted but not displayed
- A media message references a deleted file (404) → decryption succeeds but URL is invalid → `resolveFullUrl()` may return URL but image fails to load → counted and displayed with error placeholder (this is NOT the bug condition)
- All 10 messages decrypt successfully → `resolveFullUrl()` returns valid URLs for all → UI shows "10 media files" and renders 10 items (correct behavior)

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- All media messages that decrypt successfully and have valid URLs must continue to be counted and displayed
- Pagination logic must continue to merge new messages correctly without duplicates
- Plaintext content (URLs, relative paths, ObjectIDs) must continue to be processed without decryption attempts
- Month-based grouping must continue to work correctly for valid messages
- Loading states and error placeholders for network errors during image loading must remain unchanged

**Scope:**
All inputs that do NOT match the bug condition (messages with valid, renderable content) should be completely unaffected by this fix. This includes:
- Successfully decrypted messages with valid URLs
- Plaintext messages (complete URLs, relative paths, ObjectIDs)
- Messages that fail to load images due to network errors (these should still be counted and displayed with error placeholder)

## Hypothesized Root Cause

Based on the bug description and code analysis, the root cause is:

1. **No Post-Decryption Filtering**: The `_decryptMediaContent` method returns all messages regardless of whether decryption succeeded. When decryption fails, the message retains its original encrypted content, which later gets filtered by `resolveFullUrl()` returning an empty string.

2. **Filtering Happens Too Late**: The filtering logic exists in `resolveFullUrl()` (returns empty string for Base64 content ≥40 chars), but this happens during rendering in `media_tab_content.dart`. By this point, the messages are already in `RoomMediaState.messages`, so the count includes them.

3. **State Contains Invalid Messages**: Both `loadInitial()` and `loadMore()` store the decrypted messages directly in state without validating that `resolveFullUrl()` would return non-empty URLs.

4. **Count Calculation**: The count displayed to users is based on `state.messages.length`, which includes all messages from the backend, not just renderable ones.

## Correctness Properties

Property 1: Bug Condition - Count Matches Rendered Items

_For any_ set of media messages where some fail decryption or validation (isBugCondition returns true for those messages), the fixed RoomMediaNotifier SHALL filter out those invalid messages from the state, ensuring the displayed count equals the number of items actually rendered in the grid.

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Preservation - Valid Messages Unchanged

_For any_ media message where decryption succeeds and resolveFullUrl returns a non-empty string (isBugCondition returns false), the fixed RoomMediaNotifier SHALL continue to include that message in the state and display it exactly as before, preserving all existing functionality for valid messages including pagination, grouping, and rendering.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `app/lib/features/chat/providers/room_media_provider.dart`

**Function**: `_decryptMediaContent` and its callers (`loadInitial`, `loadMore`)

**Specific Changes**:
1. **Add Post-Decryption Validation**: After `_decryptMediaContent` returns the decrypted messages, filter out any messages where `resolveFullUrl(message.content)` returns an empty string.

2. **Import Required Utility**: Add import for `resolveFullUrl` from `app/lib/features/chat/utils/chat_url_utils.dart` at the top of the file.

3. **Create Filter Helper Method**: Add a private method `_filterValidMedia(List<Message> messages)` that takes decrypted messages and returns only those with non-empty URLs from `resolveFullUrl()`.

4. **Update loadInitial**: After calling `_decryptMediaContent(result.messages)`, pass the result through `_filterValidMedia()` before storing in state.

5. **Update loadMore**: After calling `_decryptMediaContent(result.messages)`, pass the result through `_filterValidMedia()` before merging with existing messages.

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code by observing count mismatches, then verify the fix correctly filters invalid messages and preserves all existing behavior for valid messages.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm that messages with invalid content are counted but not rendered, creating a mismatch.

**Test Plan**: Create test scenarios with mixed valid and invalid media messages. Run these tests on the UNFIXED code to observe the count mismatch and confirm the root cause.

**Test Cases**:
1. **Mixed Valid/Invalid Messages**: Backend returns 10 messages, 3 have Base64 encrypted content that fails decryption (will show count=10, rendered=7 on unfixed code)
2. **All Invalid Messages**: Backend returns 5 messages, all have invalid encrypted content (will show count=5, rendered=0 on unfixed code)
3. **All Valid Messages**: Backend returns 8 messages, all decrypt successfully (will show count=8, rendered=8 - correct behavior)
4. **Pagination with Invalid**: Load initial 10 messages (3 invalid), then load 10 more (2 invalid) (will show count=20, rendered=15 on unfixed code)

**Expected Counterexamples**:
- `state.messages.length` includes messages where `resolveFullUrl(message.content)` returns empty string
- Possible causes: no filtering after decryption, validation happens too late in rendering phase

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds (messages with invalid content), the fixed function filters them out so the count matches rendered items.

**Pseudocode:**
```
FOR ALL message WHERE isBugCondition(message) DO
  state := RoomMediaNotifier_fixed.loadInitial()
  ASSERT message NOT IN state.messages
  ASSERT state.messages.length == countOfRenderedItems
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold (messages with valid content), the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL message WHERE NOT isBugCondition(message) DO
  ASSERT RoomMediaNotifier_original.state.messages CONTAINS message
  ASSERT RoomMediaNotifier_fixed.state.messages CONTAINS message
  ASSERT message.content is unchanged
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across different message types (URLs, paths, ObjectIDs)
- It catches edge cases that manual unit tests might miss (unusual but valid URL formats)
- It provides strong guarantees that behavior is unchanged for all valid messages

**Test Plan**: Observe behavior on UNFIXED code first for valid messages (plaintext URLs, successfully decrypted content), then write property-based tests capturing that behavior.

**Test Cases**:
1. **Plaintext URL Preservation**: Verify messages with complete URLs (http://, https://) continue to be counted and displayed
2. **Relative Path Preservation**: Verify messages with /uploads/ paths continue to be counted and displayed
3. **ObjectID Preservation**: Verify messages with 24-char hex ObjectIDs continue to be counted and displayed
4. **Pagination Preservation**: Verify loadMore() continues to merge messages correctly without duplicates
5. **Grouping Preservation**: Verify month-based grouping continues to work for valid messages

### Unit Tests

- Test `_filterValidMedia` with messages containing valid URLs (should keep them)
- Test `_filterValidMedia` with messages containing Base64 encrypted content (should filter them out)
- Test `_filterValidMedia` with mixed valid/invalid messages (should keep only valid ones)
- Test `loadInitial` with all valid messages (count should match)
- Test `loadInitial` with mixed valid/invalid messages (count should match rendered items)
- Test `loadMore` pagination with invalid messages in both batches (count should remain accurate)

### Property-Based Tests

- Generate random sets of media messages with varying content types (URLs, paths, ObjectIDs, Base64) and verify count always matches number of messages where `resolveFullUrl()` returns non-empty string
- Generate random pagination scenarios and verify merged message list never contains duplicates and all messages have valid URLs
- Test that for any valid message type (URL, path, ObjectID), the message is always included in state after filtering

### Integration Tests

- Test full flow: load initial media → verify count matches grid items → load more → verify count still matches
- Test with real encrypted messages that fail decryption → verify they don't appear in count or grid
- Test switching between different rooms with different media validity rates → verify counts are always accurate
