import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app/core/crypto/crypto_service.dart';

/// Bug Condition Exploration Test for E2EE Key Recovery Silent Generation Fix
/// 
/// **CRITICAL**: This test is EXPECTED TO FAIL on unfixed code
/// - Failure confirms the bug exists (silent key generation instead of throwing exception)
/// - This test encodes the expected behavior after the fix
/// 
/// **Property 1: Bug Condition** - Silent Key Generation on Missing Private Key
/// **Validates: Requirements 2.1**
/// 
/// Bug Condition: When CryptoService.initialize(userId) is called and SecureStorage
/// does not contain a private key for that user, the system silently generates
/// a new keypair instead of throwing PrivateKeyNotFoundException.
/// 
/// Expected Behavior (after fix): System should throw PrivateKeyNotFoundException
/// instead of silently generating keys.

void main() {
  group('Bug Condition Exploration - Silent Key Generation', () {
    late CryptoService cryptoService;
    late FlutterSecureStorage secureStorage;

    setUp(() {
      // Initialize with a fresh instance
      FlutterSecureStorage.setMockInitialValues({});
      cryptoService = CryptoService();
      secureStorage = const FlutterSecureStorage();
    });

    tearDown(() async {
      // Clean up after each test
      await cryptoService.clearKeys();
    });

    /// **Property 1: Bug Condition** - Silent Key Generation on Missing Private Key
    /// **Validates: Requirements 2.1**
    /// 
    /// This test demonstrates the bug: when private key is missing,
    /// the system silently generates a new keypair instead of throwing an exception.
    /// 
    /// **EXPECTED OUTCOME ON UNFIXED CODE**: Test PASSES (proves bug exists)
    /// **EXPECTED OUTCOME ON FIXED CODE**: Test FAILS (system throws exception as expected)
    test('EXPLORATION: iOS simulator restart - missing key causes silent generation', () async {
      // Counterexample 1: iOS 模擬器重啟
      // Simulate iOS simulator restart: SecureStorage is empty
      final userId = 'user1_ios_restart';
      
      // Verify SecureStorage is empty (no private key exists)
      final storageKey = 'e2ee_private_key_$userId';
      final existingKey = await secureStorage.read(key: storageKey);
      expect(existingKey, isNull, reason: 'SecureStorage should be empty initially');

      // Call initialize - this should throw PrivateKeyNotFoundException (after fix)
      // But on unfixed code, it silently generates a new keypair
      String? publicKey;
      Exception? caughtException;
      
      try {
        publicKey = await cryptoService.initialize(userId: userId);
      } catch (e) {
        caughtException = e as Exception;
      }

      // EXPECTED BEHAVIOR (after fix):
      expect(caughtException, isNotNull,
        reason: 'FIXED CODE: Exception should be thrown when private key is missing');
      expect(caughtException, isA<PrivateKeyNotFoundException>(),
        reason: 'FIXED CODE: Should throw PrivateKeyNotFoundException');
      expect(publicKey, isNull,
        reason: 'FIXED CODE: No public key should be returned when exception is thrown');
    });

    /// **Property 1: Bug Condition** - Silent Key Generation on Missing Private Key
    /// **Validates: Requirements 2.1**
    test('EXPLORATION: Device change - missing key causes silent generation', () async {
      // Counterexample 2: 更換裝置
      // Simulate new device: SecureStorage is empty
      final userId = 'user2_device_change';
      
      // Verify SecureStorage is empty
      final storageKey = 'e2ee_private_key_$userId';
      final existingKey = await secureStorage.read(key: storageKey);
      expect(existingKey, isNull);

      // Call initialize
      String? publicKey;
      Exception? caughtException;
      
      try {
        publicKey = await cryptoService.initialize(userId: userId);
      } catch (e) {
        caughtException = e as Exception;
      }

      // EXPECTED BEHAVIOR (after fix):
      expect(caughtException, isNotNull,
        reason: 'FIXED CODE: Exception should be thrown on device change');
      expect(caughtException, isA<PrivateKeyNotFoundException>(),
        reason: 'FIXED CODE: Should throw PrivateKeyNotFoundException on device change');
      expect(publicKey, isNull,
        reason: 'FIXED CODE: No public key should be returned on device change');
    });

    /// **Property 1: Bug Condition** - Silent Key Generation on Missing Private Key
    /// **Validates: Requirements 2.1**
    test('EXPLORATION: App reinstall - missing key causes silent generation', () async {
      // Counterexample 3: 重新安裝應用
      // Simulate app reinstall: all local data cleared
      final userId = 'user3_app_reinstall';
      
      // Verify SecureStorage is empty
      final storageKey = 'e2ee_private_key_$userId';
      final existingKey = await secureStorage.read(key: storageKey);
      expect(existingKey, isNull);

      // Call initialize
      String? publicKey;
      Exception? caughtException;
      
      try {
        publicKey = await cryptoService.initialize(userId: userId);
      } catch (e) {
        caughtException = e as Exception;
      }

      // EXPECTED BEHAVIOR (after fix):
      expect(caughtException, isNotNull,
        reason: 'FIXED CODE: Exception should be thrown after app reinstall');
      expect(caughtException, isA<PrivateKeyNotFoundException>(),
        reason: 'FIXED CODE: Should throw PrivateKeyNotFoundException after app reinstall');
      expect(publicKey, isNull,
        reason: 'FIXED CODE: No public key should be returned after app reinstall');
    });

    /// Edge Case: Normal login with existing key should continue to work
    /// This behavior should NOT change after the fix
    test('EDGE CASE: Normal login with existing key loads successfully', () async {
      // This is the expected behavior that should be preserved
      final userId = 'user4_normal_login';
      
      // First initialization: generate and store key (using forceGenerate since no key exists)
      final firstPublicKey = await cryptoService.initialize(userId: userId, forceGenerate: true);
      expect(firstPublicKey, isNotNull);
      
      // Clear memory state to simulate app restart
      await cryptoService.clearKeys();
      
      // Second initialization: should load existing key (no forceGenerate needed)
      final secondPublicKey = await cryptoService.initialize(userId: userId);
      
      // Should load the same key (not generate a new one)
      expect(secondPublicKey, equals(firstPublicKey),
        reason: 'Should load existing key, not generate new one');
    });
  });
}
