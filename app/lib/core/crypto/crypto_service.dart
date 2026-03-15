import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 🔐 E2EE Key Recovery: 私鑰遺失異常
/// 當初始化時偵測不到本地私鑰且未設定 forceGenerate 時拋出此異常
class PrivateKeyNotFoundException implements Exception {
  final String userId;

  PrivateKeyNotFoundException({required this.userId});

  @override
  String toString() => 'PrivateKeyNotFoundException: Private key not found for user $userId';
}

/// 🔐 E2EE Auto-Resend: 解密失敗異常
/// 當解密失敗時拋出此異常，攜帶訊息 ID 與發送方 ID 以便發起重新加密請求
class DecryptionFailureException implements Exception {
  final String messageId;
  final String senderId;
  final String originalCiphertext;
  final String reason;

  DecryptionFailureException({
    required this.messageId,
    required this.senderId,
    required this.originalCiphertext,
    this.reason = 'MAC verification failed or key mismatch',
  });

  @override
  String toString() => 'DecryptionFailureException: $reason (messageId: $messageId, senderId: $senderId)';
}

class CryptoService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // X25519 algorithm for ECDH
  final X25519 _x25519 = X25519();
  // AES-GCM for symmetric encryption
  final AesGcm _aesGcm = AesGcm.with256bits();

  // Local keys
  SimpleKeyPair? _keyPair;
  String? _publicKeyBase64;

  String? _currentUserId;
  String _privateKeyStorageKey(String userId) => 'e2ee_private_key_$userId';
  static const String _privateKeyHistoryStorageKey = 'e2ee_private_key_history';
  static const String _keyOverflowWarningKey = 'e2ee_key_overflow_warning';
  static const int _maxHistoryKeys = 50;

  bool get isInitialized => _keyPair != null;
  String? get publicKeyBase64 => _publicKeyBase64;

  /// 從 SecureStorage 讀取歷史私鑰列表（JSON 陣列格式）
  Future<List<String>> _loadHistoryPrivateKeys() async {
    final raw = await _secureStorage.read(key: _privateKeyHistoryStorageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<String>();
    } catch (e) {
      return [];
    }
  }

  /// 將一把私鑰（base64）加入歷史清單並儲存
  Future<void> _appendToHistoryPrivateKeys(String privateKeyBase64) async {
    final history = await _loadHistoryPrivateKeys();
    if (!history.contains(privateKeyBase64)) {
      history.add(privateKeyBase64);
      // 最多保留 50 把歷史金鑰，防止無限增長
      if (history.length > _maxHistoryKeys) {
        // 即將丟棄最舊金鑰，寫入警告標記
        await _secureStorage.write(
          key: _keyOverflowWarningKey,
          value: DateTime.now().toIso8601String(),
        );
        final trimmed = history.sublist(history.length - _maxHistoryKeys);
        await _secureStorage.write(
          key: _privateKeyHistoryStorageKey,
          value: jsonEncode(trimmed),
        );
      } else {
        await _secureStorage.write(
          key: _privateKeyHistoryStorageKey,
          value: jsonEncode(history),
        );
      }
    }
  }

  /// Initialize the keypair. Requires userId to isolate keys per account.
  /// 
  /// 🔐 E2EE Key Recovery: 新增 forceGenerate 參數
  /// - 當 forceGenerate = false（預設）且本地私鑰不存在時，拋出 PrivateKeyNotFoundException
  /// - 當 forceGenerate = true 且本地私鑰不存在時，生成新的金鑰對
  Future<String> initialize({required String userId, bool forceGenerate = false}) async {
    // 已初始化且是同一個 user，直接返回
    if (isInitialized && _currentUserId == userId) {
      return _publicKeyBase64!;
    }

    // 切換帳號：重置記憶體狀態
    _keyPair = null;
    _publicKeyBase64 = null;
    _currentUserId = userId;

    final storageKey = _privateKeyStorageKey(userId);
    final storedPrivateKeyBase64 = await _secureStorage.read(key: storageKey);

    // 🆕 Migration: 確保舊版未隔離的金鑰被加入到歷史紀錄中，讓舊訊息仍可解密
    final legacyKey = await _secureStorage.read(key: 'e2ee_private_key');
    if (legacyKey != null) {
      await _appendToHistoryPrivateKeys(legacyKey);
    }

    if (storedPrivateKeyBase64 != null) {
      // 載入現有 keypair
      final privateKeyBytes = base64Decode(storedPrivateKeyBase64);
      final keyPair = await _x25519.newKeyPairFromSeed(privateKeyBytes);
      _keyPair = keyPair;
      final pubKey = await keyPair.extractPublicKey();
      _publicKeyBase64 = base64Encode(pubKey.bytes);
      // ✅ Fix: 確保現有 key 也進入 history（原本漏掉了）
      await _appendToHistoryPrivateKeys(storedPrivateKeyBase64);
      return _publicKeyBase64!;
    }

    // 🔐 E2EE Key Recovery: 私鑰不存在時的處理邏輯
    // 若 forceGenerate = false，拋出異常讓上層決定如何處理（還原或強制生成）
    if (!forceGenerate) {
      throw PrivateKeyNotFoundException(userId: userId);
    }

    // 生成新 keypair（僅在 forceGenerate = true 時執行）
    final newKeyPair = await _x25519.newKeyPair();
    final extractedPrivateKey = await newKeyPair.extractPrivateKeyBytes();
    final privateKeyBase64 = base64Encode(extractedPrivateKey);

    await _secureStorage.write(key: storageKey, value: privateKeyBase64);
    await _appendToHistoryPrivateKeys(privateKeyBase64); // ✅ 新 key 也存入 history

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
    final targetPublicKey = SimplePublicKey(
      targetPubKeyBytes,
      type: KeyPairType.x25519,
    );

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
  Future<String> encryptMessage(
    String plainText,
    String receiverPublicKeyBase64,
  ) async {
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

  /// 🔐 E2EE Auto-Resend: 解密訊息（一對一聊天）
  /// 
  /// 解密流程：
  /// 1. 先用當前金鑰解密
  /// 2. 失敗則嘗試所有歷史金鑰
  /// 3. 全部失敗則拋出 DecryptionFailureException（需攜帶 messageId 與 senderId）
  /// 
  /// 注意：此方法需要從外部傳入 messageId 與 senderId 以便拋出異常
  Future<String> decryptMessage(
    String encryptedOrPlainText,
    String senderPublicKeyBase64, {
    String? messageId,
    String? senderId,
  }) async {
    // Step 1: 先用當前金鑰解密（原有邏輯）
    try {
      final decodedBytes = base64Decode(encryptedOrPlainText);
      if (decodedBytes.length < 28) return encryptedOrPlainText;

      final nonce = decodedBytes.sublist(0, 12);
      final macBytes = decodedBytes.sublist(12, 28);
      final cipherText = decodedBytes.sublist(28);
      
      if (messageId != null) {
        final currentPubKey = _publicKeyBase64 ?? 'null';
        final keyFingerprint = currentPubKey != 'null' ? currentPubKey.substring(0, 8) : 'null';
        debugPrint('[CryptoService] 🔑 Attempting decryption with CURRENT key (fingerprint: $keyFingerprint...) for message: $messageId');
      }
      
      final sharedSecret = await _deriveSharedSecret(senderPublicKeyBase64);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final plainTextBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: sharedSecret,
      );
      
      if (messageId != null) {
        debugPrint('[CryptoService] ✅ Decryption succeeded with CURRENT key for message: $messageId');
      }
      
      return utf8.decode(plainTextBytes);
    } catch (e) {
      // 當前金鑰解密失敗，繼續嘗試歷史金鑰
      if (messageId != null) {
        debugPrint('[CryptoService] ❌ Current key failed: $e');
        debugPrint('[CryptoService] 🔄 Trying history keys...');
      }
    }

    // Step 2: 嘗試所有歷史私鑰
    try {
      final decodedBytes = base64Decode(encryptedOrPlainText);
      if (decodedBytes.length >= 28) {
        final nonce = decodedBytes.sublist(0, 12);
        final macBytes = decodedBytes.sublist(12, 28);
        final cipherText = decodedBytes.sublist(28);

        final historyKeys = await _loadHistoryPrivateKeys();
        
        if (messageId != null) {
          debugPrint('[CryptoService] 📚 Found ${historyKeys.length} history keys to try');
        }
        
        final targetPubKeyBytes = base64Decode(senderPublicKeyBase64);
        final targetPublicKey = SimplePublicKey(
          targetPubKeyBytes,
          type: KeyPairType.x25519,
        );

        int keyIndex = 0;
        for (final histPrivKeyBase64 in historyKeys.reversed) {
          try {
            if (messageId != null) {
              final keyFingerprint = histPrivKeyBase64.substring(0, 8);
              debugPrint('[CryptoService] 🔑 Trying history key #${keyIndex + 1}/${historyKeys.length} (fingerprint: $keyFingerprint...)');
            }
            
            final histPrivKeyBytes = base64Decode(histPrivKeyBase64);
            final histKeyPair = await _x25519.newKeyPairFromSeed(
              histPrivKeyBytes,
            );
            final sharedSecret = await _x25519.sharedSecretKey(
              keyPair: histKeyPair,
              remotePublicKey: targetPublicKey,
            );
            final secretBox = SecretBox(
              cipherText,
              nonce: nonce,
              mac: Mac(macBytes),
            );
            final plainTextBytes = await _aesGcm.decrypt(
              secretBox,
              secretKey: sharedSecret,
            );
            
            if (messageId != null) {
              debugPrint('[CryptoService] ✅ Decryption succeeded with history key #${keyIndex + 1} for message: $messageId');
            }
            
            return utf8.decode(plainTextBytes);
          } catch (_) {
            keyIndex++;
            continue;
          }
        }
      }
    } catch (e) {
      if (messageId != null) {
        debugPrint('[CryptoService] ❌ History key decryption error: $e');
      }
    }

    // Step 3: 所有金鑰都失敗 - 拋出異常以觸發自動重新加密機制
    // 如果有提供 messageId 與 senderId，則拋出 DecryptionFailureException
    if (messageId != null && senderId != null) {
      debugPrint('[CryptoService] ❌ ALL KEYS FAILED for message: $messageId');
      debugPrint('[CryptoService]   Current key: tried');
      debugPrint('[CryptoService]   History keys: tried all available');
      debugPrint('[CryptoService]   Throwing DecryptionFailureException...');
      throw DecryptionFailureException(
        messageId: messageId,
        senderId: senderId,
        originalCiphertext: encryptedOrPlainText,
        reason: 'All decryption attempts failed (current + history keys)',
      );
    }

    // 向後兼容：如果沒有提供 messageId/senderId，則返回原文（舊行為）
    return encryptedOrPlainText;
  }

  // --- 備份機制：私鑰雲端加密與還原 ---

  /// 使用 PBKDF2 從密碼與 salt 推導出 256-bit 的 SecretKey
  Future<SecretKey> deriveKeyFromPassword(
    String password,
    List<int> salt,
  ) async {
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
  Future<Map<String, String>> encryptPrivateKeyForBackup(
    String rawPrivateKeyBase64,
    String password,
  ) async {
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
  Future<String> decryptPrivateKeyFromBackup(
    String encryptedKeyBase64,
    String saltBase64,
    String password,
  ) async {
    final salt = base64Decode(saltBase64);
    final secretKey = await deriveKeyFromPassword(password, salt);

    final decodedBytes = base64Decode(encryptedKeyBase64);
    if (decodedBytes.length < 28) {
      throw Exception('Invalid encrypted key payload');
    }

    final nonce = decodedBytes.sublist(0, 12);
    final macBytes = decodedBytes.sublist(12, 28);
    final cipherText = decodedBytes.sublist(28);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

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
    if (_currentUserId == null) return null;
    return await _secureStorage.read(
      key: _privateKeyStorageKey(_currentUserId!),
    );
  }

  /// 如果從雲端還原了私鑰，手動覆寫本地儲存的私鑰
  Future<void> restorePrivateKey(String rawPrivateKeyBase64) async {
    if (_currentUserId == null) return;
    await _secureStorage.write(
      key: _privateKeyStorageKey(_currentUserId!),
      value: rawPrivateKeyBase64,
    );
    // 重新載入 KeyPair
    final privateKeyBytes = base64Decode(rawPrivateKeyBase64);
    final keyPair = await _x25519.newKeyPairFromSeed(privateKeyBytes);
    _keyPair = keyPair;
    final pubKey = await keyPair.extractPublicKey();
    _publicKeyBase64 = base64Encode(pubKey.bytes);
  }

  /// 🔐 E2EE Auto-Resend: 使用對稱金鑰解密（用於群組聊天）
  /// 直接使用當前用戶的私鑰作為對稱金鑰
  /// 
  /// 解密流程：
  /// 1. 先用當前私鑰解密
  /// 2. 失敗則嘗試所有歷史私鑰
  /// 3. 全部失敗則拋出 DecryptionFailureException（需攜帶 messageId 與 senderId）
  /// 
  /// 注意：此方法需要從外部傳入 messageId 與 senderId 以便拋出異常
  Future<String> decryptWithSymmetricKey(
    String encryptedOrPlainText, {
    String? messageId,
    String? senderId,
  }) async {
    if (!isInitialized) {
      throw StateError('CryptoService not initialized');
    }

    // Step 1: 先用當前私鑰解密
    try {
      final decodedBytes = base64Decode(encryptedOrPlainText);
      if (decodedBytes.length < 28) return encryptedOrPlainText;

      final nonce = decodedBytes.sublist(0, 12);
      final macBytes = decodedBytes.sublist(12, 28);
      final cipherText = decodedBytes.sublist(28);

      // 使用當前私鑰作為對稱金鑰
      final privateKeyBytes = await _keyPair!.extractPrivateKeyBytes();
      final symmetricKey = SecretKey(privateKeyBytes);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final plainTextBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: symmetricKey,
      );
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

        for (final histPrivKeyBase64 in historyKeys.reversed) {
          try {
            final histPrivKeyBytes = base64Decode(histPrivKeyBase64);
            final symmetricKey = SecretKey(histPrivKeyBytes);

            final secretBox = SecretBox(
              cipherText,
              nonce: nonce,
              mac: Mac(macBytes),
            );
            final plainTextBytes = await _aesGcm.decrypt(
              secretBox,
              secretKey: symmetricKey,
            );
            return utf8.decode(plainTextBytes);
          } catch (_) {
            continue;
          }
        }
      }
    } catch (_) {}

    // Step 3: 所有金鑰都失敗 - 拋出異常以觸發自動重新加密機制
    // 如果有提供 messageId 與 senderId，則拋出 DecryptionFailureException
    if (messageId != null && senderId != null) {
      throw DecryptionFailureException(
        messageId: messageId,
        senderId: senderId,
        originalCiphertext: encryptedOrPlainText,
        reason: 'All symmetric decryption attempts failed (current + history keys)',
      );
    }

    // 向後兼容：如果沒有提供 messageId/senderId，則返回原文（舊行為）
    return encryptedOrPlainText;
  }

  /// 🔐 E2EE Group Media: 從 fileKeysFanout 中提取並解密當前用戶的 fileKey
  /// 
  /// 參數：
  /// - fileKeysFanout: 包含所有成員加密 fileKey 的 map，格式：{"is_fanout": true, "keys": {userId: encryptedKey, ...}}
  /// - currentUserId: 當前用戶 ID
  /// - senderPublicKey: 發送方公鑰（用於 ECDH 解密）
  /// 
  /// 回傳：
  /// - 成功：解密後的明文 fileKey (base64)
  /// - 失敗：null（找不到對應 userId 或解密失敗）
  Future<String?> extractFileKeyFromFanout(
    Map<String, dynamic> fileKeysFanout,
    String currentUserId,
    String senderPublicKey,
  ) async {
    try {
      // 檢查格式是否正確
      if (fileKeysFanout['is_fanout'] != true) {
        debugPrint('[CryptoService] ⚠️ fileKeysFanout is_fanout flag is not true');
        return null;
      }

      final keys = fileKeysFanout['keys'];
      if (keys is! Map) {
        debugPrint('[CryptoService] ⚠️ fileKeysFanout keys is not a Map');
        return null;
      }

      // 取得當前用戶的加密 fileKey
      final encryptedKey = keys[currentUserId];
      if (encryptedKey == null) {
        debugPrint('[CryptoService] ⚠️ No encrypted fileKey found for user: $currentUserId');
        return null;
      }

      // 使用 ECDH 解密 fileKey
      final decryptedFileKey = await decryptMessage(
        encryptedKey.toString(),
        senderPublicKey,
      );

      debugPrint('[CryptoService] ✅ Successfully extracted fileKey from fanout for user: $currentUserId');
      return decryptedFileKey;
    } catch (e) {
      debugPrint('[CryptoService] ❌ Failed to extract fileKey from fanout: $e');
      return null;
    }
  }

  // Clear keys for logout — 只清記憶體，保留 SecureStorage 讓舊訊息可繼續解密
  Future<void> clearKeys() async {
    _keyPair = null;
    _publicKeyBase64 = null;
    _currentUserId = null;
    // ✅ 不刪除 SecureStorage，各帳號的 key 和 history 永久保留
  }

  /// 取得目前歷史金鑰數量
  Future<int> getHistoryKeyCount() async {
    final history = await _loadHistoryPrivateKeys();
    return history.length;
  }

  /// 檢查並清除金鑰溢出警告標記（一次性讀取）
  /// 回傳是否有警告標記
  Future<bool> checkAndClearKeyOverflowWarning() async {
    final warning = await _secureStorage.read(key: _keyOverflowWarningKey);
    if (warning != null) {
      await _secureStorage.delete(key: _keyOverflowWarningKey);
      return true;
    }
    return false;
  }

  // --- Audio/File Encryption Methods ---

  /// Generates a random 256-bit AES key for file encryption
  /// Returns base64-encoded key string
  Future<String> generateRandomKey() async {
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Encode(keyBytes);
  }

  /// Encrypts bytes using AES-GCM with the provided key
  /// Returns: nonce (12 bytes) + MAC (16 bytes) + ciphertext
  Future<Uint8List> encryptBytes(Uint8List plainBytes, String keyBase64) async {
    final keyBytes = base64Decode(keyBase64);
    final secretKey = SecretKey(keyBytes);

    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: secretKey,
    );

    // Combine nonce + mac + cipherText
    final combinedBytes = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.mac.bytes,
      ...secretBox.cipherText,
    ]);

    return combinedBytes;
  }

  /// Decrypts bytes using AES-GCM with the provided key
  /// Expects: nonce (12 bytes) + MAC (16 bytes) + ciphertext
  Future<Uint8List> decryptBytes(Uint8List encryptedBytes, String keyBase64) async {
    if (encryptedBytes.length < 28) {
      throw Exception('Invalid encrypted data: too short');
    }

    final nonce = encryptedBytes.sublist(0, 12);
    final macBytes = encryptedBytes.sublist(12, 28);
    final cipherText = encryptedBytes.sublist(28);

    final keyBytes = base64Decode(keyBase64);
    final secretKey = SecretKey(keyBytes);

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
      return Uint8List.fromList(plainTextBytes);
    } catch (e) {
      throw Exception('Decryption failed: invalid key or corrupted data');
    }
  }
}

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoService();
});
