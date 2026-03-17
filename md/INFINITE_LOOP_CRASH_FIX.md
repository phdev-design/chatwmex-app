# Infinite Loop Crash Fix - LocalDbService

## Problem
Database initialization was crashing in an infinite loop due to duplicate column migration attempts for `is_decrypted`.

## Root Cause
1. `_ensureMessagesColumns()` was called on every `onOpen`, not just during upgrades
2. Column detection logic was incorrect - using `whereType<String>()` instead of explicit cast
3. No error handling for duplicate column errors
4. Migration logic was duplicated in both `onUpgrade` and `_ensureMessagesColumns`

## Fixes Applied

### Fix 1: Corrected Column Detection Logic
**Location:** `_ensureMessagesColumns()` method

**Before:**
```dart
final existing = columns
    .map((row) => row['name'])
    .whereType<String>()
    .toSet();
```

**After:**
```dart
final existing = columns
    .map((row) => row['name'] as String)
    .toSet();
```

**Why:** The `PRAGMA table_info(messages)` returns rows where `name` is always a String. Using `whereType<String>()` was filtering incorrectly, causing the check to fail and repeatedly attempt to add the column.

### Fix 2: Added Duplicate Column Error Handling
**Location:** `_ensureMessagesColumns()` method

**Added:**
```dart
try {
  await db.execute(entry.value);
  await _logDbEvent('db_repair', {'add_column': entry.key});
} catch (e) {
  if (e.toString().contains('duplicate column')) {
    await _logDbEvent('db_repair', {
      'add_column': entry.key,
      'status': 'already_exists',
    });
    continue;
  }
  rethrow;
}
```

**Why:** If ALTER TABLE fails because the column already exists, we now catch this specific error and continue gracefully instead of crashing.

### Fix 3: Removed db_repair from onOpen
**Location:** `_openDatabase()` method

**Before:**
```dart
onOpen: (db) async {
  await _ensureMessagesColumns(db);  // ❌ Called on every open
  await _createPublicKeysTable(db);
  final version = await db.rawQuery('PRAGMA user_version');
  await _logDbEvent('db_open', {'version': version});
},
```

**After:**
```dart
onOpen: (db) async {
  await _createPublicKeysTable(db);  // ✅ Only ensure public_keys table
  final version = await db.rawQuery('PRAGMA user_version');
  await _logDbEvent('db_open', {'version': version});
},
```

**Why:** `_ensureMessagesColumns()` should only run during `onUpgrade`, not on every database open. This prevents unnecessary migration checks and potential errors.

### Fix 4: Cleaned Up onUpgrade Logic
**Location:** `_openDatabase()` method

**Before:**
```dart
onUpgrade: (db, oldVersion, newVersion) async {
  await _ensureMessagesColumns(db);  // Always called
  if (oldVersion < 5) {
    await _createPublicKeysTable(db);
  }
  if (oldVersion < 6) {
    await db.execute('ALTER TABLE messages ADD COLUMN is_decrypted INTEGER DEFAULT 0');
  }
  await _logDbEvent('db_upgrade', {'from': oldVersion, 'to': newVersion});
},
```

**After:**
```dart
onUpgrade: (db, oldVersion, newVersion) async {
  if (oldVersion < 5) {
    await _createPublicKeysTable(db);
  }
  if (oldVersion < 6) {
    await _ensureMessagesColumns(db);  // ✅ Only called for version 6 upgrade
  }
  await _logDbEvent('db_upgrade', {'from': oldVersion, 'to': newVersion});
},
```

**Why:** The `is_decrypted` column is part of version 6, so `_ensureMessagesColumns()` should only run when upgrading to version 6. This prevents redundant migration attempts.

## Testing Recommendations

1. **Clean Install Test:** Delete the app and reinstall to verify `onCreate` works correctly
2. **Upgrade Test:** Install an older version, then upgrade to verify `onUpgrade` works correctly
3. **Reopen Test:** Close and reopen the app multiple times to verify no infinite loop
4. **Log Verification:** Check `chat_cache.log` to ensure no duplicate column errors

## Expected Behavior After Fix

- Database opens successfully on first launch
- Database upgrades correctly from version 5 to 6
- No duplicate column errors in logs
- No infinite loop crashes
- `is_decrypted` column exists and functions correctly
