# Requirements Document

## Introduction

This feature completes the encrypted audio messaging implementation by enhancing the recording UI/UX, ensuring database schema compatibility, connecting state management layers, adding legacy audio caching, and providing comprehensive test coverage. The core encryption/decryption logic already exists in ChatRepository and AudioCacheService.

## Glossary

- **Chat_Input_Bar**: The UI component that handles user input including text messages, attachments, and voice recording
- **Recording_Session**: A single voice recording interaction from start to completion or cancellation
- **Slide_To_Cancel**: A gesture where the user drags their finger horizontally while recording to cancel the recording
- **Accidental_Touch**: A recording session lasting less than 1 second, considered unintentional
- **Media_Service**: The service responsible for handling microphone permissions and audio recording
- **Local_DB_Service**: The SQLite database service managing message persistence
- **Migration**: The process of updating the database schema while preserving existing data
- **Chat_Room_Provider**: The state management layer coordinating chat operations
- **Audio_Message_Bubble**: The UI component displaying and playing audio messages
- **Legacy_Audio**: Unencrypted audio messages (fileKey is null or empty) from before encryption was implemented
- **Audio_Cache**: Local storage of downloaded audio files to avoid repeated network requests
- **File_Key**: The symmetric encryption key stored with encrypted audio messages

## Requirements

### Requirement 1: Slide to Cancel Gesture

**User Story:** As a user, I want to slide my finger horizontally while recording to cancel the voice message, so that I can easily discard unwanted recordings without sending them.

#### Acceptance Criteria

1. WHEN the user is recording AND drags their finger more than 100 pixels horizontally from the initial touch point, THE Chat_Input_Bar SHALL cancel the Recording_Session without sending
2. WHILE the user is dragging horizontally during recording, THE Chat_Input_Bar SHALL display visual feedback indicating cancellation will occur
3. WHEN the Recording_Session is cancelled via slide gesture, THE Chat_Input_Bar SHALL provide haptic feedback
4. WHEN the Recording_Session is cancelled, THE Chat_Input_Bar SHALL delete the temporary audio file
5. WHEN the user releases their finger after sliding to cancel, THE Chat_Input_Bar SHALL reset to the initial state

### Requirement 2: Accidental Touch Protection

**User Story:** As a user, I want recordings shorter than 1 second to be automatically discarded, so that accidental taps on the microphone button don't send empty or meaningless audio messages.

#### Acceptance Criteria

1. WHEN the user ends a Recording_Session AND the recording duration is less than 1 second, THE Chat_Input_Bar SHALL discard the recording without sending
2. WHEN a recording is discarded due to short duration, THE Chat_Input_Bar SHALL delete the temporary audio file
3. WHEN a recording is discarded due to short duration, THE Chat_Input_Bar SHALL display a brief toast message "錄音時間過短"
4. WHEN the user ends a Recording_Session AND the recording duration is 1 second or more, THE Chat_Input_Bar SHALL proceed with sending the audio message

### Requirement 3: Microphone Permission Error Handling

**User Story:** As a user, I want to see a clear error message when microphone permission is denied, so that I understand why recording isn't working and know how to fix it.

#### Acceptance Criteria

1. WHEN the user attempts to start recording AND Media_Service microphone permission is denied, THE Chat_Input_Bar SHALL display an error SnackBar with message "需要麥克風權限才能錄音"
2. WHEN microphone permission is denied, THE Chat_Input_Bar SHALL include an action button in the SnackBar to open system settings
3. WHEN the user attempts to start recording AND Media_Service throws a permission exception, THE Chat_Input_Bar SHALL not enter recording state
4. WHEN permission is denied, THE Chat_Input_Bar SHALL provide haptic feedback indicating an error

### Requirement 4: Database Schema Verification

**User Story:** As a developer, I want to ensure the messages table includes the file_key column, so that encrypted audio messages can be properly stored and retrieved.

#### Acceptance Criteria

1. THE Local_DB_Service messages table CREATE TABLE statement SHALL include a file_key TEXT column
2. WHEN the database is created for the first time, THE Local_DB_Service SHALL create the messages table with the file_key column
3. WHEN querying messages, THE Local_DB_Service SHALL correctly map the file_key column to the Message model fileKey property
4. WHEN inserting messages with fileKey, THE Local_DB_Service SHALL persist the file_key value to the database

### Requirement 5: Database Migration for Existing Users

**User Story:** As an existing user, I want my app to continue working after an update, so that I don't lose my message history or experience database errors.

#### Acceptance Criteria

1. WHEN the app is updated AND the database version changes, THE Local_DB_Service SHALL execute the onUpgrade callback
2. WHEN onUpgrade is executed, THE Local_DB_Service SHALL add the file_key column if it doesn't exist
3. WHEN onUpgrade is executed, THE Local_DB_Service SHALL preserve all existing message data
4. WHEN the database is opened, THE Local_DB_Service SHALL verify all required columns exist via _ensureMessagesColumns
5. IF any required column is missing during database open, THE Local_DB_Service SHALL add the missing column without data loss

### Requirement 6: Encrypted Audio Sending Integration

**User Story:** As a user, I want my voice messages to be encrypted automatically, so that my conversations remain private and secure.

#### Acceptance Criteria

1. WHEN Chat_Room_Provider stopRecordingAndSend is called AND a valid audio file path is returned, THE Chat_Room_Provider SHALL call chatRepository.sendAudioMessage with the audio file path
2. WHEN calling sendAudioMessage, THE Chat_Room_Provider SHALL pass the correct roomId for group chats
3. WHEN calling sendAudioMessage, THE Chat_Room_Provider SHALL pass the correct receiverId for direct messages
4. WHEN sendAudioMessage completes successfully, THE Chat_Room_Provider SHALL add the returned message to the chat state
5. WHEN sendAudioMessage completes, THE Chat_Room_Provider SHALL delete the temporary audio file

### Requirement 7: Legacy Audio Local Caching

**User Story:** As a user, I want old unencrypted audio messages to be cached locally after first download, so that I don't waste bandwidth replaying the same messages.

#### Acceptance Criteria

1. WHEN Audio_Message_Bubble plays Legacy_Audio for the first time, THE Audio_Message_Bubble SHALL download the audio file to Audio_Cache
2. WHEN Audio_Message_Bubble plays Legacy_Audio that exists in Audio_Cache, THE Audio_Message_Bubble SHALL play from the cached file
3. WHEN downloading Legacy_Audio fails, THE Audio_Message_Bubble SHALL display an error message and allow retry
4. WHEN Legacy_Audio is cached, THE Audio_Message_Bubble SHALL store it with a unique filename based on message ID
5. THE Audio_Cache for Legacy_Audio SHALL use the same cache directory as encrypted audio

### Requirement 8: Slide to Cancel UI Feedback

**User Story:** As a user, I want to see visual feedback while sliding to cancel, so that I know when the cancellation threshold is reached.

#### Acceptance Criteria

1. WHILE the user is dragging horizontally during recording, THE Chat_Input_Bar SHALL display a "← 滑動取消" text indicator
2. WHEN the drag distance exceeds the cancellation threshold, THE Chat_Input_Bar SHALL change the indicator to "🚫 鬆開取消" with a different color
3. WHILE dragging, THE Chat_Input_Bar SHALL animate the recording UI element to follow the finger position
4. WHEN the drag distance exceeds the threshold, THE Chat_Input_Bar SHALL provide haptic feedback once

### Requirement 9: Recording UI State Management

**User Story:** As a developer, I want the recording UI state to be properly managed, so that the interface remains consistent and responsive.

#### Acceptance Criteria

1. WHEN recording starts, THE Chat_Input_Bar SHALL track the initial touch position
2. WHILE recording, THE Chat_Input_Bar SHALL continuously monitor the current touch position
3. WHEN recording ends, THE Chat_Input_Bar SHALL reset all gesture tracking state
4. WHEN the user navigates away from the chat screen while recording, THE Chat_Input_Bar SHALL automatically cancel the recording
5. WHEN recording is cancelled or completed, THE Chat_Input_Bar SHALL reset the recording timer to 0

### Requirement 10: Widget Tests for Recording Features

**User Story:** As a developer, I want comprehensive tests for the recording UI, so that I can confidently refactor and maintain the code.

#### Acceptance Criteria

1. THE test suite SHALL include a widget test verifying slide to cancel gesture detection
2. THE test suite SHALL include a widget test verifying recordings under 1 second are discarded
3. THE test suite SHALL include a widget test verifying permission denied error handling
4. THE test suite SHALL include a widget test verifying the recording UI displays correctly
5. THE test suite SHALL include a widget test verifying the slide to cancel visual feedback

### Requirement 11: Unit Tests for State Management

**User Story:** As a developer, I want unit tests for the audio sending logic, so that I can ensure the encryption flow works correctly.

#### Acceptance Criteria

1. THE test suite SHALL include a unit test verifying stopRecordingAndSend calls sendAudioMessage with correct parameters
2. THE test suite SHALL include a unit test verifying temporary audio files are deleted after sending
3. THE test suite SHALL include a unit test verifying error handling when sendAudioMessage fails
4. THE test suite SHALL include a unit test verifying the recording state is properly reset after completion
5. THE test suite SHALL include a unit test verifying recordings under 1 second are not sent

### Requirement 12: Legacy Audio Cache Management

**User Story:** As a user, I want the app to manage cached audio efficiently, so that it doesn't consume excessive storage space.

#### Acceptance Criteria

1. WHEN Legacy_Audio is cached, THE Audio_Cache SHALL store the file with a predictable naming pattern
2. THE Audio_Cache SHALL provide a method to check if a Legacy_Audio file is already cached
3. WHEN checking for cached Legacy_Audio, THE Audio_Cache SHALL verify the file exists and is readable
4. IF a cached Legacy_Audio file is corrupted, THE Audio_Cache SHALL re-download the file
5. THE Audio_Cache SHALL use the same cache directory structure for both encrypted and Legacy_Audio files
