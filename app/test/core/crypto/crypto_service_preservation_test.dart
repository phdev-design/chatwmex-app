import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app/core/crypto/crypto_service.dart';

/// 🛡️ Preservation Property Tests - E2EE Key Recovery Silent Generation Fix
/// 
/// **Property 2: Preservation** - Normal Initialization with Existing Key
/// **Validates: Requirements 3.1, 3.2**
/// 
/// These tests capture the baseline behavior when private keys EXIST in SecureStorage.
/// They MUST PASS on unfixed code to establish the baseline behavior that must be
/// preserved after the fix.
/// 
/// EXPECTED OUTCOME ON UNFIXED CODE: ALL TESTS PASS
/// EXPECTED OUTCOME AFTER FIX: ALL TESTS STILL PASS (no regressions)
/// 
/// Property: For any initialize request where the user's private key exists in
/// SecureStorage, the system SHALL continue to load the existing keypair and
/// complete initialization without throwing exceptions.

void main() {
  group('Preservation Property Tests - Normal Initialization with Existing Key', () {
    late CryptoService cryptoService;
    late FlutterSecureStorage secureStorage;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      cryptoService = CryptoService();
      secureStorage = const FlutterSecureStorage();
    });

    tearDown(() async {
      await cryptoService.clearKeys();
    });

    group('Property: Normal Initialization - Private Key Exists', () {
      // **Validates: Requirements 3.1, 3.2**
      // When private key exists in SecureStorage, system should:
      // 1. Load the existing keypair
      // 2. Complete initialization successfully
      // 3. NOT throw any exceptions
      // 4. Return the same public key on subsequent initializations

      test('**Preservation** - Single user normal initialization loads existing key', () async {
        final userId = 'user_normal_1';
        
        // First initialization: generate and store key (requires forceGenerate for new keys)
        final firstPublicKey = await cryptoService.initialize(userId: userId, forceGenerate: true);
        expect(firstPublicKey, isNotNull);
        expect(firstPublicKey, isNotEmpty);
        
        // Verify key was stored
        final storageKey = 'e2ee_private_key_$userId';
        final storedKey = await secureStorage.read(key: storageKey);
        expect(storedKey, isNotNull);
        
        // Clear memory state to simulate app restart
        await cryptoService.clearKeys();
        expect(cryptoService.isInitialized, isFalse);
        
        // Second initialization: should load existing key
        final secondPublicKey = await cryptoService.initialize(userId: userId);
        
        // Should load the same key (not generate a new one)
        expect(secondPublicKey, equals(firstPublicKey),
            reason: 'Should load existing key, not generate new one');
        expect(cryptoService.isInitialized, isTrue);
      });

      test('**Preservation** - Multiple users maintain key isolation', () async {
        // Test that different users have different keys and they don't interfere
        final user1 = 'user_isolation_1';
        final user2 = 'user_isolation_2';
        
        // Initialize user1 (requires forceGenerate for new keys)
        final user1PublicKey = await cryptoService.initialize(userId: user1, forceGenerate: true);
        expect(user1PublicKey, isNotNull);
        
        // Initialize user2 (switches user, requires forceGenerate for new keys)
        final user2PublicKey = await cryptoService.initialize(userId: user2, forceGenerate: true);
        expect(user2PublicKey, isNotNull);
        
        // Keys should be different
        expect(user1PublicKey, isNot(equals(user2PublicKey)),
            reason: 'Different users should have different keys');
        
        // Switch back to user1
        final user1PublicKeyAgain = await cryptoService.initialize(userId: user1);
        
        // Should load user1's original key
        expect(user1PublicKeyAgain, equals(user1PublicKey),
            reason: 'Switching back to user1 should load their original key');
      });

      test('**Preservation** - Repeated initialization with same user returns same key', () async {
        final userId = 'user_repeated_init';
        
        // First initialization (requires forceGenerate for new keys)
        final publicKey1 = await cryptoService.initialize(userId: userId, forceGenerate: true);
        
        // Repeated initializations without clearing memory
        final publicKey2 = await cryptoService.initialize(userId: userId);
        final publicKey3 = await cryptoService.initialize(userId: userId);
        
        // All should return the same key
        expect(publicKey2, equals(publicKey1));
        expect(publicKey3, equals(publicKey1));
      });

      test('**Preservation** - App restart scenario loads existing key', () async {
        final userId = 'user_app_restart';
        
        // Simulate first app launch: initialize and store key (requires forceGenerate for new keys)
        final originalPublicKey = await cryptoService.initialize(userId: userId, forceGenerate: true);
        expect(originalPublicKey, isNotNull);
        
        // Simulate app restart: clear memory but keep storage
        await cryptoService.clearKeys();
        
        // Create new service instance (simulates app restart)
        final newCryptoService = CryptoService();
        
        // Initialize again: should load existing key from storage
        final loadedPublicKey = await newCryptoService.initialize(userId: userId);
        
        // Should load the same key
        expect(loadedPublicKey, equals(originalPublicKey),
            reason: 'After app restart, should load existing key from storage');
        
        await newCryptoService.clearKeys();
      });

      test('**Preservation** - Multiple app restarts maintain key consistency', () async {
        final userId = 'user_multiple_restarts';
        
        // Initial setup (requires forceGenerate for new keys)
        final originalPublicKey = await cryptoService.initialize(userId: userId, forceGenerate: true);
        
        // Simulate multiple app restarts
        for (int i = 0; i < 5; i++) {
          await cryptoService.clearKeys();
          final newService = CryptoService();
          final loadedKey = await newService.initialize(userId: userId);
          
          expect(loadedKey, equals(originalPublicKey),
              reason: 'Restart $i: Should always load the same original key');
          
          await newService.clearKeys();
        }
      });
    });

    group('Property: Encryption/Decryption Flow Preservation', () {
      // **Validates: Requirements 3.2**
      // E2EE encryption/decryption flow should remain unchanged

      test('**Preservation** - Message encryption/decryption works with existing keys', () async {
        final user1 = 'user_encrypt_1';
        final user2 = 'user_encrypt_2';
        
        // Initialize both users (requires forceGenerate for new keys)
        final user1Service = CryptoService();
        final user2Service = CryptoService();
        
        final user1PublicKey = await user1Service.initialize(userId: user1, forceGenerate: true);
        final user2PublicKey = await user2Service.initialize(userId: user2, forceGenerate: true);
        
        // User1 encrypts message for User2
        final plainText = 'Hello, this is a test message!';
        final encrypted = await user1Service.encryptMessage(plainText, user2PublicKey);
        
        expect(encrypted, isNotNull);
        expect(encrypted, isNotEmpty);
        expect(encrypted, isNot(equals(plainText)),
            reason: 'Encrypted text should be different from plain text');
        
        // User2 decrypts message from User1
        final decrypted = await user2Service.decryptMessage(encrypted, user1PublicKey);
        
        expect(decrypted, equals(plainText),
            reason: 'Decrypted text should match original plain text');
        
        await user1Service.clearKeys();
        await user2Service.clearKeys();
      });

      test('**Preservation** - Encryption/decryption after app restart', () async {
        final user1 = 'user_restart_encrypt_1';
        final user2 = 'user_restart_encrypt_2';
        
        // Initialize and encrypt (requires forceGenerate for new keys)
        final user1Service = CryptoService();
        final user2Service = CryptoService();
        
        final user1PublicKey = await user1Service.initialize(userId: user1, forceGenerate: true);
        final user2PublicKey = await user2Service.initialize(userId: user2, forceGenerate: true);
        
        final plainText = 'Message before restart';
        final encrypted = await user1Service.encryptMessage(plainText, user2PublicKey);
        
        // Simulate app restart
        await user1Service.clearKeys();
        await user2Service.clearKeys();
        
        // Reinitialize (load existing keys)
        final newUser1Service = CryptoService();
        final newUser2Service = CryptoService();
        
        final reloadedUser1PublicKey = await newUser1Service.initialize(userId: user1);
        await newUser2Service.initialize(userId: user2);
        
        // Should be able to decrypt message encrypted before restart
        final decrypted = await newUser2Service.decryptMessage(encrypted, reloadedUser1PublicKey);
        
        expect(decrypted, equals(plainText),
            reason: 'Should decrypt message encrypted before app restart');
        
        await newUser1Service.clearKeys();
        await newUser2Service.clearKeys();
      });

      test('**Preservation** - Symmetric encryption/decryption for group chat', () async {
        final userId = 'user_group_chat';
        
        // Initialize user (requires forceGenerate for new keys)
        final userService = CryptoService();
        await userService.initialize(userId: userId, forceGenerate: true);
        
        // Get private key for symmetric encryption
        final privateKey = await userService.getRawPrivateKey();
        expect(privateKey, isNotNull);
        
        // Encrypt with symmetric key (simulating group chat encryption)
        final plainText = 'Group chat message';
        final privateKeyBytes = base64Decode(privateKey!);
        
        // This simulates the encryption that would happen in group chat
        // The actual encryption logic is internal, but we verify the key is available
        expect(privateKeyBytes, isNotEmpty);
        expect(privateKeyBytes.length, equals(32),
            reason: 'X25519 private key should be 32 bytes');
        
        await userService.clearKeys();
      });
    });

    group('Property: Backup Methods Preservation', () {
      // **Validates: Requirements 3.2**
      // encryptPrivateKeyForBackup and decryptPrivateKeyFromBackup should remain unchanged

      test('**Preservation** - Backup encryption/decryption round-trip', () async {
        final userId = 'user_backup_test';
        
        // Initialize and get private key (requires forceGenerate for new keys)
        await cryptoService.initialize(userId: userId, forceGenerate: true);
        final privateKey = await cryptoService.getRawPrivateKey();
        expect(privateKey, isNotNull);
        
        // Encrypt private key for backup
        final password = 'test_backup_password_123';
        final backupData = await cryptoService.encryptPrivateKeyForBackup(
          privateKey!,
          password,
        );
        
        expect(backupData, isNotNull);
        expect(backupData.containsKey('encryptedKeyBase64'), isTrue);
        expect(backupData.containsKey('saltBase64'), isTrue);
        expect(backupData['encryptedKeyBase64'], isNotEmpty);
        expect(backupData['saltBase64'], isNotEmpty);
        
        // Decrypt private key from backup
        final decryptedKey = await cryptoService.decryptPrivateKeyFromBackup(
          backupData['encryptedKeyBase64']!,
          backupData['saltBase64']!,
          password,
        );
        
        expect(decryptedKey, equals(privateKey),
            reason: 'Decrypted key should match original private key');
      });

      test('**Preservation** - Backup with wrong password throws exception', () async {
        final userId = 'user_backup_wrong_password';
        
        // Initialize and get private key (requires forceGenerate for new keys)
        await cryptoService.initialize(userId: userId, forceGenerate: true);
        final privateKey = await cryptoService.getRawPrivateKey();
        
        // Encrypt with correct password
        final correctPassword = 'correct_password';
        final backupData = await cryptoService.encryptPrivateKeyForBackup(
          privateKey!,
          correctPassword,
        );
        
        // Try to decrypt with wrong password
        final wrongPassword = 'wrong_password';
        
        expect(
          () => cryptoService.decryptPrivateKeyFromBackup(
            backupData['encryptedKeyBase64']!,
            backupData['saltBase64']!,
            wrongPassword,
          ),
          throwsException,
          reason: 'Wrong password should throw exception',
        );
      });

      test('**Preservation** - Restore private key from backup', () async {
        final userId = 'user_restore_test';
        
        // Initialize and get original key (requires forceGenerate for new keys)
        final originalPublicKey = await cryptoService.initialize(userId: userId, forceGenerate: true);
        final originalPrivateKey = await cryptoService.getRawPrivateKey();
        
        // Create backup
        final password = 'restore_password';
        final backupData = await cryptoService.encryptPrivateKeyForBackup(
          originalPrivateKey!,
          password,
        );
        
        // Simulate key loss: clear everything
        await cryptoService.clearKeys();
        await secureStorage.delete(key: 'e2ee_private_key_$userId');
        
        // Restore from backup
        final decryptedKey = await cryptoService.decryptPrivateKeyFromBackup(
          backupData['encryptedKeyBase64']!,
          backupData['saltBase64']!,
          password,
        );
        
        // Manually restore the key
        await secureStorage.write(
          key: 'e2ee_private_key_$userId',
          value: decryptedKey,
        );
        
        // Initialize again: should load restored key
        final restoredPublicKey = await cryptoService.initialize(userId: userId);
        
        expect(restoredPublicKey, equals(originalPublicKey),
            reason: 'Restored key should produce same public key as original');
      });

      test('**Preservation** - Multiple backup/restore cycles maintain key integrity', () async {
        final userId = 'user_multiple_backup';
        
        // Initialize (requires forceGenerate for new keys)
        final originalPublicKey = await cryptoService.initialize(userId: userId, forceGenerate: true);
        final originalPrivateKey = await cryptoService.getRawPrivateKey();
        
        // Perform multiple backup/restore cycles
        String currentPrivateKey = originalPrivateKey!;
        
        for (int i = 0; i < 3; i++) {
          final password = 'password_cycle_$i';
          
          // Backup
          final backupData = await cryptoService.encryptPrivateKeyForBackup(
            currentPrivateKey,
            password,
          );
          
          // Restore
          final restoredKey = await cryptoService.decryptPrivateKeyFromBackup(
            backupData['encryptedKeyBase64']!,
            backupData['saltBase64']!,
            password,
          );
          
          expect(restoredKey, equals(currentPrivateKey),
              reason: 'Cycle $i: Restored key should match current key');
          
          currentPrivateKey = restoredKey;
        }
        
        // Final key should still match original
        expect(currentPrivateKey, equals(originalPrivateKey),
            reason: 'After multiple cycles, key should remain unchanged');
      });
    });

    group('Property: Multi-User Isolation Preservation', () {
      // **Validates: Requirements 3.2**
      // Switching users should maintain key isolation

      test('**Preservation** - User switching maintains separate keys', () async {
        final user1 = 'user_switch_1';
        final user2 = 'user_switch_2';
        final user3 = 'user_switch_3';
        
        // Initialize all users (requires forceGenerate for new keys)
        final user1PublicKey = await cryptoService.initialize(userId: user1, forceGenerate: true);
        final user2PublicKey = await cryptoService.initialize(userId: user2, forceGenerate: true);
        final user3PublicKey = await cryptoService.initialize(userId: user3, forceGenerate: true);
        
        // All keys should be different
        expect(user1PublicKey, isNot(equals(user2PublicKey)));
        expect(user2PublicKey, isNot(equals(user3PublicKey)));
        expect(user1PublicKey, isNot(equals(user3PublicKey)));
        
        // Switch back to user1
        final user1KeyAgain = await cryptoService.initialize(userId: user1);
        expect(user1KeyAgain, equals(user1PublicKey));
        
        // Switch to user2
        final user2KeyAgain = await cryptoService.initialize(userId: user2);
        expect(user2KeyAgain, equals(user2PublicKey));
        
        // Switch to user3
        final user3KeyAgain = await cryptoService.initialize(userId: user3);
        expect(user3KeyAgain, equals(user3PublicKey));
      });

      test('**Preservation** - User switching does not corrupt keys', () async {
        final users = ['user_a', 'user_b', 'user_c', 'user_d'];
        final publicKeys = <String, String>{};
        
        // Initialize all users and store their public keys (requires forceGenerate for new keys)
        for (final user in users) {
          final publicKey = await cryptoService.initialize(userId: user, forceGenerate: true);
          publicKeys[user] = publicKey;
        }
        
        // Rapidly switch between users multiple times
        for (int i = 0; i < 20; i++) {
          final user = users[i % users.length];
          final publicKey = await cryptoService.initialize(userId: user);
          
          expect(publicKey, equals(publicKeys[user]),
              reason: 'Iteration $i: User $user should have consistent key');
        }
      });

      test('**Preservation** - User logout does not affect other users keys', () async {
        final user1 = 'user_logout_1';
        final user2 = 'user_logout_2';
        
        // Initialize both users (requires forceGenerate for new keys)
        final user1PublicKey = await cryptoService.initialize(userId: user1, forceGenerate: true);
        final user2PublicKey = await cryptoService.initialize(userId: user2, forceGenerate: true);
        
        // Logout (clear memory)
        await cryptoService.clearKeys();
        
        // User1 logs back in
        final user1KeyAfterLogout = await cryptoService.initialize(userId: user1);
        expect(user1KeyAfterLogout, equals(user1PublicKey),
            reason: 'User1 key should be preserved after logout');
        
        // User2 logs in
        final user2KeyAfterLogout = await cryptoService.initialize(userId: user2);
        expect(user2KeyAfterLogout, equals(user2PublicKey),
            reason: 'User2 key should be preserved after logout');
      });
    });

    group('Property-Based Behavior Verification', () {
      // This test verifies the overall preservation property across multiple scenarios
      
      test('**Preservation** - All normal initialization scenarios complete successfully', () async {
        // Property: For all scenarios where private key exists,
        // initialization should complete without throwing exceptions
        
        final testScenarios = [
          'scenario_1_normal',
          'scenario_2_restart',
          'scenario_3_switch',
          'scenario_4_multiple',
          'scenario_5_isolation',
        ];
        
        for (final userId in testScenarios) {
          // First init: create key (requires forceGenerate for new keys)
          await expectLater(
            cryptoService.initialize(userId: userId, forceGenerate: true),
            completes,
            reason: 'First initialization for $userId should complete',
          );
          
          // Clear memory
          await cryptoService.clearKeys();
          
          // Second init: load existing key
          await expectLater(
            cryptoService.initialize(userId: userId),
            completes,
            reason: 'Second initialization for $userId should complete',
          );
        }
      });

      test('**Preservation** - Existing key initialization never throws exceptions', () async {
        final userId = 'user_no_exceptions';
        
        // Create key (requires forceGenerate for new keys)
        final publicKey = await cryptoService.initialize(userId: userId, forceGenerate: true);
        expect(publicKey, isNotNull);
        
        // Multiple initializations should never throw
        for (int i = 0; i < 10; i++) {
          await cryptoService.clearKeys();
          
          String? loadedKey;
          Exception? exception;
          
          try {
            loadedKey = await cryptoService.initialize(userId: userId);
          } catch (e) {
            exception = e as Exception;
          }
          
          expect(exception, isNull,
              reason: 'Iteration $i: Should not throw exception when key exists');
          expect(loadedKey, equals(publicKey),
              reason: 'Iteration $i: Should load same key');
        }
      });

      test('**Preservation** - Key consistency across all operations', () async {
        // This test verifies that keys remain consistent across:
        // 1. Initialization
        // 2. Encryption/Decryption
        // 3. Backup/Restore
        // 4. User switching
        
        final userId = 'user_consistency_test';
        
        // Initialize (requires forceGenerate for new keys)
        final publicKey1 = await cryptoService.initialize(userId: userId, forceGenerate: true);
        
        // Encrypt/Decrypt
        final otherUser = CryptoService();
        final otherPublicKey = await otherUser.initialize(userId: 'other_user', forceGenerate: true);
        final encrypted = await cryptoService.encryptMessage('test', otherPublicKey);
        expect(encrypted, isNotNull);
        
        // Get public key again
        final publicKey2 = await cryptoService.initialize(userId: userId);
        expect(publicKey2, equals(publicKey1));
        
        // Backup
        final privateKey = await cryptoService.getRawPrivateKey();
        final backup = await cryptoService.encryptPrivateKeyForBackup(privateKey!, 'pass');
        expect(backup, isNotNull);
        
        // Get public key again
        final publicKey3 = await cryptoService.initialize(userId: userId);
        expect(publicKey3, equals(publicKey1));
        
        // Switch user and back
        await cryptoService.initialize(userId: 'temp_user', forceGenerate: true);
        final publicKey4 = await cryptoService.initialize(userId: userId);
        expect(publicKey4, equals(publicKey1));
        
        // All operations should maintain key consistency
        expect(publicKey1, equals(publicKey2));
        expect(publicKey2, equals(publicKey3));
        expect(publicKey3, equals(publicKey4));
        
        await otherUser.clearKeys();
      });
    });
  });
}
