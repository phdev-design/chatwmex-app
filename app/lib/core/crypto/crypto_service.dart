import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CryptoService {
  late final encrypt.Key _key;
  late final encrypt.Encrypter _encrypter;

  CryptoService(String keyString) {
    if (keyString.length != 32) {
      throw ArgumentError('Key length must be 32 bytes');
    }
    _key = encrypt.Key.fromUtf8(keyString);
    _encrypter = encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.gcm));
  }

  String encryptData(String plainText) {
    // Generate a random IV (12 bytes for GCM)
    final iv = encrypt.IV.fromLength(12);
    
    // Encrypt
    final encrypted = _encrypter.encrypt(plainText, iv: iv);
    
    // Combine IV + Ciphertext (Tag is included in encrypted.bytes)
    final combined = Uint8List.fromList(iv.bytes + encrypted.bytes);
    
    // Return as Base64 string
    return base64.encode(combined);
  }

  String decryptData(String encryptedBase64) {
    try {
      final decodedBytes = base64.decode(encryptedBase64);
      
      if (decodedBytes.length < 12) {
        throw ArgumentError('Invalid ciphertext length');
      }
      
      // Extract IV (first 12 bytes)
      final iv = encrypt.IV(decodedBytes.sublist(0, 12));
      
      // Extract Ciphertext (remaining bytes)
      final ciphertextBytes = decodedBytes.sublist(12);
      final encrypted = encrypt.Encrypted(ciphertextBytes);
      
      return _encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      print('Decryption failed: $e');
      return ''; // Return empty string or throw depending on policy
    }
  }
}

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  // TODO: Get this key from a secure config or env
  return CryptoService('12345678901234567890123456789012');
});

