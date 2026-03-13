import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/auth/models/auth_state.dart';
import 'package:app/core/crypto/crypto_service.dart';

/// Test for Task 3.2: AuthViewModel Changes
/// Validates that AuthState has the new fields for key recovery
void main() {
  group('AuthState - Key Recovery Fields', () {
    test('AuthState has needsKeyRecovery and missingKeyUserId fields', () {
      // Test default values
      final defaultState = AuthState();
      expect(defaultState.needsKeyRecovery, isFalse,
          reason: 'needsKeyRecovery should default to false');
      expect(defaultState.missingKeyUserId, isNull,
          reason: 'missingKeyUserId should default to null');

      // Test with values
      final stateWithRecovery = AuthState(
        needsKeyRecovery: true,
        missingKeyUserId: 'test_user_123',
      );
      expect(stateWithRecovery.needsKeyRecovery, isTrue);
      expect(stateWithRecovery.missingKeyUserId, equals('test_user_123'));
    });

    test('AuthState.copyWith() correctly updates key recovery fields', () {
      final initialState = AuthState();
      
      // Copy with key recovery fields
      final updatedState = initialState.copyWith(
        needsKeyRecovery: true,
        missingKeyUserId: 'user_456',
      );
      
      expect(updatedState.needsKeyRecovery, isTrue);
      expect(updatedState.missingKeyUserId, equals('user_456'));
      
      // Copy to reset fields
      final resetState = updatedState.copyWith(
        needsKeyRecovery: false,
        missingKeyUserId: null,
      );
      
      expect(resetState.needsKeyRecovery, isFalse);
      expect(resetState.missingKeyUserId, isNull);
    });

    test('PrivateKeyNotFoundException exists and has userId field', () {
      const testUserId = 'test_user_789';
      final exception = PrivateKeyNotFoundException(userId: testUserId);
      
      expect(exception.userId, equals(testUserId));
      expect(exception.toString(), contains(testUserId));
      expect(exception.toString(), contains('PrivateKeyNotFoundException'));
    });
  });
}
