# Implementation Plan: Encrypted Audio Messaging UI Completion

## Overview

This implementation completes the encrypted audio messaging feature by enhancing the recording UI with slide-to-cancel gesture and accidental touch protection, verifying database schema compatibility, integrating state management for encrypted audio sending, adding legacy audio caching, and providing comprehensive test coverage. The core encryption/decryption logic already exists in ChatRepository and AudioCacheService.

## Tasks

- [x] 1. Enhance ChatInputBar with gesture detection and recording controls
  - [x] 1.1 Add gesture tracking state variables to ChatInputBar
    - Add `_recordingStartPosition`, `_currentDragPosition`, `_isCancelThresholdReached` state variables
    - Add constants `_cancelThreshold` (100.0) and `_minRecordingDuration` (1 second)
    - _Requirements: 1.1, 2.1, 9.1, 9.2_
  
  - [x] 1.2 Implement permission checking in onLongPressStart
    - Check microphone permission before starting recording
    - Show SnackBar with "需要麥克風權限才能錄音" message if denied
    - Add action button to open system settings
    - Provide haptic feedback on permission denial
    - _Requirements: 3.1, 3.2, 3.3, 3.4_
  
  - [x] 1.3 Implement slide-to-cancel gesture detection
    - Track initial touch position in onLongPressStart
    - Update current drag position in onLongPressMoveUpdate
    - Calculate horizontal drag distance and check against threshold
    - Provide haptic feedback when threshold is reached
    - _Requirements: 1.1, 1.3, 8.4, 9.2_
  
  - [x] 1.4 Implement recording completion logic in onLongPressEnd
    - Check if cancelled by slide gesture (distance > 100px)
    - Check if recording is too short (< 1 second)
    - Show toast "錄音時間過短" for short recordings
    - Call stopRecordingAndSend for valid recordings
    - Reset all gesture tracking state after completion
    - _Requirements: 1.1, 1.5, 2.1, 2.3, 2.4, 9.3, 9.5_
  
  - [x] 1.5 Add visual feedback for slide-to-cancel gesture
    - Display "← 滑動取消" text during normal recording
    - Change to "🚫 鬆開取消" in red when threshold exceeded
    - Animate recording UI to follow finger position during drag
    - _Requirements: 1.2, 8.1, 8.2, 8.3_
  
  - [x] 1.6 Write widget tests for ChatInputBar gesture detection
    - **Property 1: Slide-to-cancel gesture detection**
    - **Property 2: Visual feedback during slide gesture**
    - **Property 5: Short recording rejection**
    - **Validates: Requirements 1.1, 1.2, 2.1, 8.1, 8.2**

- [x] 2. Implement state management integration in ChatRoomProvider
  - [x] 2.1 Add cancelRecording method to ChatRoomProvider
    - Stop recording via MediaService
    - Set isRecording state to false
    - Delete temporary audio file
    - Add debug logging for cleanup operations
    - _Requirements: 1.4, 2.2_
  
  - [x] 2.2 Update stopRecordingAndSend with proper error handling
    - Verify recording path is valid before sending
    - Call chatRepository.sendAudioMessage with correct roomId/receiverId
    - Add returned message to chat state
    - Delete temporary audio file after successful send
    - Handle errors and still clean up temp file on failure
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_
  
  - [x] 2.3 Write unit tests for ChatRoomProvider audio methods
    - **Property 3: Temporary file cleanup**
    - **Property 4: Recording state reset**
    - **Property 10: Audio message sending integration**
    - **Property 11: Message state update after send**
    - **Validates: Requirements 1.4, 1.5, 6.1, 6.2, 6.3, 6.4, 6.5**

- [x] 3. Verify and test database schema for file_key column
  - [x] 3.1 Verify file_key column exists in messages table schema
    - Check CREATE TABLE statement includes `file_key TEXT`
    - Verify _ensureMessagesColumns includes file_key migration logic
    - Confirm Message.fromMap and Message.toMap handle fileKey correctly
    - _Requirements: 4.1, 4.2, 4.3, 4.4_
  
  - [x] 3.2 Write unit tests for database schema and migration
    - **Property 8: Database file_key round-trip**
    - **Property 9: Migration data preservation**
    - **Validates: Requirements 4.1, 4.2, 4.3, 5.2, 5.3, 5.4, 5.5**

- [x] 4. Checkpoint - Verify recording and state management
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement legacy audio caching in AudioMessageBubble
  - [x] 5.1 Update _loadAndPlay method to handle legacy audio
    - Check if fileKey is null or empty to identify legacy audio
    - Call _downloadAndCacheLegacyAudio for legacy messages
    - Use existing encrypted audio flow for messages with fileKey
    - Handle AudioCacheException and display error messages
    - _Requirements: 7.1, 7.2, 7.3_
  
  - [x] 5.2 Implement _downloadAndCacheLegacyAudio method
    - Generate cache key using format "legacy_{messageId}"
    - Check if audio is already cached before downloading
    - Download audio directly from URL using Dio
    - Save downloaded audio to cache directory with proper filename
    - Return local file path for playback
    - _Requirements: 7.1, 7.4, 7.5, 12.1, 12.2, 12.3, 12.5_
  
  - [x] 5.3 Write widget tests for AudioMessageBubble caching
    - **Property 12: Legacy audio caching on first play**
    - **Property 13: Legacy audio cache hit**
    - **Property 14: Legacy audio cache filename format**
    - **Validates: Requirements 7.1, 7.2, 7.4, 12.1**

- [x] 6. Add cache validation to AudioCacheService
  - [x] 6.1 Expose getCacheFilePath method for legacy audio
    - Make _getCacheFilePath public or add helper method
    - Return cache file path for given message ID
    - _Requirements: 12.1, 12.2_
  
  - [x] 6.2 Add cache file validation logic
    - Verify cached file exists before returning as available
    - Check file is readable
    - Handle corrupted cache files by re-downloading
    - _Requirements: 12.3, 12.4_
  
  - [x] 6.3 Write unit tests for AudioCacheService validation
    - **Property 16: Cache file validation**
    - **Validates: Requirements 12.3, 12.4**

- [x] 7. Final checkpoint - Integration verification
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- The design uses Dart/Flutter, so all implementations should follow Flutter best practices
- Core encryption/decryption logic already exists and doesn't need modification
- Database schema already includes file_key column, only verification needed
- Property tests should run minimum 100 iterations for comprehensive coverage
- All temporary audio files must be cleaned up to avoid storage leaks
