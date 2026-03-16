import { x25519 } from '@noble/curves/ed25519.js';

// AES-GCM constants matching Flutter CryptoService format
const AES_GCM_NONCE_LENGTH = 12;
const AES_GCM_TAG_LENGTH = 16;

/**
 * Web CryptoService — X25519 金鑰對產生與 E2EE 工具
 *
 * 使用 @noble/curves 實作 X25519 金鑰交換（相容 Flutter CryptoService 的 base64 格式）。
 * Web Crypto API 的 X25519 支援尚未普及，因此採用 @noble/curves 確保跨瀏覽器相容性。
 */

/**
 * 產生 X25519 金鑰對。
 * @returns {{ publicKey: string, privateKey: Uint8Array }}
 *   - publicKey: base64 編碼的 32-byte 公鑰（與後端 / Flutter 端格式一致）
 *   - privateKey: 原始 32-byte 私鑰（Uint8Array，不應離開記憶體）
 */
export function generateX25519KeyPair() {
  const privateKey = x25519.utils.randomSecretKey();
  const publicKeyBytes = x25519.getPublicKey(privateKey);
  const publicKey = uint8ArrayToBase64(publicKeyBytes);
  return { publicKey, privateKey };
}

/**
 * 將 Uint8Array 轉換為 base64 字串。
 * @param {Uint8Array} bytes
 * @returns {string}
 */
export function uint8ArrayToBase64(bytes) {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * 將 base64 字串轉換為 Uint8Array。
 * @param {string} base64
 * @returns {Uint8Array}
 */
export function base64ToUint8Array(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}


/**
 * 使用 X25519 ECDH + AES-256-GCM 解密 Session Key。
 *
 * 加密格式（與 Flutter CryptoService 一致）：
 *   base64( nonce[12] + mac[16] + ciphertext )
 *
 * @param {string} encryptedKeyBase64 — 加密後的 Session Key（base64）
 * @param {string} senderPublicKeyBase64 — 發送方（Primary Device）的 X25519 公鑰（base64）
 * @param {Uint8Array} privateKey — 本機 X25519 私鑰（32 bytes）
 * @returns {Promise<string>} 解密後的 Session Key（base64）
 */
export async function decryptSessionKey(encryptedKeyBase64, senderPublicKeyBase64, privateKey) {
  const encryptedBytes = base64ToUint8Array(encryptedKeyBase64);

  if (encryptedBytes.length < AES_GCM_NONCE_LENGTH + AES_GCM_TAG_LENGTH) {
    throw new Error('Invalid encrypted session key: too short');
  }

  // Parse: nonce (12) + mac/tag (16) + ciphertext
  const nonce = encryptedBytes.slice(0, AES_GCM_NONCE_LENGTH);
  const tag = encryptedBytes.slice(AES_GCM_NONCE_LENGTH, AES_GCM_NONCE_LENGTH + AES_GCM_TAG_LENGTH);
  const ciphertext = encryptedBytes.slice(AES_GCM_NONCE_LENGTH + AES_GCM_TAG_LENGTH);

  // Derive shared secret via X25519 ECDH
  const senderPublicKeyBytes = base64ToUint8Array(senderPublicKeyBase64);
  const sharedSecret = x25519.getSharedSecret(privateKey, senderPublicKeyBytes);

  // Import shared secret as AES-GCM key
  const aesKey = await crypto.subtle.importKey(
    'raw',
    sharedSecret,
    { name: 'AES-GCM' },
    false,
    ['decrypt'],
  );

  // Web Crypto API expects ciphertext + tag concatenated
  const ciphertextWithTag = new Uint8Array(ciphertext.length + tag.length);
  ciphertextWithTag.set(ciphertext);
  ciphertextWithTag.set(tag, ciphertext.length);

  const plainBytes = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: nonce, tagLength: AES_GCM_TAG_LENGTH * 8 },
    aesKey,
    ciphertextWithTag,
  );

  return uint8ArrayToBase64(new Uint8Array(plainBytes));
}

/**
 * 使用 AES-256-GCM 解密訊息內容。
 *
 * 加密格式（與 Flutter CryptoService 一致）：
 *   base64( nonce[12] + mac[16] + ciphertext )
 *
 * 此方法使用對稱金鑰直接解密（不涉及 ECDH），供聊天頁面解密已連結裝置收到的訊息。
 *
 * @param {string} encryptedContentBase64 — 加密後的訊息內容（base64）
 * @param {string} sessionKeyBase64 — AES-256 Session Key（base64）
 * @returns {Promise<string>} 解密後的明文訊息（UTF-8 字串）
 * @throws {Error} 若輸入過短、金鑰無效或資料損毀
 */
export async function decryptMessage(encryptedContentBase64, sessionKeyBase64) {
  const encryptedBytes = base64ToUint8Array(encryptedContentBase64);

  if (encryptedBytes.length < AES_GCM_NONCE_LENGTH + AES_GCM_TAG_LENGTH) {
    throw new Error('Invalid encrypted message: too short');
  }

  // Parse: nonce (12) + mac/tag (16) + ciphertext
  const nonce = encryptedBytes.slice(0, AES_GCM_NONCE_LENGTH);
  const tag = encryptedBytes.slice(AES_GCM_NONCE_LENGTH, AES_GCM_NONCE_LENGTH + AES_GCM_TAG_LENGTH);
  const ciphertext = encryptedBytes.slice(AES_GCM_NONCE_LENGTH + AES_GCM_TAG_LENGTH);

  // Import session key directly as AES-GCM key
  const sessionKeyBytes = base64ToUint8Array(sessionKeyBase64);
  const aesKey = await crypto.subtle.importKey(
    'raw',
    sessionKeyBytes,
    { name: 'AES-GCM' },
    false,
    ['decrypt'],
  );

  // Web Crypto API expects ciphertext + tag concatenated
  const ciphertextWithTag = new Uint8Array(ciphertext.length + tag.length);
  ciphertextWithTag.set(ciphertext);
  ciphertextWithTag.set(tag, ciphertext.length);

  try {
    const plainBytes = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: nonce, tagLength: AES_GCM_TAG_LENGTH * 8 },
      aesKey,
      ciphertextWithTag,
    );

    return new TextDecoder().decode(plainBytes);
  } catch (e) {
    throw new Error('Decryption failed: invalid key or corrupted data');
  }
}

