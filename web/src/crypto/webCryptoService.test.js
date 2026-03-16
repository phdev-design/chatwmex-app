import { describe, it, expect } from 'vitest';
import {
  generateX25519KeyPair,
  uint8ArrayToBase64,
  base64ToUint8Array,
  decryptMessage,
} from './webCryptoService.js';

describe('webCryptoService', () => {
  describe('generateX25519KeyPair', () => {
    it('should return an object with publicKey (base64 string) and privateKey (Uint8Array)', () => {
      const keyPair = generateX25519KeyPair();
      expect(keyPair).toHaveProperty('publicKey');
      expect(keyPair).toHaveProperty('privateKey');
      expect(typeof keyPair.publicKey).toBe('string');
      expect(keyPair.privateKey).toBeInstanceOf(Uint8Array);
    });

    it('should generate a 32-byte private key', () => {
      const { privateKey } = generateX25519KeyPair();
      expect(privateKey.length).toBe(32);
    });

    it('should generate a base64 public key that decodes to 32 bytes', () => {
      const { publicKey } = generateX25519KeyPair();
      const decoded = base64ToUint8Array(publicKey);
      expect(decoded.length).toBe(32);
    });

    it('should generate unique key pairs on each call', () => {
      const kp1 = generateX25519KeyPair();
      const kp2 = generateX25519KeyPair();
      expect(kp1.publicKey).not.toBe(kp2.publicKey);
    });
  });

  describe('uint8ArrayToBase64 / base64ToUint8Array', () => {
    it('should round-trip correctly', () => {
      const original = new Uint8Array([0, 1, 127, 128, 255]);
      const b64 = uint8ArrayToBase64(original);
      const restored = base64ToUint8Array(b64);
      expect(restored).toEqual(original);
    });

    it('should handle empty array', () => {
      const empty = new Uint8Array(0);
      const b64 = uint8ArrayToBase64(empty);
      const restored = base64ToUint8Array(b64);
      expect(restored).toEqual(empty);
    });

    it('should produce valid base64 for 32-byte key', () => {
      const bytes = new Uint8Array(32);
      crypto.getRandomValues(bytes);
      const b64 = uint8ArrayToBase64(bytes);
      // base64 of 32 bytes = 44 chars (with padding)
      expect(b64.length).toBe(44);
      expect(b64).toMatch(/^[A-Za-z0-9+/]+=*$/);
    });
  });

  describe('decryptMessage', () => {
    /**
     * Helper: encrypt plaintext using Web Crypto API in the same
     * nonce[12] + mac[16] + ciphertext format used by Flutter CryptoService.
     */
    async function encryptForTest(plainText, sessionKeyBase64) {
      const keyBytes = base64ToUint8Array(sessionKeyBase64);
      const aesKey = await crypto.subtle.importKey(
        'raw',
        keyBytes,
        { name: 'AES-GCM' },
        false,
        ['encrypt'],
      );

      const nonce = crypto.getRandomValues(new Uint8Array(12));
      const plainBytes = new TextEncoder().encode(plainText);

      const ciphertextWithTag = new Uint8Array(
        await crypto.subtle.encrypt(
          { name: 'AES-GCM', iv: nonce, tagLength: 128 },
          aesKey,
          plainBytes,
        ),
      );

      // Web Crypto returns ciphertext + tag; reformat to nonce + tag + ciphertext
      const ciphertext = ciphertextWithTag.slice(0, ciphertextWithTag.length - 16);
      const tag = ciphertextWithTag.slice(ciphertextWithTag.length - 16);

      const combined = new Uint8Array(12 + 16 + ciphertext.length);
      combined.set(nonce, 0);
      combined.set(tag, 12);
      combined.set(ciphertext, 28);

      return uint8ArrayToBase64(combined);
    }

    /** Generate a random 256-bit key as base64. */
    function randomSessionKey() {
      const key = new Uint8Array(32);
      crypto.getRandomValues(key);
      return uint8ArrayToBase64(key);
    }

    it('should decrypt a message encrypted with the same session key (round-trip)', async () => {
      const sessionKey = randomSessionKey();
      const plainText = 'Hello, linked device! 你好世界 🎉';
      const encrypted = await encryptForTest(plainText, sessionKey);

      const result = await decryptMessage(encrypted, sessionKey);
      expect(result).toBe(plainText);
    });

    it('should throw on input shorter than 28 bytes', async () => {
      const sessionKey = randomSessionKey();
      const tooShort = uint8ArrayToBase64(new Uint8Array(27));

      await expect(decryptMessage(tooShort, sessionKey)).rejects.toThrow(
        'Invalid encrypted message: too short',
      );
    });

    it('should throw on corrupted ciphertext', async () => {
      const sessionKey = randomSessionKey();
      const encrypted = await encryptForTest('test message', sessionKey);

      // Corrupt a byte in the ciphertext portion
      const bytes = base64ToUint8Array(encrypted);
      bytes[bytes.length - 1] ^= 0xff;
      const corrupted = uint8ArrayToBase64(bytes);

      await expect(decryptMessage(corrupted, sessionKey)).rejects.toThrow(
        'Decryption failed: invalid key or corrupted data',
      );
    });

    it('should throw when using a wrong session key', async () => {
      const correctKey = randomSessionKey();
      const wrongKey = randomSessionKey();
      const encrypted = await encryptForTest('secret', correctKey);

      await expect(decryptMessage(encrypted, wrongKey)).rejects.toThrow(
        'Decryption failed: invalid key or corrupted data',
      );
    });
  });
});
