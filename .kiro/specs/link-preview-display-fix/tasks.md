# Implementation Plan

- [ ] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - Link Preview Text Visibility
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope the property to concrete failing cases: link previews with non-empty title and/or description in different theme/sender contexts
  - Test that link preview cards with non-empty title and description display visible text with proper contrast against the background
  - Test across all combinations: dark/light mode × incoming/outgoing messages
  - The test assertions should verify that title uses appropriate color (not colorScheme.onSurface) and description uses appropriate color (not colorScheme.onSurfaceVariant)
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS (this is correct - it proves the bug exists)
  - Document counterexamples found: specific theme/sender combinations where text is invisible
  - Use Flutter DevTools to inspect widget tree and confirm color values match hypothesis (colorScheme.onSurface/onSurfaceVariant)
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 2.1, 2.2, 2.3_

- [ ] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Link Preview Non-Text Elements
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for non-text aspects of link preview
  - Observe: Image thumbnails display correctly with CachedNetworkImageWidget
  - Observe: Tapping link preview launches URL in external browser
  - Observe: Empty title/description fields are not rendered (conditional logic works)
  - Observe: Container styling (padding, border, background) renders correctly
  - Write property-based tests capturing these observed behavior patterns from Preservation Requirements
  - Property-based testing generates many test cases for stronger guarantees
  - Test image display with various URL formats (valid, invalid, missing)
  - Test tap gesture with various URL formats
  - Test conditional rendering with different title/description combinations (empty/non-empty)
  - Test container styling remains unchanged
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ] 3. Fix for link preview text visibility

  - [ ] 3.1 Implement the fix in message_bubble.dart
    - Replace title text color: Change line 286 from `color: colorScheme.onSurface` to `color: textColor`
    - Replace description text color: Change line 299 from `color: colorScheme.onSurfaceVariant` to `color: subtleTextColor`
    - Verify textColor and subtleTextColor variables (lines 63-66) are accessible in scope
    - Ensure no other changes to link preview card structure or behavior
    - _Bug_Condition: isBugCondition(input) where (input.preview.title.isNotEmpty OR input.preview.description.isNotEmpty) AND text uses colorScheme colors directly_
    - _Expected_Behavior: Title and description text SHALL display with colors that provide sufficient contrast against tokens.replyBackground background_
    - _Preservation: Image thumbnail display, tap behavior, conditional rendering logic, container styling, and maximum width constraint must remain unchanged_
    - _Requirements: 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ] 3.2 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - Link Preview Text Visibility
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - Verify text is visible in all theme/sender combinations (dark/light × incoming/outgoing)
    - Verify title uses textColor and description uses subtleTextColor
    - Verify text has proper contrast against background
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ] 3.3 Verify preservation tests still pass
    - **Property 2: Preservation** - Link Preview Non-Text Elements
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - Verify image thumbnails still display correctly
    - Verify tap gesture still launches URL
    - Verify conditional rendering still works
    - Verify container styling unchanged
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all tests still pass after fix (no regressions)

- [ ] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
