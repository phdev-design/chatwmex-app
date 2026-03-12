# Implementation Plan

- [x] 1. Write bug condition exploration test
  - **Property 1: Bug Condition** - URL Validation Before Caching
  - **CRITICAL**: This test MUST FAIL on unfixed code - failure confirms the bug exists
  - **DO NOT attempt to fix the test or the code when it fails**
  - **NOTE**: This test encodes the expected behavior - it will validate the fix when it passes after implementation
  - **GOAL**: Surface counterexamples that demonstrate the bug exists
  - **Scoped PBT Approach**: Scope the property to concrete failing cases: empty string, null, and encrypted Base64 URLs
  - Test that `ImageCacheService.cacheImage()` throws DioException with "No host specified in URI" for invalid URLs
  - Test cases:
    - `cacheImage("")` - empty string URL
    - `cacheImage(null)` - null URL
    - `cacheImage("U2FsdGVkX1+abc123...xyz789==")` - encrypted Base64 string (length ≥40 with +/= characters)
    - Link Preview with encrypted imageUrl
  - Run test on UNFIXED code
  - **EXPECTED OUTCOME**: Test FAILS with DioException (this is correct - it proves the bug exists)
  - Document counterexamples found to understand root cause
  - Mark task complete when test is written, run, and failure is documented
  - _Requirements: 1.1, 1.2, 1.3_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Valid URL Caching Behavior
  - **IMPORTANT**: Follow observation-first methodology
  - Observe behavior on UNFIXED code for valid URL inputs:
    - Complete URLs: `https://example.com/image.jpg`
    - Relative paths: `/uploads/images/abc123.jpg`
    - MongoDB ObjectIDs: `507f1f77bcf86cd799439011` (24 hex characters)
  - Write property-based tests capturing observed behavior patterns:
    - For all valid complete URLs (http:// or https://), cacheImage successfully downloads and caches
    - For all valid relative paths (/uploads/...), cacheImage correctly resolves and caches
    - For all valid MongoDB ObjectIDs (24 hex chars), cacheImage correctly resolves and caches
    - Cache cleanup continues to work when size exceeds 500MB
    - resolveFullUrl continues to return correct URLs for valid inputs
  - Property-based testing generates many test cases for stronger guarantees
  - Run tests on UNFIXED code
  - **EXPECTED OUTCOME**: Tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 3. Fix for image cache decryption handling

  - [x] 3.1 Add URL validation to ImageCacheService.cacheImage()
    - Add check at method start: if url is null or empty, return null immediately
    - Add URL format validation using `Uri.tryParse(url)`
    - If parse fails or URI has no host, return null with warning message
    - Improve error messages to distinguish "URL invalid" from "download failed"
    - File: `app/lib/core/media/image_cache_service.dart`
    - _Bug_Condition: isBugCondition(input) where input is empty/null/invalid URL or encrypted Base64 (length ≥40 with +/= chars)_
    - _Expected_Behavior: cacheImage returns null without throwing DioException for invalid URLs_
    - _Preservation: Valid URLs (complete, relative paths, MongoDB ObjectIDs) continue to download and cache correctly_
    - _Requirements: 1.1, 1.2, 2.2, 2.5_

  - [x] 3.2 Handle empty imageUrl in Link Preview rendering
    - Identify Link Preview rendering component (likely in chat message widgets)
    - Add check: if linkPreview.imageUrl is null or empty, show fallback icon
    - Use resolveFullUrl to validate imageUrl before attempting to load
    - Only pass valid URLs to image loading component
    - _Bug_Condition: Link Preview with encrypted or empty imageUrl_
    - _Expected_Behavior: Display fallback icon instead of attempting to load invalid URL_
    - _Preservation: Link Previews with valid imageUrl continue to display correctly_
    - _Requirements: 1.3, 2.3_

  - [x] 3.3 Verify resolveFullUrl logic remains unchanged
    - Confirm resolveFullUrl correctly detects encrypted Base64 strings (≥40 chars with +/= chars)
    - Confirm it returns empty string with warning for encrypted content
    - Confirm it continues to handle valid URLs, relative paths, and MongoDB ObjectIDs
    - File: `app/lib/features/chat/utils/chat_url_utils.dart`
    - _Preservation: resolveFullUrl behavior for all valid inputs remains unchanged_
    - _Requirements: 3.4, 3.5_

  - [x] 3.4 Verify bug condition exploration test now passes
    - **Property 1: Expected Behavior** - URL Validation Before Caching
    - **IMPORTANT**: Re-run the SAME test from task 1 - do NOT write a new test
    - The test from task 1 encodes the expected behavior
    - When this test passes, it confirms the expected behavior is satisfied
    - Run bug condition exploration test from step 1
    - **EXPECTED OUTCOME**: Test PASSES (confirms bug is fixed)
    - Verify cacheImage returns null for empty/null/invalid URLs without throwing DioException
    - _Requirements: 2.2, 2.5_

  - [x] 3.5 Verify preservation tests still pass
    - **Property 2: Preservation** - Valid URL Caching Behavior
    - **IMPORTANT**: Re-run the SAME tests from task 2 - do NOT write new tests
    - Run preservation property tests from step 2
    - **EXPECTED OUTCOME**: Tests PASS (confirms no regressions)
    - Confirm all valid URL caching scenarios still work correctly
    - Confirm cache cleanup, resolveFullUrl, and Link Preview for valid URLs unchanged
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 4. Checkpoint - Ensure all tests pass
  - Run all unit tests for ImageCacheService
  - Run all integration tests for message decryption and Link Preview
  - Verify no DioException "No host specified in URI" errors in logs
  - Verify encrypted messages display correctly after decryption
  - Ensure all tests pass, ask the user if questions arise
