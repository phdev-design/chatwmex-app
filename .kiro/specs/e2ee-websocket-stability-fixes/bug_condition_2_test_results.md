# Bug Condition 2: Link Preview Type Overwrite - Test Results

## Test Execution Summary

**Test File**: `backend/internal/usecase/message_link_preview_type_test.go`

**Test Status**: ✅ PASSED (Test correctly FAILED on unfixed code, confirming bug exists)

**Date**: 2026-03-13

## Test Overview

This bug condition exploration test validates that the backend incorrectly overwrites `msg.Type` to `"link"` when a Link Preview is detected, causing Flutter frontend crashes.

## Test Results

### TestProperty_LinkPreviewTypePreservation

All 5 test cases FAILED as expected, confirming the bug exists:

#### 1. Text message with YouTube link
- **Original Type**: `text`
- **Modified Type**: `link` ❌
- **Link Preview URL**: `https://www.youtube.com/watch?v=dQw4w9WgXcQ`
- **Result**: Backend overwrites msg.Type to 'link', causing Flutter StateError

#### 2. Text message with news link
- **Original Type**: `text`
- **Modified Type**: `link` ❌
- **Link Preview URL**: `https://www.example.com/news/article-123`
- **Result**: Backend overwrites msg.Type to 'link'

#### 3. Text message with GitHub link
- **Original Type**: `text`
- **Modified Type**: `link` ❌
- **Link Preview URL**: `https://github.com/user/repo`
- **Result**: Backend overwrites msg.Type to 'link'

#### 4. Text message with Twitter link
- **Original Type**: `text`
- **Modified Type**: `link` ❌
- **Link Preview URL**: `https://twitter.com/user/status/123456`
- **Result**: Backend overwrites msg.Type to 'link'

#### 5. Text message with blog link
- **Original Type**: `text`
- **Modified Type**: `link` ❌
- **Link Preview URL**: `https://blog.example.com/post/how-to-code`
- **Result**: Backend overwrites msg.Type to 'link'

### TestProperty_LinkPreviewTypePreservation_GroupMessages

All 3 group message test cases FAILED as expected:

#### 1. Group message with 5 members
- **Original Type**: `text`
- **Modified Type**: `link` ❌
- **Members**: 5
- **Result**: Bug affects group messages with Link Preview

#### 2. Group message with 10 members
- **Original Type**: `text`
- **Modified Type**: `link` ❌
- **Members**: 10
- **Result**: Bug affects larger groups

#### 3. Group message with 20 members
- **Original Type**: `text`
- **Modified Type**: `link` ❌
- **Members**: 20
- **Result**: Bug affects even larger groups

## Root Cause Confirmation

The test confirms the root cause identified in the design document:

**Location**: `backend/internal/usecase/message_usecase.go` lines 120-124

**Problematic Code**:
```go
if msg.LinkPreview != nil && msg.LinkPreview.URL != "" {
    msg.Type = "link"
} else {
    msg.LinkPreview = nil
}
```

**Issue**: The backend forcibly overwrites `msg.Type` to `"link"` when a Link Preview is detected, regardless of the original type set by the Flutter frontend.

**Impact**: 
- Flutter frontend's `MessageType` enum does not include `"link"` as a valid value
- When `Message.fromJson()` tries to parse the message, it throws a `StateError`
- This causes the Flutter app to crash when receiving messages with Link Preview

## Counterexamples Summary

The property-based test successfully generated **8 counterexamples** demonstrating:

1. ✅ Bug affects 1-on-1 messages with Link Preview (5 examples)
2. ✅ Bug affects group messages with Link Preview (3 examples)
3. ✅ Bug occurs with various link types (YouTube, news, GitHub, Twitter, blog)
4. ✅ Bug occurs regardless of group size (5, 10, 20 members tested)

## Expected Behavior After Fix

After implementing the fix (removing the forced type overwrite), the test should PASS:

- `msg.Type` should remain as `"text"` (or whatever the frontend originally set)
- Link Preview data should be preserved in `msg.LinkPreview`
- Flutter frontend should successfully parse the message without crashing
- Messages should display correctly with Link Preview UI

## Next Steps

1. ✅ Bug condition exploration test written and run (Task 2.1)
2. ⏭️ Write preservation property tests (Task 2.2)
3. ⏭️ Implement the fix (Task 2.3.1)
4. ⏭️ Verify this test passes after fix (Task 2.3.2)
5. ⏭️ Verify preservation tests still pass (Task 2.3.3)

## Test Command

To run this test:
```bash
cd backend
go test -v -run TestProperty_LinkPreviewTypePreservation ./internal/usecase/
```

## Notes

- This is a **bug condition exploration test** - it is EXPECTED to FAIL on unfixed code
- The test failure confirms the bug exists and validates our root cause analysis
- The test encodes the expected behavior and will validate the fix when it passes after implementation
- DO NOT attempt to fix the test or the code at this stage - the failure is the correct outcome
