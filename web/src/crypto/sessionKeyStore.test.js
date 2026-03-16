import { describe, it, expect, beforeEach } from 'vitest';
import 'fake-indexeddb/auto';
import {
  saveSessionKey,
  getSessionKey,
  clearSessionKey,
  hasSessionKey,
} from './sessionKeyStore.js';

describe('sessionKeyStore', () => {
  beforeEach(async () => {
    await clearSessionKey();
  });

  describe('saveSessionKey / getSessionKey', () => {
    it('should store and retrieve a session key', async () => {
      const key = 'dGVzdC1zZXNzaW9uLWtleQ=='; // base64 of "test-session-key"
      await saveSessionKey(key);
      const retrieved = await getSessionKey();
      expect(retrieved).toBe(key);
    });

    it('should overwrite existing key on subsequent save', async () => {
      await saveSessionKey('a2V5MQ==');
      await saveSessionKey('a2V5Mg==');
      const retrieved = await getSessionKey();
      expect(retrieved).toBe('a2V5Mg==');
    });
  });

  describe('getSessionKey (empty)', () => {
    it('should return null when no key is stored', async () => {
      const result = await getSessionKey();
      expect(result).toBeNull();
    });
  });

  describe('clearSessionKey', () => {
    it('should remove the stored key', async () => {
      await saveSessionKey('dG9CZUNsZWFyZWQ=');
      await clearSessionKey();
      const result = await getSessionKey();
      expect(result).toBeNull();
    });

    it('should not throw when clearing an already empty store', async () => {
      await expect(clearSessionKey()).resolves.not.toThrow();
    });
  });

  describe('hasSessionKey', () => {
    it('should return false when no key exists', async () => {
      expect(await hasSessionKey()).toBe(false);
    });

    it('should return true after saving a key', async () => {
      await saveSessionKey('c29tZUtleQ==');
      expect(await hasSessionKey()).toBe(true);
    });

    it('should return false after clearing', async () => {
      await saveSessionKey('c29tZUtleQ==');
      await clearSessionKey();
      expect(await hasSessionKey()).toBe(false);
    });
  });
});
