import 'dart:convert';
import 'dart:math';
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
  static const String _privateKeyHistoryStorageKey = 'e2ee_private_key_history'; // 新增

  bool get isInitialized => _keyPair != null;
  String? get publicKeyBase64 => _publicKeyBase64;

  /// 從 SecureStorage 讀取歷史私鑰列表（JSON 陣列格式）
  Future<List<String>> _loadHistoryPrivateKeys() async {
    final raw = await _secureStorage.read(key: _privateKeyHistoryStorageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<String>();
    } catch (_) {
      return [];
    }
  }

  /// 將一把私鑰（base64）加入歷史清單並儲存
  Future<void> _appendToHistoryPrivateKeys(String privateKeyBase64) async {
    final history = await _loadHistoryPrivateKeys();
    if (!history.contains(privateKeyBase64)) {
      history.add(privateKeyBase64);
      // 最多保留 20 把歷史金鑰，防止無限增長
      final trimmed = history.length > 20 ? history.sublist(history.length - 20) : history;
      await _secureStorage.write(
        key: _privateKeyHistoryStorageKey,
        value: jsonEncode(trimmed),
      );
    }
  }

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
    if (storedPrivateKeyBase64 != null) {
      await _appendToHistoryPrivateKeys(storedPrivateKeyBase64);
    }
    
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
    // Step 1: 先用當前金鑰解密（原有邏輯）
    try {
      final decodedBytes = base64Decode(encryptedOrPlainText);
      if (decodedBytes.length < 28) return encryptedOrPlainText;

      final nonce = decodedBytes.sublist(0, 12);
      final macBytes = decodedBytes.sublist(12, 28);
      final cipherText = decodedBytes.sublist(28);
      final sharedSecret = await _deriveSharedSecret(senderPublicKeyBase64);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final plainTextBytes = await _aesGcm.decrypt(secretBox, secretKey: sharedSecret);
      return utf8.decode(plainTextBytes);
    } catch (_) {
      // 當前金鑰解密失敗，繼續嘗試歷史金鑰
    }

    // Step 2: 嘗試所有歷史私鑰
    try {
      final decodedBytes = base64Decode(encryptedOrPlainText);
      if (decodedBytes.length >= 28) {
        final nonce = decodedBytes.sublist(0, 12);
        final macBytes = decodedBytes.sublist(12, 28);
        final cipherText = decodedBytes.sublist(28);

        final historyKeys = await _loadHistoryPrivateKeys();
        final targetPubKeyBytes = base64Decode(senderPublicKeyBase64);
        final targetPublicKey = SimplePublicKey(targetPubKeyBytes, type: KeyPairType.x25519);

        for (final histPrivKeyBase64 in historyKeys.reversed) {
          try {
            final histPrivKeyBytes = base64Decode(histPrivKeyBase64);
            final histKeyPair = await _x25519.newKeyPairFromSeed(histPrivKeyBytes);
            final sharedSecret = await _x25519.sharedSecretKey(
              keyPair: histKeyPair,
              remotePublicKey: targetPublicKey,
            );
            final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
            final plainTextBytes = await _aesGcm.decrypt(secretBox, secretKey: sharedSecret);
            print('✅ 歷史金鑰解密成功');
            return utf8.decode(plainTextBytes);
          } catch (_) {
            continue; // 這把歷史金鑰也不對，試下一把
          }
        }
      }
    } catch (_) {}

    // Step 3: 所有金鑰都失敗
    print('⚠️ 解密判定：此為舊版明文訊息或解密失敗，直接顯示原文。');
    return encryptedOrPlainText;
  }

  // --- 備份機制：私鑰雲端加密與還原 ---

  /// 使用 PBKDF2 從密碼與 salt 推導出 256-bit 的 SecretKey
  Future<SecretKey> deriveKeyFromPassword(String password, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return secretKey;
  }

  /// 使用者設定密碼，將原本的 Private Key 拿出、加密，準備上傳到伺服器
  Future<Map<String, String>> encryptPrivateKeyForBackup(String rawPrivateKeyBase64, String password) async {
    final salt = List<int>.generate(16, (i) => Random.secure().nextInt(256));
    final secretKey = await deriveKeyFromPassword(password, salt);

    // X25519 的 private key 是一串 bytes
    final privateKeyBytes = base64Decode(rawPrivateKeyBase64);

    final secretBox = await _aesGcm.encrypt(
      privateKeyBytes,
      secretKey: secretKey,
    );

    final combinedBytes = [
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ];

    return {
      'encryptedKeyBase64': base64Encode(combinedBytes),
      'saltBase64': base64Encode(salt),
    };
  }

  /// 使用者換手機登入後，輸入密碼解開從伺服器拿回的加密私鑰
  Future<String> decryptPrivateKeyFromBackup(String encryptedKeyBase64, String saltBase64, String password) async {
    final salt = base64Decode(saltBase64);
    final secretKey = await deriveKeyFromPassword(password, salt);

    final decodedBytes = base64Decode(encryptedKeyBase64);
    if (decodedBytes.length < 28) {
      throw Exception('Invalid encrypted key payload');
    }

    final nonce = decodedBytes.sublist(0, 12);
    final macBytes = decodedBytes.sublist(12, 28);
    final cipherText = decodedBytes.sublist(28);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    try {
      final plainTextBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      // 還原為 base64 的原始 private key
      return base64Encode(plainTextBytes);
    } catch (e) {
      throw Exception('Passphrase incorrect or data corrupted');
    }
  }

  /// 取得當前本機的私鑰 (供加密備份時使用)
  Future<String?> getRawPrivateKey() async {
    return await _secureStorage.read(key: _privateKeyStorageKey);
  }

  /// 如果從雲端還原了私鑰，手動覆寫本地儲存的私鑰
  Future<void> restorePrivateKey(String rawPrivateKeyBase64) async {
    await _secureStorage.write(
      key: _privateKeyStorageKey,
      value: rawPrivateKeyBase64,
    );
    // 重新載入 KeyPair
    final privateKeyBytes = base64Decode(rawPrivateKeyBase64);
    final keyPair = await _x25519.newKeyPairFromSeed(privateKeyBytes);
    _keyPair = keyPair;
    final pubKey = await keyPair.extractPublicKey();
    _publicKeyBase64 = base64Encode(pubKey.bytes);
  }

  // Clear keys for logout
  Future<void> clearKeys() async {
    _keyPair = null;
    _publicKeyBase64 = null;
    await _secureStorage.delete(key: _privateKeyStorageKey);
    await _secureStorage.delete(key: _privateKeyHistoryStorageKey); // 新增
  }
}

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoService();
});
