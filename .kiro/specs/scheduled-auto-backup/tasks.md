# Implementation Plan: Scheduled Auto-Backup

## Overview

This implementation enhances the existing BackupManager in the Flutter app to support user-configurable scheduled backup times. The approach maintains backward compatibility with the existing 24-hour interval logic while adding time-based scheduling with foreground compensation. All changes are isolated to the BackupManager and BackupState classes, with no modifications required to CryptoService or GoogleDriveService.

## Tasks

- [x] 1. Enhance BackupState data model
  - Add autoBackupTime field (String?) to BackupState class
  - Add autoBackupTime parameter to copyWith method
  - Update constructor to accept autoBackupTime parameter
  - _Requirements: 1.1_

- [ ]* 1.1 Write property test for BackupState
  - **Property 1: Time Setting Persistence Round-Trip**
  - **Validates: Requirements 1.2, 1.3**

- [ ] 2. Implement time validation and setting method
  - [x] 2.1 Implement _validateTimeFormat helper method
    - Create regex pattern for "HH:mm" format validation (00-23 hours, 00-59 minutes)
    - Return boolean indicating format validity
    - _Requirements: 6.1_
  
  - [ ]* 2.2 Write property test for time format validation
    - **Property 7: Time Format Validation**
    - **Validates: Requirements 6.1**
  
  - [x] 2.3 Implement setAutoBackupTime method
    - Validate input using _validateTimeFormat
    - Handle null input (disable scheduled backups)
    - Persist to SharedPreferences using key 'autoBackupTime'
    - Update BackupState with new value or error message
    - _Requirements: 1.2, 1.3, 6.2, 6.3_
  
  - [ ]* 2.4 Write property test for invalid input rejection
    - **Property 8: Invalid Input Rejection**
    - **Validates: Requirements 6.2, 6.3**

- [ ] 3. Implement date and time comparison helpers
  - [x] 3.1 Implement _hasBackupHappenedToday method
    - Return false if lastBackupDate is null
    - Parse lastBackupDate ISO 8601 string to DateTime
    - Compare year, month, day fields with DateTime.now()
    - Handle parsing errors gracefully (return false, log to debug)
    - _Requirements: 2.5, 7.3_
  
  - [ ]* 3.2 Write property test for date comparison
    - **Property 5: Date Comparison Accuracy**
    - **Validates: Requirements 2.5**
  
  - [ ]* 3.3 Write property test for daily reset behavior
    - **Property 11: Daily Reset Behavior**
    - **Validates: Requirements 7.4**
  
  - [x] 3.4 Implement _isScheduledTimePassed method
    - Return false if autoBackupTime is null
    - Parse autoBackupTime string to extract hour and minute
    - Construct DateTime for today at scheduled time
    - Compare with DateTime.now() using isAfter()
    - Handle parsing errors gracefully (return false, log to debug)
    - _Requirements: 7.1, 7.2, 6.4_
  
  - [ ]* 3.5 Write property test for time comparison logic
    - **Property 10: Time Comparison Logic**
    - **Validates: Requirements 7.2**
  
  - [ ]* 3.6 Write property test for graceful parsing error handling
    - **Property 9: Graceful Parsing Error Handling**
    - **Validates: Requirements 6.4**

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Refactor _checkAutoBackup method
  - [x] 5.1 Add backward compatibility branch for null autoBackupTime
    - Check if autoBackupTime is null
    - If null, execute existing 24-hour interval logic
    - Parse lastBackupDate and check if 24 hours have passed
    - Call signInSilently and backupNow if interval exceeded
    - _Requirements: 2.1, 5.1_
  
  - [x] 5.2 Implement scheduled time logic branch
    - Check if backup already happened today using _hasBackupHappenedToday
    - Return early if backup already occurred
    - Check if scheduled time has passed using _isScheduledTimePassed
    - Return early if scheduled time not yet reached
    - Call signInSilently and backupNow if conditions met
    - _Requirements: 2.2, 2.3, 2.4, 3.1_
  
  - [x] 5.3 Add code comments for background execution preparation
    - Document limitation: backups only trigger on foreground resume
    - Note future integration point for workmanager or similar package
    - Explain headless authentication requirements for background mode
    - Note platform permissions needed (SCHEDULE_EXACT_ALARM, background modes)
    - _Requirements: 4.1, 4.2, 4.4, 4.5_
  
  - [ ]* 5.4 Write property test for scheduled backup execution
    - **Property 2: Scheduled Backup Execution When Time Passed**
    - **Validates: Requirements 2.2**
  
  - [ ]* 5.5 Write property test for no backup before scheduled time
    - **Property 3: No Backup Before Scheduled Time**
    - **Validates: Requirements 2.3**
  
  - [ ]* 5.6 Write property test for no duplicate backup same day
    - **Property 4: No Duplicate Backup Same Day**
    - **Validates: Requirements 2.4**

- [x] 6. Update _loadSettings method
  - Add loading of autoBackupTime from SharedPreferences using key 'autoBackupTime'
  - Pass loaded autoBackupTime to BackupState in copyWith call
  - Handle null case (key not present in SharedPreferences)
  - _Requirements: 1.4, 1.5, 5.2_

- [ ] 7. Verify backupNow updates timestamp
  - [x] 7.1 Confirm backupNow updates lastBackupDate in BackupState
    - Review existing backupNow implementation
    - Verify lastBackupDate is set to current timestamp on success
    - Ensure timestamp is in ISO 8601 format
    - _Requirements: 2.6_
  
  - [ ]* 7.2 Write property test for backup timestamp update
    - **Property 6: Backup Updates Timestamp**
    - **Validates: Requirements 2.6**

- [x] 8. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ]* 9. Write unit tests for edge cases
  - Test valid time formats ("00:00", "12:00", "23:59")
  - Test invalid time formats ("24:00", "12:60", "1:30", "abc", empty string, whitespace)
  - Test backward compatibility (null autoBackupTime with 24-hour interval)
  - Test date boundary behavior (backup across midnight transition)
  - Test first-time user (null lastBackupDate)
  - Test SharedPreferences persistence across app restart
  - Test error propagation to BackupState
  - Test corrupted SharedPreferences data handling
  - _Requirements: All_

- [ ]* 10. Write integration tests
  - Test complete flow: set time → app resume → backup execution
  - Test foreground wake-up compensation scenario
  - Test interaction with CryptoService during scheduled backup
  - Test interaction with GoogleDriveService during scheduled backup
  - Test state transitions through multiple backup cycles
  - _Requirements: 3.1, 3.2, 3.3, 4.3, 5.3, 5.4_

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property tests should run with minimum 100 iterations each
- All time comparisons use device local timezone (DateTime.now())
- Backward compatibility is maintained: null autoBackupTime uses 24-hour interval logic
- No changes required to CryptoService or GoogleDriveService
- Background execution support is prepared through code comments but not implemented
- Test organization: place tests in test/core/backup/ directory
