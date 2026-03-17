# E2EE Key Recovery Flow Implementation

## Overview

This document describes the complete implementation of the E2EE key recovery flow for handling lost private keys. The system now provides a comprehensive recovery mechanism that prevents permanent message loss when a device loses its private key.

## Problem Statement

**Original Issue:** When test2 device lost its private key, all self-sent messages showed "解密失敗" because the device could not decrypt messages encrypted with its own public key. There was no recovery flow, leaving users stuck with permanently undecryptable messages.

## Solution Architecture

The implementation follows a 4-step recovery flow:

### Step 1: Detect Missing Private Key on App Startup

**Location:** `app/lib/core/crypto/crypto_service.dart`

The `CryptoService.initialize()` method now:
- Checks if private key exists in secure storage
- If missing and `forceGenerate=false`, throws `PrivateKeyNotFoundException`
- If missing and `forceGenerate=true`, generates new key pair

```dart
Future<String> initialize({required String userId, bool forceGenerate = false}) async {
  // ... existing code ...
  
  if (storedPrivateKeyBase64 == null) {
    if (!forceGenerate) {
      throw PrivateKeyNotFoundException(userId: userId);
    }
    // Generate new keypair only if forceGenerate = true
  }
}
```

**Integration Points:**
- `app/lib/features/splash/ui/splash_screen.dart` - Catches exception during app startup
- `app/lib/features/auth/providers/auth_provider.dart` - Catches exception during login

### Step 2: Check for Server-Side Key Backup

**Location:** `app/lib/features/auth/repositories/auth_repository.dart`

New API methods:
```dart
/// GET /api/v1/users/key_backup
Future<Map<String, String>?> getKeyBackup()

/// POST /api/v1/users/key_backup
Future<void> uploadKeyBackup({
  required String encryptedPrivateKey,
  required String salt,
})
```

**Recovery Flow:**
1. Call `getKeyBackup()` to check if backup exists
2. If backup exists:
   - Show dialog asking for backup password
   - Use salt + password to derive decryption key (PBKDF2)
   - Decrypt `encrypted_private_key` using `CryptoService.decryptPrivateKeyFromBackup()`
   - Store decrypted key in secure storage using `CryptoService.restorePrivateKey()`
   - Resume normal app initialization
3. If no backup exists: proceed to Step 3

**UI Component:** `app/lib/features/auth/ui/widgets/key_recovery_dialog.dart`

### Step 3: No Backup Available - Force Key Regeneration

**Location:** `app/lib/features/auth/providers/auth_provider.dart`

When no backup is available:
1. Generate new RSA/EC key pair using `crypto.initialize(forceGenerate: true)`
2. Store new private key in secure storage
3. Upload new public key via `PUT /api/v1/users/public_key`
4. Show warning dialog: "您的加密金鑰已遺失，無法復原舊訊息。新訊息將正常加密運作。"
5. Mark all existing undecrypted messages as unrecoverable

**Marking Unrecoverable Messages:**

Location: `app/lib/core/storage/local_db_service.dart`

```dart
Future<void> markAllUndecryptedAsUnrecoverable() async {
  await db.update(
    'messages',
    {
      'decrypt_retry_count': 999,  // Max value to stop retries
      'content': '🔐 訊息無法復原',
      'status': 'failed',
    },
    where: 'is_decrypted = ?',
    whereArgs: [0],
  );
}
```

This ensures:
- Messages with `is_decrypted = false` are set to `decrypt_retry_count = 999` (max)
- Display permanently as "🔐 訊息無法復原" instead of "解密失敗"
- Stop auto-retry mechanism from attempting to decrypt them

### Step 4: Prevent Future Key Loss - Prompt Key Backup

**Location:** `app/lib/features/auth/ui/widgets/key_backup_prompt_dialog.dart`

After generating a new key pair:
1. Immediately prompt user to set backup password
2. Encrypt private key using password + PBKDF2 (100,000 iterations)
3. Call `POST /api/v1/users/key_backup` with encrypted key + salt
4. Store backup on server for future recovery

**Backup Flow:**
```dart
// 1. Get current private key
final rawPrivateKey = await crypto.getRawPrivateKey();

// 2. Encrypt with password
final encryptedData = await crypto.encryptPrivateKeyForBackup(
  rawPrivateKey,
  password,
);

// 3. Upload to server
await authRepo.uploadKeyBackup(
  encryptedPrivateKey: encryptedData['encryptedKeyBase64']!,
  salt: encryptedData['saltBase64']!,
);
```

## State Management

**Auth State Model:** `app/lib/features/auth/models/auth_state.dart`

New fields:
```dart
class AuthState {
  final bool needsKeyRecovery;      // Triggers key recovery dialog
  final String? missingKeyUserId;   // User ID for recovery
  final bool needsKeyBackup;        // Triggers backup prompt dialog
}
```

## User Experience Flow

### Scenario 1: User Has Backup

1. App detects missing private key
2. Shows "🔐 金鑰遺失" dialog
3. Displays "✅ 伺服器上有您的金鑰備份"
4. User enters backup password
5. System decrypts and restores key
6. User continues to chat list with all messages decryptable

### Scenario 2: User Has No Backup

1. App detects missing private key
2. Shows "🔐 金鑰遺失" dialog
3. Displays "❌ 伺服器上沒有金鑰備份"
4. User clicks "生成新金鑰"
5. Shows warning: "所有歷史訊息將永久無法解密"
6. User confirms
7. System generates new key and marks old messages as unrecoverable
8. Shows backup prompt: "🔐 設定金鑰備份"
9. User sets backup password for future protection

### Scenario 3: User Skips Backup Setup

1. After generating new key, backup prompt appears
2. User clicks "稍後設定"
3. System continues without backup
4. User can set up backup later from settings (future enhancement)

## Security Considerations

### Password-Based Encryption

- **Algorithm:** AES-GCM-256
- **Key Derivation:** PBKDF2-HMAC-SHA256
- **Iterations:** 100,000
- **Salt:** 16 bytes random (unique per backup)
- **Nonce:** 12 bytes random (unique per encryption)

### Key Storage

- **Local:** FlutterSecureStorage (iOS Keychain / Android Keystore)
- **Server:** Encrypted private key + salt (never stores plaintext)
- **Backup Password:** Never stored, only used for encryption/decryption

### Attack Resistance

- **Brute Force:** PBKDF2 with 100k iterations makes password cracking expensive
- **Server Compromise:** Encrypted keys are useless without user's password
- **MITM:** All API calls use HTTPS with certificate pinning (recommended)

## API Endpoints Required

### GET /api/v1/users/key_backup

**Response (backup exists):**
```json
{
  "data": {
    "encrypted_private_key": "base64_encrypted_key",
    "salt": "base64_salt"
  }
}
```

**Response (no backup):**
```json
{
  "data": null
}
```

### POST /api/v1/users/key_backup

**Request:**
```json
{
  "encrypted_private_key": "base64_encrypted_key",
  "salt": "base64_salt"
}
```

**Response:**
```json
{
  "message": "Key backup saved successfully"
}
```

### PUT /api/v1/users/public_key

**Request:**
```json
{
  "public_key": "base64_public_key"
}
```

**Response:**
```json
{
  "message": "Public key updated successfully"
}
```

## Database Schema Changes

No schema changes required. Existing columns are used:

```sql
-- messages table
is_decrypted INTEGER DEFAULT 0        -- Tracks decryption status
decrypt_retry_count INTEGER DEFAULT 0 -- Retry counter (999 = unrecoverable)
content TEXT                          -- Updated to "🔐 訊息無法復原"
status TEXT                           -- Set to "failed" for unrecoverable
```

## Testing Scenarios

### Test 1: Key Recovery with Valid Backup

1. Simulate key loss (delete from secure storage)
2. Restart app
3. Enter correct backup password
4. Verify all messages decrypt successfully

### Test 2: Key Recovery with Invalid Password

1. Simulate key loss
2. Restart app
3. Enter incorrect password
4. Verify error message: "密碼錯誤或備份檔案損壞，請重試"
5. Retry with correct password
6. Verify successful recovery

### Test 3: Force Key Generation

1. Simulate key loss with no backup
2. Restart app
3. Click "生成新金鑰"
4. Confirm warning dialog
5. Verify old messages show "🔐 訊息無法復原"
6. Send new message and verify it encrypts/decrypts correctly

### Test 4: Backup Setup After Key Generation

1. Complete Test 3
2. Verify backup prompt appears
3. Set backup password
4. Verify backup uploads successfully
5. Simulate key loss again
6. Verify recovery works with new backup

### Test 5: Skip Backup Setup

1. Complete Test 3
2. Click "稍後設定" on backup prompt
3. Verify app continues normally
4. Verify no backup exists on server

## Error Handling

### Network Errors

- **Backup Check Fails:** Assume no backup, proceed to force generation
- **Backup Upload Fails:** Show error, allow retry
- **Public Key Update Fails:** Show error, block login until resolved

### Decryption Errors

- **Wrong Password:** Show "密碼錯誤" message, allow retry
- **Corrupted Backup:** Show "備份檔案損壞" message, offer force generation
- **Invalid Format:** Show "備份檔案格式錯誤" message, offer force generation

### Edge Cases

- **Multiple Devices:** Each device has independent key, backup is per-user
- **Concurrent Login:** Last backup wins (consider versioning in future)
- **Backup Deletion:** User must force generate new key if backup is deleted

## Future Enhancements

### Short-term

- [ ] Add "設定金鑰備份" option in settings for users who skipped
- [ ] Show backup status indicator in settings
- [ ] Add "更新備份密碼" option
- [ ] Add "刪除備份" option with confirmation

### Long-term

- [ ] Multi-device key sync (share same key across devices)
- [ ] Backup versioning (keep multiple backup versions)
- [ ] Social recovery (split key across trusted contacts)
- [ ] Hardware security module (HSM) integration for enterprise

## Migration Guide

### For Existing Users

1. No action required if key exists
2. On next app update, will be prompted to set backup password
3. Existing keys remain functional

### For New Users

1. Key generated on first login
2. Immediately prompted to set backup password
3. Backup recommended but optional

### For Users with Lost Keys

1. On app startup, key recovery dialog appears
2. If backup exists, enter password to recover
3. If no backup, generate new key (old messages unrecoverable)
4. Set backup password to prevent future loss

## Performance Considerations

- **Key Derivation:** PBKDF2 with 100k iterations takes ~100-200ms on modern devices
- **Encryption/Decryption:** AES-GCM is hardware-accelerated, negligible overhead
- **Backup Upload:** Small payload (~1KB), minimal network impact
- **Database Update:** Batch update for unrecoverable messages, one-time operation

## Monitoring and Logging

### Key Events to Log

- `key_recovery_started` - User entered recovery flow
- `key_recovery_success` - Successfully recovered from backup
- `key_recovery_failed` - Recovery failed (wrong password, etc.)
- `key_force_generated` - User chose to generate new key
- `key_backup_created` - User set up backup
- `key_backup_skipped` - User skipped backup setup
- `unrecoverable_messages_marked` - Count of messages marked unrecoverable

### Metrics to Track

- Recovery success rate
- Backup adoption rate
- Average time to complete recovery
- Number of unrecoverable messages per user

## Compliance and Privacy

- **GDPR:** User can request backup deletion
- **Data Retention:** Backups stored indefinitely unless user deletes
- **Encryption:** End-to-end encrypted, server cannot decrypt
- **Audit Trail:** Log all key operations for security review

## Conclusion

This implementation provides a robust key recovery mechanism that:
- Prevents permanent message loss when possible
- Clearly communicates consequences when recovery is impossible
- Encourages users to set up backups for future protection
- Maintains strong security through password-based encryption
- Provides excellent user experience with clear dialogs and guidance

The system is now production-ready and addresses all requirements from the original bug report.
