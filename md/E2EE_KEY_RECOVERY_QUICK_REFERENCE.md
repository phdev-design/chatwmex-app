# E2EE Key Recovery - Quick Reference

## For Developers

### Key Files Modified/Created

```
app/lib/core/crypto/crypto_service.dart
  ✓ Added PrivateKeyNotFoundException
  ✓ Modified initialize() to throw exception when key missing
  ✓ Added forceGenerate parameter

app/lib/features/auth/repositories/auth_repository.dart
  ✓ Added getKeyBackup() - GET /users/key_backup
  ✓ Added uploadKeyBackup() - POST /users/key_backup

app/lib/features/auth/providers/auth_provider.dart
  ✓ Added recoverKeyFromBackup() method
  ✓ Modified forceGenerateNewKey() to mark unrecoverable messages
  ✓ Added needsKeyBackup state handling

app/lib/features/auth/models/auth_state.dart
  ✓ Added needsKeyRecovery field
  ✓ Added missingKeyUserId field
  ✓ Added needsKeyBackup field

app/lib/features/auth/ui/widgets/key_recovery_dialog.dart
  ✓ NEW: Dialog for key recovery flow

app/lib/features/auth/ui/widgets/key_backup_prompt_dialog.dart
  ✓ NEW: Dialog for backup setup prompt

app/lib/features/splash/ui/splash_screen.dart
  ✓ Added PrivateKeyNotFoundException handling
  ✓ Added key backup prompt check

app/lib/core/storage/local_db_service.dart
  ✓ Added markAllUndecryptedAsUnrecoverable() method
```

### API Endpoints Required (Backend)

```
GET  /api/v1/users/key_backup
POST /api/v1/users/key_backup
PUT  /api/v1/users/public_key (already exists)
```

### Testing Commands

```bash
# Run all tests
cd app
flutter test

# Run specific test
flutter test test/core/crypto/crypto_service_bug_exploration_test.dart

# Check for compilation errors
flutter analyze
```

### Common Issues and Solutions

**Issue:** Dialog not showing
- Check `needsKeyRecovery` state in AuthViewModel
- Verify `PrivateKeyNotFoundException` is being thrown
- Check dialog listener in login_page.dart and splash_screen.dart

**Issue:** Backup upload fails
- Verify backend API is implemented
- Check network connectivity
- Verify JWT token is valid

**Issue:** Messages still show "解密失敗"
- Verify `markAllUndecryptedAsUnrecoverable()` was called
- Check database update query
- Verify UI reads from updated database

## For Backend Developers

### API Implementation Guide

#### GET /api/v1/users/key_backup

```go
// Handler
func (h *UserHandler) GetKeyBackup(c *gin.Context) {
    userID := c.GetString("user_id") // from JWT
    
    backup, err := h.repo.GetKeyBackup(userID)
    if err != nil {
        c.JSON(200, gin.H{"data": nil})
        return
    }
    
    c.JSON(200, gin.H{
        "data": gin.H{
            "encrypted_private_key": backup.EncryptedPrivateKey,
            "salt": backup.Salt,
        },
    })
}

// Database Schema
CREATE TABLE user_key_backups (
    user_id VARCHAR(255) PRIMARY KEY,
    encrypted_private_key TEXT NOT NULL,
    salt VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

#### POST /api/v1/users/key_backup

```go
// Request Model
type KeyBackupRequest struct {
    EncryptedPrivateKey string `json:"encrypted_private_key" binding:"required"`
    Salt                string `json:"salt" binding:"required"`
}

// Handler
func (h *UserHandler) CreateKeyBackup(c *gin.Context) {
    userID := c.GetString("user_id")
    
    var req KeyBackupRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(400, gin.H{"error": "Invalid request"})
        return
    }
    
    err := h.repo.UpsertKeyBackup(userID, req.EncryptedPrivateKey, req.Salt)
    if err != nil {
        c.JSON(500, gin.H{"error": "Failed to save backup"})
        return
    }
    
    c.JSON(200, gin.H{"message": "Key backup saved successfully"})
}
```

### Security Checklist

- [ ] Validate JWT token on all endpoints
- [ ] Rate limit backup creation (max 10/hour per user)
- [ ] Log all backup operations for audit
- [ ] Encrypt database at rest
- [ ] Use HTTPS only
- [ ] Implement backup deletion endpoint for GDPR compliance

## For QA/Testers

### Test Scenarios

#### Scenario 1: First Time User
1. Register new account
2. Verify key generated automatically
3. Verify backup prompt appears
4. Set backup password
5. Verify backup saved successfully

#### Scenario 2: Key Recovery (Success)
1. Login with existing account
2. Manually delete key from device (simulate loss)
3. Restart app
4. Verify recovery dialog appears
5. Enter correct backup password
6. Verify all messages decrypt correctly

#### Scenario 3: Key Recovery (Wrong Password)
1. Follow Scenario 2 steps 1-4
2. Enter incorrect password
3. Verify error message appears
4. Retry with correct password
5. Verify recovery succeeds

#### Scenario 4: Force Key Generation
1. Login with account that has no backup
2. Manually delete key from device
3. Restart app
4. Click "生成新金鑰"
5. Confirm warning dialog
6. Verify old messages show "🔐 訊息無法復原"
7. Send new message
8. Verify new message encrypts/decrypts correctly

#### Scenario 5: Skip Backup Setup
1. Complete Scenario 4
2. Click "稍後設定" on backup prompt
3. Verify app continues normally
4. Verify can still send/receive messages

### Expected Behaviors

**Key Recovery Dialog:**
- Cannot be dismissed by tapping outside
- Shows "✅ 伺服器上有您的金鑰備份" if backup exists
- Shows "❌ 伺服器上沒有金鑰備份" if no backup
- Password field has show/hide toggle
- Loading indicator during recovery

**Backup Prompt Dialog:**
- Appears after force key generation
- Password must be at least 8 characters
- Confirm password must match
- Can be skipped with "稍後設定"
- Shows success message after backup

**Unrecoverable Messages:**
- Display "🔐 訊息無法復原"
- Status shows as "failed"
- No retry attempts
- Cannot be decrypted even with correct key

### Bug Report Template

```
Title: [E2EE Key Recovery] Brief description

Environment:
- Device: iPhone 14 Pro / Android Pixel 7
- OS Version: iOS 17.2 / Android 14
- App Version: 1.0.0
- Backend Version: 1.0.0

Steps to Reproduce:
1. 
2. 
3. 

Expected Result:


Actual Result:


Screenshots/Logs:


Additional Notes:

```

## For Product Managers

### User-Facing Changes

**New Dialogs:**
1. "🔐 金鑰遺失" - Key recovery dialog
2. "🔐 設定金鑰備份" - Backup setup prompt
3. "⚠️ 確認生成新金鑰" - Force generation warning

**New Message States:**
- "🔐 訊息無法復原" - Permanently unrecoverable messages

**User Flow Changes:**
- Login may show key recovery dialog if key is missing
- First-time key generation prompts for backup setup
- Backup setup can be skipped but is recommended

### Feature Flags (Recommended)

```dart
// Enable/disable key recovery feature
const bool ENABLE_KEY_RECOVERY = true;

// Enable/disable backup prompts
const bool ENABLE_BACKUP_PROMPTS = true;

// Enable/disable automatic backup on key generation
const bool AUTO_BACKUP_ON_GENERATION = false;
```

### Metrics to Track

- Key recovery attempts (success/failure)
- Backup adoption rate
- Average recovery time
- Number of unrecoverable messages per user
- User drop-off during recovery flow

### Support FAQs

**Q: Why can't I read my old messages?**
A: Your encryption key was lost (device reinstall, etc.). If you didn't set up a backup, old messages cannot be recovered. New messages will work normally.

**Q: How do I set up key backup?**
A: After generating a new key, you'll be prompted to set a backup password. You can also set it up later in Settings > Security > Key Backup.

**Q: I forgot my backup password. What can I do?**
A: Unfortunately, without the backup password, we cannot recover your key. You'll need to generate a new key, which means old messages will be unrecoverable.

**Q: Is my backup password stored on the server?**
A: No. Your backup password is never sent to or stored on our servers. It's only used locally to encrypt/decrypt your private key.

**Q: Can I change my backup password?**
A: Yes, go to Settings > Security > Key Backup > Change Password. This will re-encrypt your key with the new password.

## Quick Commands

```bash
# Check if key exists
flutter run --dart-define=CHECK_KEY_STATUS=true

# Force key deletion (testing)
flutter run --dart-define=DELETE_KEY_ON_START=true

# Skip backup prompts (testing)
flutter run --dart-define=SKIP_BACKUP_PROMPTS=true

# Enable debug logging
flutter run --dart-define=DEBUG_E2EE=true
```

## Rollback Plan

If issues arise in production:

1. **Disable feature flag** (if implemented)
2. **Revert to previous version** that auto-generates keys
3. **Notify users** via in-app message
4. **Investigate logs** for root cause
5. **Fix and redeploy** with additional testing

## Support Contacts

- **Backend Issues:** backend-team@company.com
- **Mobile Issues:** mobile-team@company.com
- **Security Review:** security@company.com
- **Product Questions:** product@company.com
