import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:glados/glados.dart';

/// **Feature: linked-devices, Property 4: Session Key 加密解密往返**
///
/// *For any* 隨機產生的 Session Key 與 X25519 金鑰對，使用公鑰加密
/// Session Key 後，再使用對應的私鑰解密，應得到與原始 Session Key
/// 完全相同的值。
///
/// **Validates: Requirements 5.2, 5.4**

/// Standalone encrypt/decrypt functions that mirror CryptoService logic
/// but accept explicit key pairs, making them pure and testable without
/// Flutter widget dependencies.

final _x25519 = X25519();
final _aesGcm = AesGcm.with256bits();

/// Derive ECDH shared secret from a key pair and a remote public key.
Future<SecretKey> _deriveSharedSecret(
  SimpleKeyPair localKeyPair,
  SimplePublicKey remotePublicKey,
) async {
  return _x25519.sharedSecretKey(
    keyPair: localKeyPair,
    remotePublicKey: remotePublicKey,
  );
}

/// Encrypt a session key (base64) using the sender's key pair and the
/// receiver's public key. Returns base64(nonce + mac + ciphertext).
Future<String> encryptSessionKey(
  String sessionKeyBase64,
  SimpleKeyPair senderKeyPair,
  SimplePublicKey receiverPublicKey,
) async {
  final sharedSecret = await _deriveSharedSecret(senderKeyPair, receiverPublicKey);
  final sessionKeyBytes = base64Decode(sessionKeyBase64);

  final secretBox = await _aesGcm.encrypt(
    sessionKeyBytes,
    secretKey: sharedSecret,
  );

  final combined = [
    ...secretBox.nonce,
    ...secretBox.mac.bytes,
    ...secretBox.cipherText,
  ];
  return base64Encode(combined);
}

/// Decrypt an encrypted session key using the receiver's key pair and the
/// sender's public key. Returns the original session key as base64.
Future<String> decryptSessionKey(
  String encryptedBase64,
  SimpleKeyPair receiverKeyPair,
  SimplePublicKey senderPublicKey,
) async {
  final sharedSecret = await _deriveSharedSecret(receiverKeyPair, senderPublicKey);
  final decoded = base64Decode(encryptedBase64);

  final nonce = decoded.sublist(0, 12);
  final macBytes = decoded.sublist(12, 28);
  final cipherText = decoded.sublist(28);

  final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
  final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: sharedSecret);
  return base64Encode(plainBytes);
}

/// Generate a random base64-encoded AES-256 key (32 bytes).
String _randomSessionKey(Random rng) {
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return base64Encode(bytes);
}

void main() {
  group('Property 4: Session Key 加密解密往返', () {
    // Use Glados with a seed list to drive 100+ iterations.
    // Each seed produces a unique random session key + key pair.
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      'encrypt then decrypt yields original session key',
      (seed) async {
        final rng = Random(seed);

        // Generate a random session key (AES-256, 32 bytes)
        final originalSessionKey = _randomSessionKey(rng);

        // Generate two X25519 key pairs: sender (primary device) and receiver (linked device)
        final senderKeyPair = await _x25519.newKeyPair();
        final receiverKeyPair = await _x25519.newKeyPair();

        final senderPublicKey = await senderKeyPair.extractPublicKey();
        final receiverPublicKey = await receiverKeyPair.extractPublicKey();

        // Sender encrypts session key for receiver
        final encrypted = await encryptSessionKey(
          originalSessionKey,
          senderKeyPair,
          receiverPublicKey,
        );

        // Receiver decrypts session key using sender's public key
        final decrypted = await decryptSessionKey(
          encrypted,
          receiverKeyPair,
          senderPublicKey,
        );

        expect(decrypted, equals(originalSessionKey),
            reason: 'Decrypted session key should match original '
                '(seed=$seed)');
      },
    );
  });
}
