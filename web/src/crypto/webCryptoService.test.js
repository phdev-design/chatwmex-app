import { describe, it, expect } from 'vitest';
import * as fc from 'fast-check';
import {
  generateX25519KeyPair,
  uint8ArrayToBase64,
  base64ToUint8Array,
  encryptMessage,
  decryptMessage,
  encryptForRecipient,
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

  describe('encryptForRecipient', () => {
    /**
     * Decrypt a message encrypted with encryptForRecipient using the recipient's private key
     * and sender's public key (mirrors decryptSessionKey logic).
     */
    async function decryptForRecipient(encryptedBase64, senderPublicKeyBase64, recipientPrivateKey) {
      const { x25519 } = await import('@noble/curves/ed25519.js');
      const encryptedBytes = base64ToUint8Array(encryptedBase64);
      const nonce = encryptedBytes.slice(0, 12);
      const tag = encryptedBytes.slice(12, 28);
      const ciphertext = encryptedBytes.slice(28);

      const senderPublicKeyBytes = base64ToUint8Array(senderPublicKeyBase64);
      const sharedSecret = x25519.getSharedSecret(recipientPrivateKey, senderPublicKeyBytes);

      const aesKey = await crypto.subtle.importKey(
        'raw',
        sharedSecret,
        { name: 'AES-GCM' },
        false,
        ['decrypt'],
      );

      const ciphertextWithTag = new Uint8Array(ciphertext.length + tag.length);
      ciphertextWithTag.set(ciphertext);
      ciphertextWithTag.set(tag, ciphertext.length);

      const plainBytes = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: nonce, tagLength: 128 },
        aesKey,
        ciphertextWithTag,
      );

      return new TextDecoder().decode(plainBytes);
    }

    it('should encrypt and decrypt successfully (round-trip)', async () => {
      const sender = generateX25519KeyPair();
      const recipient = generateX25519KeyPair();
      const plaintext = 'Hello recipient! 你好 🔐';

      const encrypted = await encryptForRecipient(plaintext, recipient.publicKey, sender.privateKey);
      const decrypted = await decryptForRecipient(encrypted, sender.publicKey, recipient.privateKey);

      expect(decrypted).toBe(plaintext);
    });

    it('should return a base64 string', async () => {
      const sender = generateX25519KeyPair();
      const recipient = generateX25519KeyPair();

      const encrypted = await encryptForRecipient('test', recipient.publicKey, sender.privateKey);

      expect(typeof encrypted).toBe('string');
      expect(encrypted).toMatch(/^[A-Za-z0-9+/]+=*$/);
    });

    it('should produce output with correct minimum length (nonce + tag = 28 bytes)', async () => {
      const sender = generateX25519KeyPair();
      const recipient = generateX25519KeyPair();

      const encrypted = await encryptForRecipient('hi', recipient.publicKey, sender.privateKey);
      const bytes = base64ToUint8Array(encrypted);

      // nonce(12) + tag(16) + ciphertext(>=1)
      expect(bytes.length).toBeGreaterThan(28);
    });

    it('should produce different ciphertexts for the same plaintext (random nonce)', async () => {
      const sender = generateX25519KeyPair();
      const recipient = generateX25519KeyPair();
      const plaintext = 'same message';

      const enc1 = await encryptForRecipient(plaintext, recipient.publicKey, sender.privateKey);
      const enc2 = await encryptForRecipient(plaintext, recipient.publicKey, sender.privateKey);

      expect(enc1).not.toBe(enc2);
    });

    it('should fail to decrypt with wrong recipient private key', async () => {
      const sender = generateX25519KeyPair();
      const recipient = generateX25519KeyPair();
      const wrongRecipient = generateX25519KeyPair();

      const encrypted = await encryptForRecipient('secret', recipient.publicKey, sender.privateKey);

      await expect(
        decryptForRecipient(encrypted, sender.publicKey, wrongRecipient.privateKey),
      ).rejects.toThrow();
    });
  });
});

describe('Property-Based Tests', () => {
  // Feature: web-e2ee-full-feature, Property 1: encryptMessage/decryptMessage round-trip
  it('Property 1: encrypt then decrypt returns original plaintext for any valid key and plaintext', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.string(),
        fc.uint8Array({ minLength: 32, maxLength: 32 }),
        async (plaintext, keyBytes) => {
          const keyBase64 = uint8ArrayToBase64(keyBytes);
          const encrypted = await encryptMessage(plaintext, keyBase64);
          const decrypted = await decryptMessage(encrypted, keyBase64);
          expect(decrypted).toBe(plaintext);
        },
      ),
      { numRuns: 100 },
    );
  }, 30000);

  // Feature: web-e2ee-full-feature, Property 2: invalid session key throws error
  it('Property 2: encryptMessage throws for any key that is not valid 32-byte base64', async () => {
    // Generate invalid keys: strings that either aren't valid base64 or decode to != 32 bytes
    const invalidKeyArb = fc.oneof(
      // Random strings that are unlikely to be valid base64 of exactly 32 bytes
      fc.string({ minLength: 1, maxLength: 43 }).filter(s => {
        try {
          const bytes = base64ToUint8Array(s);
          return bytes.length !== 32;
        } catch {
          return true;
        }
      }),
      // base64 strings that decode to wrong lengths (not 32 bytes)
      fc.uint8Array({ minLength: 1, maxLength: 31 }).map(b => uint8ArrayToBase64(b)),
      fc.uint8Array({ minLength: 33, maxLength: 64 }).map(b => uint8ArrayToBase64(b)),
    );

    await fc.assert(
      fc.asyncProperty(
        fc.string(),
        invalidKeyArb,
        async (plaintext, invalidKey) => {
          await expect(encryptMessage(plaintext, invalidKey)).rejects.toThrow();
        },
      ),
      { numRuns: 100 },
    );
  }, 30000);

  // Feature: web-e2ee-full-feature, Property 4: encryptForRecipient round-trip
  it('Property 4: encryptForRecipient then decrypt returns original plaintext for any key pair and plaintext', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.string(),
        async (plaintext) => {
          const sender = generateX25519KeyPair();
          const recipient = generateX25519KeyPair();

          const encrypted = await encryptForRecipient(plaintext, recipient.publicKey, sender.privateKey);

          // Decrypt using recipient private key + sender public key (ECDH path)
          const { x25519 } = await import('@noble/curves/ed25519.js');
          const encryptedBytes = base64ToUint8Array(encrypted);
          const nonce = encryptedBytes.slice(0, 12);
          const tag = encryptedBytes.slice(12, 28);
          const ciphertext = encryptedBytes.slice(28);

          const senderPublicKeyBytes = base64ToUint8Array(sender.publicKey);
          const sharedSecret = x25519.getSharedSecret(recipient.privateKey, senderPublicKeyBytes);

          const aesKey = await crypto.subtle.importKey(
            'raw',
            sharedSecret,
            { name: 'AES-GCM' },
            false,
            ['decrypt'],
          );

          const ciphertextWithTag = new Uint8Array(ciphertext.length + tag.length);
          ciphertextWithTag.set(ciphertext);
          ciphertextWithTag.set(tag, ciphertext.length);

          const plainBytes = await crypto.subtle.decrypt(
            { name: 'AES-GCM', iv: nonce, tagLength: 128 },
            aesKey,
            ciphertextWithTag,
          );

          const decrypted = new TextDecoder().decode(plainBytes);
          expect(decrypted).toBe(plaintext);
        },
      ),
      { numRuns: 100 },
    );
  }, 60000);

  describe('Edge Cases', () => {
    it('Requirement 1.4: empty string encrypts and round-trips successfully', async () => {
      const keyBytes = new Uint8Array(32);
      crypto.getRandomValues(keyBytes);
      const keyBase64 = uint8ArrayToBase64(keyBytes);

      const encrypted = await encryptMessage('', keyBase64);
      expect(typeof encrypted).toBe('string');
      expect(encrypted.length).toBeGreaterThan(0);

      const decrypted = await decryptMessage(encrypted, keyBase64);
      expect(decrypted).toBe('');
    });

    it('Output format: nonce is 12 bytes and tag is 16 bytes in encryptMessage output', async () => {
      const keyBytes = new Uint8Array(32);
      crypto.getRandomValues(keyBytes);
      const keyBase64 = uint8ArrayToBase64(keyBytes);

      const encrypted = await encryptMessage('test message', keyBase64);
      const bytes = base64ToUint8Array(encrypted);

      // Format: nonce[12] + tag[16] + ciphertext[variable]
      expect(bytes.length).toBeGreaterThanOrEqual(12 + 16);

      const nonce = bytes.slice(0, 12);
      const tag = bytes.slice(12, 28);

      expect(nonce.length).toBe(12);
      expect(tag.length).toBe(16);
    });
  });
});
