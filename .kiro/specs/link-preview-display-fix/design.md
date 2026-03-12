# Link Preview Display Fix - Bugfix Design

## Overview

Link preview cards in chat messages receive complete data from the backend (URL, Title, Description, ImageURL) but the title and description text fields are not visible in the UI. The bug appears to be a color contrast issue where text is being rendered with colors that match or are too similar to the background, making them invisible. The image thumbnail displays correctly, indicating the data flow and widget structure are working properly. The fix will involve correcting the text color assignments in the link preview card to use appropriate theme-aware colors that provide sufficient contrast against the background.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug - when a link preview card is rendered with non-empty title and/or description fields
- **Property (P)**: The desired behavior - title and description text should be visible with appropriate color contrast against the background
- **Preservation**: Existing image thumbnail display, tap behavior, and conditional rendering logic that must remain unchanged
- **linkPreviewCard**: The widget in `app/lib/features/chat/ui/widgets/message_bubble.dart` (lines 231-310) that renders the link preview UI
- **tokens**: The `ChatSurfaceTokens` instance that provides theme-aware colors for chat UI elements
- **colorScheme**: The Material Design `ColorScheme` that provides standard theme colors
- **textColor**: The variable that determines text color based on whether the message is sent by the current user (isMe)
- **replyBackground**: The background color used for the link preview card container

## Bug Details

### Bug Condition

The bug manifests when a link preview card is rendered with non-empty title and/or description fields. The text widgets are created and positioned correctly in the widget tree, but they use `colorScheme.onSurface` and `colorScheme.onSurfaceVariant` colors directly without considering the actual background color (`tokens.replyBackground`) or the message sender context (isMe). This causes the text to have insufficient contrast or match the background, making it invisible.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type LinkPreviewRenderContext
  OUTPUT: boolean
  
  RETURN (input.preview.title.isNotEmpty OR input.preview.description.isNotEmpty)
         AND input.linkPreviewCard.background == tokens.replyBackground
         AND (input.titleTextColor == colorScheme.onSurface 
              OR input.descriptionTextColor == colorScheme.onSurfaceVariant)
         AND NOT textIsVisible(input.titleText, input.descriptionText)
END FUNCTION
```

### Examples


- **Incoming message with link preview**: User receives a message with a link preview containing title "Flutter Documentation" and description "Official Flutter docs". The image thumbnail displays correctly, but the title and description text are invisible because they use `colorScheme.onSurface` which may not contrast with `tokens.replyBackground`.

- **Outgoing message with link preview**: User sends a message with a link preview containing title "GitHub Repository" and description "Open source project". The image thumbnail displays correctly, but the title and description text are invisible because the colors don't account for the `isMe` context.

- **Dark theme link preview**: In dark mode, the link preview card uses `tokens.replyBackground` (Color(0xFF1E2A30) - dark blue-gray), but the text uses `colorScheme.onSurface` which may be too similar, resulting in invisible text.

- **Light theme link preview**: In light mode, the link preview card uses `tokens.replyBackground` (colorScheme.surfaceContainerHigh), but the text color assignment doesn't guarantee sufficient contrast.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Image thumbnail display must continue to work correctly with `CachedNetworkImageWidget`
- Tap gesture to launch URL in external browser must continue to work
- Conditional rendering logic (if title.isNotEmpty, if description.isNotEmpty) must remain unchanged
- Link icon fallback when no image is available must continue to display
- Container styling (padding, border, borderRadius) must remain unchanged
- Maximum width constraint (60% of screen width) must remain unchanged

**Scope:**
All inputs that do NOT involve rendering title or description text in the link preview card should be completely unaffected by this fix. This includes:
- Image thumbnail rendering and caching behavior
- Tap gesture handling and URL launching
- Container layout and decoration
- Icon display for links without images
- Link preview data fetching and logging

## Hypothesized Root Cause

Based on the bug description and code analysis, the most likely issues are:

1. **Incorrect Color Assignment for Link Preview Text**: The title and description text widgets (lines 281-301 in message_bubble.dart) use `colorScheme.onSurface` and `colorScheme.onSurfaceVariant` directly, without considering:
   - The actual background color (`tokens.replyBackground`) which differs from standard surface colors
   - The message sender context (`isMe`) which affects whether the message is in an incoming or outgoing bubble
   - Theme-specific color tokens that are already computed for chat bubbles (`textColor`, `subtleTextColor`)

2. **Missing Theme Context Awareness**: The link preview card is rendered inside a message bubble that already has theme-aware color variables (`textColor` for primary text, `subtleTextColor` for secondary text) based on the `isMe` flag, but these variables are not used for the link preview text.

3. **Background Color Mismatch**: The link preview uses `tokens.replyBackground` which is a specialized chat theme color, but the text colors are from the standard Material Design `colorScheme` which may not provide sufficient contrast with this specific background.


4. **Inconsistent Color Strategy**: Other parts of the message bubble correctly use `textColor` and `subtleTextColor` variables (computed at lines 63-66), but the link preview card bypasses this pattern and uses `colorScheme` colors directly.

## Correctness Properties

Property 1: Bug Condition - Link Preview Text Visibility

_For any_ link preview card rendered with non-empty title and/or description fields, the fixed code SHALL display the title text using a color that provides sufficient contrast against the `tokens.replyBackground` background, and the description text using a color that provides sufficient contrast while indicating secondary information hierarchy, ensuring both text fields are clearly visible and readable.

**Validates: Requirements 2.1, 2.2, 2.3**

Property 2: Preservation - Link Preview Non-Text Elements

_For any_ link preview card rendering that does NOT involve title or description text display (image thumbnails, tap gestures, container styling, conditional rendering logic), the fixed code SHALL produce exactly the same behavior as the original code, preserving all existing functionality for image display, URL launching, and layout.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `app/lib/features/chat/ui/widgets/message_bubble.dart`

**Function**: `build` method of `_MessageBubbleState` class

**Specific Changes**:

1. **Replace Title Text Color**: Change line 286 from `color: colorScheme.onSurface` to `color: textColor`
   - This ensures the title uses the same theme-aware color as other primary text in the message bubble
   - The `textColor` variable already accounts for `isMe` context and theme brightness

2. **Replace Description Text Color**: Change line 299 from `color: colorScheme.onSurfaceVariant` to `color: subtleTextColor`
   - This ensures the description uses the same theme-aware color as other secondary text in the message bubble
   - The `subtleTextColor` variable already accounts for `isMe` context and theme brightness

3. **Verify Color Variable Scope**: Ensure `textColor` and `subtleTextColor` variables (defined at lines 63-66) are accessible in the link preview card construction scope
   - These variables are already defined in the same `build` method scope, so no scope changes are needed

4. **Test Color Contrast**: After the fix, verify that:
   - In dark mode, incoming messages: title and description are visible against dark background
   - In dark mode, outgoing messages: title and description are visible against green/blue background
   - In light mode, incoming messages: title and description are visible against light background
   - In light mode, outgoing messages: title and description are visible against primary container background


## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code by capturing screenshots or visual inspection showing invisible text, then verify the fix works correctly across all theme and sender combinations while preserving existing image and interaction behavior.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis (color assignment issue). If we refute, we will need to re-hypothesize.

**Test Plan**: Create test messages with link previews containing title and description in both incoming and outgoing message contexts, in both light and dark themes. Visually inspect or capture screenshots to confirm text is invisible. Use Flutter DevTools to inspect the widget tree and verify that Text widgets exist with the hypothesized color values. Run these tests on the UNFIXED code to observe the invisible text and confirm the color values match our hypothesis.

**Test Cases**:
1. **Dark Mode Incoming Message**: Send a link preview from another user in dark mode (will show invisible text on unfixed code)
   - Expected: Title uses `colorScheme.onSurface`, description uses `colorScheme.onSurfaceVariant`
   - Expected: Text is invisible or barely visible against `tokens.replyBackground` (Color(0xFF1E2A30))

2. **Dark Mode Outgoing Message**: Send a link preview as current user in dark mode (will show invisible text on unfixed code)
   - Expected: Title uses `colorScheme.onSurface`, description uses `colorScheme.onSurfaceVariant`
   - Expected: Text is invisible or barely visible against outgoing bubble background

3. **Light Mode Incoming Message**: Send a link preview from another user in light mode (will show invisible text on unfixed code)
   - Expected: Title uses `colorScheme.onSurface`, description uses `colorScheme.onSurfaceVariant`
   - Expected: Text may have insufficient contrast against `tokens.replyBackground`

4. **Light Mode Outgoing Message**: Send a link preview as current user in light mode (will show invisible text on unfixed code)
   - Expected: Title uses `colorScheme.onSurface`, description uses `colorScheme.onSurfaceVariant`
   - Expected: Text may have insufficient contrast against primary container background

**Expected Counterexamples**:
- Text widgets exist in the widget tree but are not visible in the rendered UI
- Possible causes: color values match or are too similar to background, incorrect color assignment, missing theme context

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds (link previews with non-empty title/description), the fixed function produces the expected behavior (visible text with proper contrast).

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  result := renderLinkPreviewCard_fixed(input)
  ASSERT textIsVisible(result.titleText)
  ASSERT textIsVisible(result.descriptionText)
  ASSERT hasProperContrast(result.titleColor, result.backgroundColor)
  ASSERT hasProperContrast(result.descriptionColor, result.backgroundColor)
END FOR
```


### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold (image display, tap behavior, conditional rendering), the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT renderLinkPreviewCard_original(input) = renderLinkPreviewCard_fixed(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain (different link preview configurations)
- It catches edge cases that manual unit tests might miss (empty title, empty description, no image, etc.)
- It provides strong guarantees that behavior is unchanged for all non-text-color aspects

**Test Plan**: Observe behavior on UNFIXED code first for image display, tap gestures, and conditional rendering, then write property-based tests capturing that behavior to ensure it remains unchanged after the fix.

**Test Cases**:
1. **Image Thumbnail Preservation**: Observe that image thumbnails display correctly on unfixed code, then write test to verify this continues after fix
   - Test with valid image URLs, invalid image URLs, and missing image URLs
   - Verify `CachedNetworkImageWidget` is called with correct parameters
   - Verify fallback icon displays when no image is available

2. **Tap Gesture Preservation**: Observe that tapping link preview launches URL on unfixed code, then write test to verify this continues after fix
   - Test with various URL formats (http, https, with/without www)
   - Verify `launchUrl` is called with correct URI and launch mode
   - Verify gesture detector responds to taps

3. **Conditional Rendering Preservation**: Observe that empty title/description are not rendered on unfixed code, then write test to verify this continues after fix
   - Test with empty title, non-empty description
   - Test with non-empty title, empty description
   - Test with both empty
   - Verify conditional widgets are not built when fields are empty

4. **Container Styling Preservation**: Observe that container styling (padding, border, background) works correctly on unfixed code, then write test to verify this continues after fix
   - Verify padding values remain unchanged
   - Verify border radius and color remain unchanged
   - Verify background color uses `tokens.replyBackground`

### Unit Tests

- Test link preview rendering with non-empty title and description in dark mode (incoming message)
- Test link preview rendering with non-empty title and description in dark mode (outgoing message)
- Test link preview rendering with non-empty title and description in light mode (incoming message)
- Test link preview rendering with non-empty title and description in light mode (outgoing message)
- Test that title uses `textColor` variable after fix
- Test that description uses `subtleTextColor` variable after fix
- Test edge cases: only title, only description, both empty (should not render text widgets)

### Property-Based Tests

- Generate random link preview data (title, description, imageUrl combinations) and verify text is visible when non-empty
- Generate random theme configurations (light/dark, different color schemes) and verify text contrast is sufficient
- Generate random message sender contexts (isMe true/false) and verify appropriate colors are used
- Test that all non-text aspects (image display, tap behavior, layout) remain unchanged across many scenarios

### Integration Tests

- Test full chat flow with link preview messages in both incoming and outgoing contexts
- Test switching between light and dark themes and verify link preview text remains visible
- Test that tapping link preview opens URL in external browser
- Test that link preview images load and display correctly
- Test that messages without link previews continue to display normally
