import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CryptoService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // X25519 algorithm for ECDH
  final X25519 _x25519 = X25519();
  // AES-GCM for symmetric encryption
  final AesGcm _aesGcm = AesGcm.with256bits();
  
  // Local keys
  SimpleKeyPair? _keyPair;
  String? _publicKeyBase64;

  static const String _privateKeyStorageKey = 'e2ee_private_key';

  bool get isInitialized => _keyPair != null;
  String? get publicKeyBase64 => _publicKeyBase64;

  /// Initialize the keypair. Loads from secure storage or generates a new one.
  Future<String> initialize() async {
    if (isInitialized) {
      return _publicKeyBase64!;
    }

    final storedPrivateKeyBase64 = await _secureStorage.read(key: _privateKeyStorageKey);
    
    if (storedPrivateKeyBase64 != null) {
      // Load existing keypair
      final privateKeyBytes = base64Decode(storedPrivateKeyBase64);
      final keyPair = await _x25519.newKeyPairFromSeed(privateKeyBytes);
      _keyPair = keyPair;
      final pubKey = await keyPair.extractPublicKey();
      _publicKeyBase64 = base64Encode(pubKey.bytes);
      return _publicKeyBase64!;
    }

    // Generate new keypair
    final newKeyPair = await _x25519.newKeyPair();
    final extractedPrivateKey = await newKeyPair.extractPrivateKeyBytes();
    
    // Store private key securely
    await _secureStorage.write(
      key: _privateKeyStorageKey,
      value: base64Encode(extractedPrivateKey),
    );
    
    _keyPair = newKeyPair;
    final pubKey = await newKeyPair.extractPublicKey();
    _publicKeyBase64 = base64Encode(pubKey.bytes);
    
    return _publicKeyBase64!;
  }

  /// Derives an AES key (Shared Secret) from our private key and their public key.
  Future<SecretKey> _deriveSharedSecret(String targetPublicKeyBase64) async {
    if (!isInitialized) {
      throw StateError('CryptoService not initialized');
    }

    final targetPubKeyBytes = base64Decode(targetPublicKeyBase64);
    final targetPublicKey = SimplePublicKey(targetPubKeyBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: targetPublicKey,
    );

    // Often good practice to hash the ECDH output to form the AES key.
    // However, for simplicity and typical AES-GCM 256bit, using the shared secret bytes directly
    // is often done. But cryptography library's `sharedSecretKey` returns a SecretKey.
    // We can extract and hash it, or just use it.
    // For AesGcm.with256bits(), the SecretKey should be 32 bytes.
    // X25519 shared secret is exactly 32 bytes, so it fits perfectly.
    
    return sharedSecret;
  }

  /// Encrypts plaintext using AES-GCM and the derived shared secret.
  Future<String> encryptMessage(String plainText, String receiverPublicKeyBase64) async {
    final sharedSecret = await _deriveSharedSecret(receiverPublicKeyBase64);
    
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plainText),
      secretKey: sharedSecret,
    );
    
    // secretBox contains cipherText, mac (tag), and nonce (iv)
    // We combine nonce + mac + cipherText
    final combinedBytes = [
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ];

    return base64Encode(combinedBytes);
  }

  /// Decrypts a base64 encoded payload using AES-GCM and the derived shared secret.
 Future<String> decryptMessage(String encryptedOrPlainText, String senderPublicKeyBase64) async {
    try {
      // 1. 嘗試進行 Base64 解碼
      final decodedBytes = base64Decode(encryptedOrPlainText);
      
      // 2. AES-GCM 格式檢查：nonce(12) + mac(16) = 最少 28 bytes
      // 如果連這個長度都達不到，代表這絕對不是我們加密的封包，直接當作舊明文回傳
      if (decodedBytes.length < 28) {
        return encryptedOrPlainText; 
      }

      // 3. 正常解密流程
      final nonce = decodedBytes.sublist(0, 12);
      final macBytes = decodedBytes.sublist(12, 28);
      final cipherText = decodedBytes.sublist(28);

      final sharedSecret = await _deriveSharedSecret(senderPublicKeyBase64);
      
      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final plainTextBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: sharedSecret,
      );

      return utf8.decode(plainTextBytes);
      
    } catch (e) {
      // 4. 關鍵備用機制 (Fallback)：
      // 如果 Base64 解碼失敗 (因為本來就是普通文字)，或解密過程發生任何錯誤，
      // 就把它當作「舊版未加密」的訊息，直接回傳原始文字。
      print('⚠️ 解密判定：此為舊版明文訊息或解密失敗，直接顯示原文。');
      return encryptedOrPlainText;
    }
  }

  // Clear keys for logout
  Future<void> clearKeys() async {
    _keyPair = null;
    _publicKeyBase64 = null;
    await _secureStorage.delete(key: _privateKeyStorageKey);
  }
}

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoService();
});
