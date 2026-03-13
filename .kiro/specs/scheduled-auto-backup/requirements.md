# Requirements Document

## Introduction

This document specifies requirements for enhancing the Google Drive auto-backup feature in a Flutter app with scheduled backup capabilities. The current system performs auto-backup checks only when the app resumes to foreground and uses a simple 24-hour interval. The enhancement will allow users to configure a specific time for daily backups and implement intelligent trigger logic to ensure backups occur at the scheduled time.

## Glossary

- **Backup_Manager**: The Flutter StateNotifier class responsible for managing backup operations, state, and Google Drive integration
- **Backup_State**: The state object containing backup configuration and status information
- **Auto_Backup_Time**: A user-configured time string in "HH:mm" format (24-hour) specifying when daily backups should occur
- **Scheduled_Time**: The time of day configured by the user for automatic backups
- **Last_Backup_Date**: ISO 8601 timestamp string of the most recent successful backup
- **Backup_Already_Happened_Today**: Boolean condition indicating whether a backup has been performed on the current calendar date
- **Foreground_Wake_Up_Compensation**: Logic that executes a missed scheduled backup when the user opens the app after the scheduled time has passed
- **Background_Task**: An operation that runs when the app is not in the foreground, typically using platform-specific scheduling mechanisms
- **Shared_Preferences**: Flutter's persistent key-value storage mechanism for user settings
- **Crypto_Service**: The service responsible for encryption and decryption of backup data
- **Google_Drive_Service**: The service handling Google Drive authentication and file operations

## Requirements

### Requirement 1: User-Configurable Backup Time

**User Story:** As a user, I want to configure a specific time for daily automatic backups, so that backups occur at a convenient time without manual intervention.

#### Acceptance Criteria

1. THE Backup_State SHALL include an optional Auto_Backup_Time field stored as a string in "HH:mm" format
2. WHEN setAutoBackupTime is called with a valid time string, THE Backup_Manager SHALL update the Backup_State with the new Auto_Backup_Time
3. WHEN setAutoBackupTime is called with a valid time string, THE Backup_Manager SHALL persist the Auto_Backup_Time to Shared_Preferences
4. WHEN _loadSettings is executed, THE Backup_Manager SHALL load the Auto_Backup_Time from Shared_Preferences into Backup_State
5. IF Auto_Backup_Time is not set in Shared_Preferences, THEN THE Backup_Manager SHALL set Auto_Backup_Time to null in Backup_State

### Requirement 2: Time-Based Backup Trigger Logic

**User Story:** As a user, I want backups to occur at my configured time once per day, so that I have predictable and consistent backup behavior.

#### Acceptance Criteria

1. WHEN _checkAutoBackup is called AND Auto_Backup_Time is null, THE Backup_Manager SHALL use the existing 24-hour interval logic
2. WHEN _checkAutoBackup is called AND Auto_Backup_Time is configured AND current time has passed the Scheduled_Time AND Backup_Already_Happened_Today is false, THE Backup_Manager SHALL execute signInSilently and call backupNow
3. WHEN _checkAutoBackup is called AND Auto_Backup_Time is configured AND current time has not passed the Scheduled_Time, THE Backup_Manager SHALL not execute a backup
4. WHEN _checkAutoBackup is called AND Auto_Backup_Time is configured AND Backup_Already_Happened_Today is true, THE Backup_Manager SHALL not execute a backup
5. WHEN determining Backup_Already_Happened_Today, THE Backup_Manager SHALL compare the calendar date of Last_Backup_Date with the current calendar date
6. WHEN backupNow completes successfully, THE Backup_Manager SHALL update Last_Backup_Date to the current timestamp

### Requirement 3: Foreground Wake-Up Compensation

**User Story:** As a user, I want missed scheduled backups to execute when I open the app, so that backups still occur even if the app wasn't running at the scheduled time.

#### Acceptance Criteria

1. WHEN the app resumes to foreground AND Auto_Backup_Time is configured AND current time is after Scheduled_Time AND Backup_Already_Happened_Today is false, THE Backup_Manager SHALL execute the backup immediately
2. WHEN the app resumes to foreground AND Auto_Backup_Time is configured AND Backup_Already_Happened_Today is true, THE Backup_Manager SHALL not execute a backup
3. WHEN Foreground_Wake_Up_Compensation executes a backup, THE Backup_Manager SHALL follow the same authentication and backup flow as scheduled backups

### Requirement 4: Background Execution Preparation

**User Story:** As a developer, I want the backup logic structured to support future background execution, so that migration to background tasks is straightforward.

#### Acceptance Criteria

1. THE Backup_Manager SHALL include code comments documenting the limitation that backups only trigger on app foreground resume
2. THE Backup_Manager SHALL include code comments identifying the need for future integration with a background task package such as workmanager
3. THE Backup_Manager SHALL structure the backup execution logic (exportAllConversationsToJSON and Google_Drive_Service upload) to be callable independently of UI lifecycle
4. THE Backup_Manager SHALL include code comments explaining that background execution requires handling authentication state in headless mode
5. THE Backup_Manager SHALL include code comments noting that background execution may require additional platform permissions

### Requirement 5: Backward Compatibility

**User Story:** As a user with existing auto-backup enabled, I want the enhanced feature to work seamlessly with my current settings, so that my backup workflow is not disrupted.

#### Acceptance Criteria

1. WHEN Auto_Backup_Time is null AND autoBackupEnabled is true, THE Backup_Manager SHALL continue using the existing 24-hour interval backup logic
2. WHEN upgrading to the new version, THE Backup_Manager SHALL preserve existing autoBackupEnabled and Last_Backup_Date settings
3. THE Backup_Manager SHALL maintain compatibility with existing Crypto_Service encryption and decryption operations
4. THE Backup_Manager SHALL maintain compatibility with existing Google_Drive_Service authentication and upload operations

### Requirement 6: Time Format Validation

**User Story:** As a developer, I want time input validation to prevent invalid configurations, so that the system remains stable and predictable.

#### Acceptance Criteria

1. WHEN setAutoBackupTime receives a time string, THE Backup_Manager SHALL validate the format matches "HH:mm" where HH is 00-23 and mm is 00-59
2. IF setAutoBackupTime receives an invalid time string, THEN THE Backup_Manager SHALL not update Backup_State or Shared_Preferences
3. IF setAutoBackupTime receives an invalid time string, THEN THE Backup_Manager SHALL set an error in Backup_State describing the validation failure
4. WHEN parsing Auto_Backup_Time for comparison, THE Backup_Manager SHALL handle parsing errors gracefully without crashing

### Requirement 7: Time Comparison Accuracy

**User Story:** As a user, I want backup scheduling to respect time zones and date boundaries correctly, so that backups occur at the expected local time.

#### Acceptance Criteria

1. WHEN comparing current time to Scheduled_Time, THE Backup_Manager SHALL use the device's local time zone
2. WHEN determining if Scheduled_Time has passed, THE Backup_Manager SHALL compare hours and minutes of the current time to the configured Auto_Backup_Time
3. WHEN determining Backup_Already_Happened_Today, THE Backup_Manager SHALL compare calendar dates in the device's local time zone
4. WHEN the date changes from one day to the next, THE Backup_Manager SHALL reset the Backup_Already_Happened_Today condition to false
