# Design Document: Scheduled Auto-Backup

## Overview

This design enhances the existing Google Drive auto-backup feature in the Flutter app by adding user-configurable scheduled backup times. Currently, the BackupManager only checks for backups when the app resumes to foreground and uses a simple 24-hour interval. The enhancement introduces:

1. **Time-based scheduling**: Users can configure a specific daily time (e.g., "02:00") for automatic backups
2. **Foreground compensation**: Missed backups execute when the app opens after the scheduled time
3. **Backward compatibility**: Existing 24-hour interval logic remains functional when no scheduled time is set
4. **Future-ready structure**: Code is organized to facilitate future background task integration

The design maintains compatibility with existing encryption (CryptoService), Google Drive operations (GoogleDriveService), and state persistence (SharedPreferences) while adding minimal complexity to the current StateNotifier-based architecture.

## Architecture

### High-Level Design

The scheduled backup feature extends the existing BackupManager without introducing new services or major architectural changes. The core enhancement is a refactored `_checkAutoBackup()` method that implements time-based logic alongside the existing interval-based approach.

```
┌─────────────────────────────────────────────────────────────┐
│                      BackupManager                          │
│                   (StateNotifier)                           │
├─────────────────────────────────────────────────────────────┤
│  State Management:                                          │
│  • BackupState (enhanced with autoBackupTime field)        │
│  • WidgetsBindingObserver (app lifecycle monitoring)       │
├─────────────────────────────────────────────────────────────┤
│  New/Modified Methods:                                      │
│  • setAutoBackupTime(String? time)                         │
│  • _checkAutoBackup() [REFACTORED]                         │
│  • _hasBackupHappenedToday() → bool                        │
│  • _isScheduledTimePassed() → bool                         │
│  • _validateTimeFormat(String time) → bool                 │
├─────────────────────────────────────────────────────────────┤
│  Existing Methods (unchanged):                              │
│  • backupNow()                                              │
│  • exportAllConversationsToJSON()                          │
│  • signInSilently()                                         │
│  • _loadSettings()                                          │
└─────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌──────────────┐   ┌──────────────────┐   ┌──────────────┐
│SharedPrefs   │   │GoogleDriveService│   │CryptoService │
│(persistence) │   │(upload/download) │   │(encryption)  │
└──────────────┘   └──────────────────┘   └──────────────┘
```

### Decision Logic Flow

The refactored `_checkAutoBackup()` method implements a decision tree:

```
didChangeAppLifecycleState(resumed)
         │
         ▼
   _checkAutoBackup()
         │
         ├─→ autoBackupEnabled? ──NO──→ return
         │                YES
         ▼
   autoBackupTime == null?
         │
         ├─→ YES: Use 24-hour interval logic (backward compatible)
         │        • Check if lastBackupDate + 24h < now
         │        • If yes: signInSilently() → backupNow()
         │
         └─→ NO: Use scheduled time logic
                  │
                  ├─→ _hasBackupHappenedToday()? ──YES──→ return
                  │                NO
                  ▼
            _isScheduledTimePassed()?
                  │
                  ├─→ NO ──→ return (wait for scheduled time)
                  │
                  └─→ YES ──→ signInSilently() → backupNow()
```

### Time Comparison Strategy

Time comparisons use Flutter's `DateTime` class with local timezone:

- **Scheduled time parsing**: Parse "HH:mm" string and construct a DateTime for today at that time
- **Current time**: `DateTime.now()` provides local time
- **Date boundary handling**: Compare `.year`, `.month`, `.day` fields to determine if backup happened today
- **Time-passed check**: Compare current DateTime with scheduled DateTime using `.isAfter()`

This approach avoids timezone conversion complexity and respects the user's local time expectations.

## Components and Interfaces

### BackupState (Enhanced)

```dart
class BackupState {
  final bool isBackingUp;
  final String? lastBackupDate;        // ISO 8601 timestamp
  final bool autoBackupEnabled;
  final String? autoBackupTime;        // NEW: "HH:mm" format or null
  final String? error;
  final String? linkedGoogleEmail;

  BackupState({
    this.isBackingUp = false,
    this.lastBackupDate,
    this.autoBackupEnabled = false,
    this.autoBackupTime,                // NEW field
    this.error,
    this.linkedGoogleEmail,
  });

  BackupState copyWith({
    bool? isBackingUp,
    String? lastBackupDate,
    bool? autoBackupEnabled,
    String? autoBackupTime,              // NEW parameter
    String? error,
    bool clearError = false,
    String? linkedGoogleEmail,
  }) {
    return BackupState(
      isBackingUp: isBackingUp ?? this.isBackingUp,
      lastBackupDate: lastBackupDate ?? this.lastBackupDate,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      autoBackupTime: autoBackupTime ?? this.autoBackupTime,  // NEW
      error: clearError ? null : (error ?? this.error),
      linkedGoogleEmail: linkedGoogleEmail ?? this.linkedGoogleEmail,
    );
  }
}
```

### BackupManager (New/Modified Methods)

#### setAutoBackupTime

```dart
/// Sets the scheduled backup time in "HH:mm" format (24-hour).
/// Pass null to disable scheduled backups and revert to 24-hour interval.
/// 
/// Validates format and persists to SharedPreferences.
/// Sets error state if validation fails.
Future<void> setAutoBackupTime(String? time) async {
  // Validation
  if (time != null && !_validateTimeFormat(time)) {
    state = state.copyWith(
      error: 'Invalid time format. Use HH:mm (00:00 to 23:59)',
      clearError: false,
    );
    return;
  }

  // Persist
  final prefs = await SharedPreferences.getInstance();
  if (time == null) {
    await prefs.remove('autoBackupTime');
  } else {
    await prefs.setString('autoBackupTime', time);
  }

  // Update state
  state = state.copyWith(autoBackupTime: time, clearError: true);
}
```

#### _validateTimeFormat

```dart
/// Validates time string matches "HH:mm" where HH is 00-23 and mm is 00-59.
bool _validateTimeFormat(String time) {
  final regex = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
  return regex.hasMatch(time);
}
```

#### _checkAutoBackup (Refactored)

```dart
/// Checks if an automatic backup should be triggered.
/// 
/// Behavior depends on autoBackupTime configuration:
/// - If null: Uses 24-hour interval logic (backward compatible)
/// - If set: Uses scheduled time logic with daily reset
/// 
/// LIMITATION: This method only runs when app resumes to foreground.
/// For true background execution, integrate with workmanager or similar.
/// Background execution requires:
/// - Platform permissions (Android: SCHEDULE_EXACT_ALARM, iOS: background modes)
/// - Headless authentication handling
/// - Battery optimization exemptions
Future<void> _checkAutoBackup() async {
  if (_isAuthenticating) return;
  if (!state.autoBackupEnabled) return;

  // Backward compatibility: 24-hour interval when no scheduled time
  if (state.autoBackupTime == null) {
    if (state.lastBackupDate != null) {
      try {
        final last = DateTime.parse(state.lastBackupDate!);
        if (DateTime.now().difference(last).inHours < 24) {
          return; // backup was too recent
        }
      } catch (e) {
        debugPrint('[BackupManager] Error parsing lastBackupDate: $e');
      }
    }

    if (await signInSilently()) {
      backupNow();
    }
    return;
  }

  // Scheduled time logic
  if (_hasBackupHappenedToday()) {
    return; // Already backed up today
  }

  if (!_isScheduledTimePassed()) {
    return; // Scheduled time hasn't arrived yet
  }

  // Execute backup (foreground wake-up compensation)
  if (await signInSilently()) {
    backupNow();
  }
}
```

#### _hasBackupHappenedToday

```dart
/// Determines if a backup has already occurred on the current calendar date.
/// Compares lastBackupDate with current date in local timezone.
bool _hasBackupHappenedToday() {
  if (state.lastBackupDate == null) return false;

  try {
    final lastBackup = DateTime.parse(state.lastBackupDate!);
    final now = DateTime.now();

    return lastBackup.year == now.year &&
           lastBackup.month == now.month &&
           lastBackup.day == now.day;
  } catch (e) {
    debugPrint('[BackupManager] Error parsing lastBackupDate: $e');
    return false; // Treat parse errors as "no backup today"
  }
}
```

#### _isScheduledTimePassed

```dart
/// Checks if the current time has passed the configured scheduled time.
/// Returns false if autoBackupTime is invalid or not set.
bool _isScheduledTimePassed() {
  if (state.autoBackupTime == null) return false;

  try {
    final parts = state.autoBackupTime!.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    final now = DateTime.now();
    final scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);

    return now.isAfter(scheduledTime);
  } catch (e) {
    debugPrint('[BackupManager] Error parsing autoBackupTime: $e');
    return false; // Treat parse errors conservatively
  }
}
```

#### _loadSettings (Modified)

```dart
Future<void> _loadSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final lastBackup = prefs.getString('lastBackupDate');
  final autoBackup = prefs.getBool('autoBackupEnabled') ?? false;
  final autoBackupTime = prefs.getString('autoBackupTime');  // NEW

  // Load linked email based on current app user
  final userId = await _storageService.read('user_id');
  String? linkedEmail;
  if (userId != null && userId.isNotEmpty) {
    linkedEmail = prefs.getString('drive_linked_email_$userId');
  }

  state = state.copyWith(
    lastBackupDate: lastBackup,
    autoBackupEnabled: autoBackup,
    autoBackupTime: autoBackupTime,  // NEW
    linkedGoogleEmail: linkedEmail,
  );
}
```

### UI Integration Points

The UI layer (not part of this design) will need to:

1. **Settings screen**: Add a time picker widget that calls `setAutoBackupTime()`
2. **Display current schedule**: Show `state.autoBackupTime` to the user
3. **Error handling**: Display `state.error` when time validation fails
4. **Backward compatibility indicator**: Show "24-hour interval" when `autoBackupTime` is null

## Data Models

### Persistence Schema (SharedPreferences)

| Key | Type | Description | Example |
|-----|------|-------------|---------|
| `autoBackupEnabled` | bool | Whether auto-backup is enabled | `true` |
| `lastBackupDate` | String | ISO 8601 timestamp of last successful backup | `"2024-01-15T14:30:00.000Z"` |
| `autoBackupTime` | String? | Scheduled backup time in HH:mm format | `"02:00"` or null |
| `drive_linked_email_<userId>` | String | Google account linked to user | `"user@gmail.com"` |

### State Transitions

```
Initial State:
  autoBackupEnabled: false
  autoBackupTime: null
  lastBackupDate: null

User enables auto-backup (legacy mode):
  autoBackupEnabled: true
  autoBackupTime: null  ← Uses 24-hour interval
  lastBackupDate: null

User sets scheduled time:
  autoBackupEnabled: true
  autoBackupTime: "02:00"  ← Uses scheduled logic
  lastBackupDate: null

After first backup:
  autoBackupEnabled: true
  autoBackupTime: "02:00"
  lastBackupDate: "2024-01-15T02:05:00.000Z"

Next day before 02:00:
  _hasBackupHappenedToday() → false (different date)
  _isScheduledTimePassed() → false (current time < 02:00)
  → No backup triggered

Next day after 02:00 (app opened at 08:00):
  _hasBackupHappenedToday() → false (no backup yet today)
  _isScheduledTimePassed() → true (08:00 > 02:00)
  → Backup triggered (foreground compensation)

After backup completes:
  lastBackupDate: "2024-01-16T08:00:15.000Z"
  _hasBackupHappenedToday() → true
  → No more backups until next day
```

### Time Format Specification

- **Input format**: `"HH:mm"` (24-hour time)
- **Validation regex**: `^([01]\d|2[0-3]):([0-5]\d)$`
- **Valid examples**: `"00:00"`, `"02:30"`, `"14:45"`, `"23:59"`
- **Invalid examples**: `"24:00"`, `"2:30"`, `"14:60"`, `"25:00"`, `"abc"`


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property Reflection

After analyzing all acceptance criteria, I identified the following testable properties and performed reflection to eliminate redundancy:

**Redundancy Analysis:**
- Properties 2.2, 2.3, and 2.4 test the core scheduling logic from different angles (time passed + no backup today → execute; time not passed → don't execute; backup already today → don't execute). These are complementary and each provides unique validation.
- Property 3.1 and 3.2 duplicate 2.2 and 2.4 in the foreground context, so they are redundant.
- Property 5.1 duplicates 2.1 (backward compatibility), so it's redundant.
- Property 7.3 duplicates 2.5 (date comparison), so it's redundant.
- Properties 6.2 and 6.3 both test invalid input handling and can be combined into a single comprehensive property.

**Final Property Set:** After eliminating redundancy, we have 11 unique properties.

### Property 1: Time Setting Persistence Round-Trip

*For any* valid time string in "HH:mm" format, if we call setAutoBackupTime with that time and then reload settings from SharedPreferences, the loaded autoBackupTime should equal the original time string.

**Validates: Requirements 1.2, 1.3**

### Property 2: Scheduled Backup Execution When Time Passed

*For any* scheduled time that is earlier than the current time on the current day, and any state where no backup has occurred today, calling _checkAutoBackup should trigger a backup (signInSilently and backupNow).

**Validates: Requirements 2.2**

### Property 3: No Backup Before Scheduled Time

*For any* scheduled time that is later than the current time on the current day, calling _checkAutoBackup should not trigger a backup.

**Validates: Requirements 2.3**

### Property 4: No Duplicate Backup Same Day

*For any* state where lastBackupDate is on the current calendar date, calling _checkAutoBackup should not trigger a backup regardless of the scheduled time.

**Validates: Requirements 2.4**

### Property 5: Date Comparison Accuracy

*For any* two timestamps, _hasBackupHappenedToday should return true if and only if the lastBackupDate timestamp has the same year, month, and day as the current date in local timezone.

**Validates: Requirements 2.5**

### Property 6: Backup Updates Timestamp

*For any* successful execution of backupNow, the lastBackupDate in BackupState should be updated to a timestamp representing the current time.

**Validates: Requirements 2.6**

### Property 7: Time Format Validation

*For any* string input, _validateTimeFormat should return true if and only if the string matches the pattern "HH:mm" where HH is 00-23 and mm is 00-59.

**Validates: Requirements 6.1**

### Property 8: Invalid Input Rejection

*For any* invalid time string, calling setAutoBackupTime should result in: (1) no change to the autoBackupTime field in BackupState, (2) no change to SharedPreferences, and (3) an error message set in BackupState.

**Validates: Requirements 6.2, 6.3**

### Property 9: Graceful Parsing Error Handling

*For any* malformed time string stored in autoBackupTime, calling _isScheduledTimePassed should not throw an exception and should return false.

**Validates: Requirements 6.4**

### Property 10: Time Comparison Logic

*For any* scheduled time "HH:mm" and any current time, _isScheduledTimePassed should return true if and only if the current hour is greater than HH, or the current hour equals HH and the current minute is greater than mm.

**Validates: Requirements 7.2**

### Property 11: Daily Reset Behavior

*For any* lastBackupDate that is on a different calendar date than the current date, _hasBackupHappenedToday should return false, enabling a new backup to occur.

**Validates: Requirements 7.4**

## Error Handling

### Validation Errors

**Time Format Validation:**
- **Error condition**: User provides invalid time format (e.g., "25:00", "2:30", "abc")
- **Handling**: `setAutoBackupTime()` validates input using regex, sets error in state, does not persist invalid value
- **User feedback**: UI displays error message from `state.error`
- **Recovery**: User corrects input and resubmits

**Parsing Errors:**
- **Error condition**: Corrupted autoBackupTime in SharedPreferences (e.g., manual editing)
- **Handling**: `_isScheduledTimePassed()` catches parse exceptions, logs to debug, returns false (conservative behavior)
- **Impact**: Backup won't trigger until valid time is set or app is restarted with corrected data
- **Recovery**: User can set new valid time through UI

### Authentication Errors

**Silent Sign-In Failure:**
- **Error condition**: `signInSilently()` returns false (token expired, network issue, account removed)
- **Handling**: `_checkAutoBackup()` exits early without calling `backupNow()`
- **Impact**: Backup is skipped for this trigger; will retry on next app resume
- **User feedback**: No immediate feedback (silent failure by design); user can manually trigger backup to see error
- **Recovery**: User can manually sign in through UI, which will refresh tokens

**Backup Execution Errors:**
- **Error condition**: `backupNow()` fails (network error, Drive API error, insufficient storage)
- **Handling**: Error is caught in `backupNow()`, set in `state.error`, `isBackingUp` set to false
- **Impact**: `lastBackupDate` is not updated, so backup will retry on next app resume
- **User feedback**: Error displayed in UI from `state.error`
- **Recovery**: User resolves underlying issue (network, storage) and backup retries automatically

### Date/Time Edge Cases

**Daylight Saving Time Transitions:**
- **Scenario**: Clock jumps forward/backward during DST change
- **Handling**: DateTime comparisons use local time, so scheduled time adjusts with system clock
- **Impact**: Backup may occur 1 hour earlier/later on DST transition day (acceptable trade-off)
- **Mitigation**: None required; behavior is consistent with user expectations of "local time"

**Date Boundary at Midnight:**
- **Scenario**: App resumes at 23:59, scheduled time is 02:00, date changes to next day at 00:00
- **Handling**: `_hasBackupHappenedToday()` compares dates, so after midnight it returns false (new day)
- **Impact**: If scheduled time (02:00) hasn't passed yet on new day, backup waits until 02:00
- **Correctness**: Behavior is correct; backup occurs once per calendar day

**Last Backup Date Null:**
- **Scenario**: First-time user or after clearing app data
- **Handling**: `_hasBackupHappenedToday()` returns false when `lastBackupDate` is null
- **Impact**: Backup will trigger if scheduled time has passed (correct first-run behavior)

### Backward Compatibility Edge Cases

**Upgrading from 24-Hour Interval:**
- **Scenario**: User has autoBackupEnabled=true, lastBackupDate set, but no autoBackupTime
- **Handling**: `_checkAutoBackup()` detects null autoBackupTime and uses 24-hour interval logic
- **Impact**: No behavior change for existing users until they configure scheduled time
- **Correctness**: Preserves existing functionality

**Mixed State (autoBackupEnabled=false, autoBackupTime set):**
- **Scenario**: User disables auto-backup but scheduled time remains in SharedPreferences
- **Handling**: `_checkAutoBackup()` exits early if `autoBackupEnabled` is false
- **Impact**: Scheduled time is ignored (correct behavior)
- **Recovery**: When user re-enables auto-backup, scheduled time is still available

## Testing Strategy

### Dual Testing Approach

This feature requires both unit tests and property-based tests for comprehensive coverage:

- **Unit tests**: Verify specific examples, edge cases, and integration points
- **Property-based tests**: Verify universal properties across randomized inputs

### Property-Based Testing Configuration

**Library Selection:**
- Use `test` package with custom property-based testing helpers or integrate a library like `dartz` for property testing in Dart
- Minimum 100 iterations per property test to ensure adequate randomization coverage

**Test Tagging:**
Each property test must include a comment referencing the design property:
```dart
// Feature: scheduled-auto-backup, Property 1: Time Setting Persistence Round-Trip
test('setAutoBackupTime persists and reloads correctly', () async {
  // Property-based test with 100+ iterations
});
```

### Unit Test Coverage

**Specific Examples:**
1. **Valid time formats**: Test common times ("00:00", "12:00", "23:59")
2. **Invalid time formats**: Test edge cases ("24:00", "12:60", "1:30", "abc")
3. **Backward compatibility**: Test null autoBackupTime with 24-hour interval logic
4. **Date boundary**: Test backup behavior across midnight transition
5. **First-time user**: Test behavior when lastBackupDate is null

**Integration Points:**
1. **SharedPreferences persistence**: Verify settings survive app restart
2. **State updates**: Verify BackupState reflects changes correctly
3. **Error propagation**: Verify errors from validation reach UI state

**Edge Cases:**
1. **Empty string time**: Verify treated as invalid
2. **Whitespace in time**: Verify "02:00 " is rejected
3. **Corrupted SharedPreferences**: Verify graceful handling of malformed data

### Property-Based Test Specifications

**Property 1: Time Setting Persistence Round-Trip**
- **Generator**: Random valid time strings ("00:00" to "23:59")
- **Test**: Set time → reload settings → verify equality
- **Iterations**: 100

**Property 2: Scheduled Backup Execution When Time Passed**
- **Generator**: Random scheduled times in the past (relative to mocked current time)
- **Test**: Mock time, set scheduled time, call _checkAutoBackup → verify backup triggered
- **Iterations**: 100

**Property 3: No Backup Before Scheduled Time**
- **Generator**: Random scheduled times in the future
- **Test**: Mock time, set scheduled time, call _checkAutoBackup → verify no backup
- **Iterations**: 100

**Property 4: No Duplicate Backup Same Day**
- **Generator**: Random lastBackupDate on current day
- **Test**: Set lastBackupDate to today, call _checkAutoBackup → verify no backup
- **Iterations**: 100

**Property 5: Date Comparison Accuracy**
- **Generator**: Random pairs of timestamps (same day vs different days)
- **Test**: Verify _hasBackupHappenedToday returns correct boolean
- **Iterations**: 100

**Property 6: Backup Updates Timestamp**
- **Generator**: Random initial states
- **Test**: Call backupNow → verify lastBackupDate is updated to recent timestamp
- **Iterations**: 100

**Property 7: Time Format Validation**
- **Generator**: Random strings (mix of valid and invalid formats)
- **Test**: Verify _validateTimeFormat returns correct boolean
- **Iterations**: 200 (to cover wide range of invalid inputs)

**Property 8: Invalid Input Rejection**
- **Generator**: Random invalid time strings
- **Test**: Call setAutoBackupTime → verify state unchanged, error set
- **Iterations**: 100

**Property 9: Graceful Parsing Error Handling**
- **Generator**: Random malformed strings
- **Test**: Set autoBackupTime to malformed value, call _isScheduledTimePassed → verify no exception
- **Iterations**: 100

**Property 10: Time Comparison Logic**
- **Generator**: Random pairs of (scheduled time, current time)
- **Test**: Verify _isScheduledTimePassed returns correct boolean based on time comparison
- **Iterations**: 100

**Property 11: Daily Reset Behavior**
- **Generator**: Random lastBackupDate on different days (past/future)
- **Test**: Verify _hasBackupHappenedToday returns false for different dates
- **Iterations**: 100

### Test Mocking Strategy

**Time Mocking:**
- Mock `DateTime.now()` to control current time in tests
- Use dependency injection or test-specific clock abstraction

**SharedPreferences Mocking:**
- Use `SharedPreferences.setMockInitialValues()` for unit tests
- Verify persistence without actual file I/O

**Service Mocking:**
- Mock `GoogleDriveService.signInSilently()` to control authentication results
- Mock `backupNow()` to verify it's called without executing full backup

### Test Organization

```
test/
  core/
    backup/
      backup_manager_test.dart          # Unit tests
      backup_manager_property_test.dart # Property-based tests
      test_helpers/
        time_generator.dart             # Random time string generator
        date_generator.dart             # Random date generator
        mock_clock.dart                 # Mockable clock for time control
```

### Continuous Integration

- Run all tests on every commit
- Property tests run with fixed seed for reproducibility
- Fail build if any property test fails
- Track test execution time (property tests may be slower due to iterations)

