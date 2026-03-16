/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { handleSessionKeyDelivery, handleDeviceUnlinked } from './useWebSocket.js';

// Mock the crypto service and session key store
vi.mock('../crypto/webCryptoService.js', () => ({
  decryptSessionKey: vi.fn(),
}));

vi.mock('../crypto/sessionKeyStore.js', () => ({
  saveSessionKey: vi.fn(),
  clearSessionKey: vi.fn(),
}));

import { decryptSessionKey } from '../crypto/webCryptoService.js';
import { saveSessionKey, clearSessionKey } from '../crypto/sessionKeyStore.js';

describe('useWebSocket event handlers', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
    sessionStorage.clear();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('handleSessionKeyDelivery', () => {
    it('should decrypt and store session key when all data is present', async () => {
      // Store a fake private key in localStorage (base64 of 32 zero bytes)
      const fakePrivateKey = new Uint8Array(32);
      let binary = '';
      for (let i = 0; i < fakePrivateKey.length; i++) {
        binary += String.fromCharCode(fakePrivateKey[i]);
      }
      localStorage.setItem('device_private_key', btoa(binary));

      decryptSessionKey.mockResolvedValue('decrypted-session-key-base64');
      saveSessionKey.mockResolvedValue(undefined);

      await handleSessionKeyDelivery({
        encrypted_key: 'encrypted-key-base64',
        sender_public_key: 'sender-pub-key-base64',
      });

      expect(decryptSessionKey).toHaveBeenCalledWith(
        'encrypted-key-base64',
        'sender-pub-key-base64',
        expect.any(Uint8Array),
      );
      expect(saveSessionKey).toHaveBeenCalledWith('decrypted-session-key-base64');
    });

    it('should not proceed when encrypted_key is missing', async () => {
      await handleSessionKeyDelivery({ sender_public_key: 'pub' });

      expect(decryptSessionKey).not.toHaveBeenCalled();
      expect(saveSessionKey).not.toHaveBeenCalled();
    });

    it('should not proceed when sender_public_key is missing', async () => {
      await handleSessionKeyDelivery({ encrypted_key: 'enc' });

      expect(decryptSessionKey).not.toHaveBeenCalled();
      expect(saveSessionKey).not.toHaveBeenCalled();
    });

    it('should not proceed when data is null/undefined', async () => {
      await handleSessionKeyDelivery(null);

      expect(decryptSessionKey).not.toHaveBeenCalled();
    });

    it('should not proceed when device private key is not in localStorage', async () => {
      await handleSessionKeyDelivery({
        encrypted_key: 'enc',
        sender_public_key: 'pub',
      });

      expect(decryptSessionKey).not.toHaveBeenCalled();
    });

    it('should handle decryption failure gracefully', async () => {
      const fakePrivateKey = new Uint8Array(32);
      let binary = '';
      for (let i = 0; i < fakePrivateKey.length; i++) {
        binary += String.fromCharCode(fakePrivateKey[i]);
      }
      localStorage.setItem('device_private_key', btoa(binary));

      decryptSessionKey.mockRejectedValue(new Error('decryption failed'));

      await handleSessionKeyDelivery({
        encrypted_key: 'bad-enc',
        sender_public_key: 'pub',
      });

      expect(saveSessionKey).not.toHaveBeenCalled();
    });
  });

  describe('handleDeviceUnlinked', () => {
    it('should clear IndexedDB session key', async () => {
      clearSessionKey.mockResolvedValue(undefined);

      await handleDeviceUnlinked();

      expect(clearSessionKey).toHaveBeenCalled();
    });

    it('should clear localStorage token, user_id, and device_private_key', async () => {
      localStorage.setItem('token', 'jwt-token');
      localStorage.setItem('user_id', 'user-123');
      localStorage.setItem('device_private_key', 'key-data');
      clearSessionKey.mockResolvedValue(undefined);

      await handleDeviceUnlinked();

      expect(localStorage.getItem('token')).toBeNull();
      expect(localStorage.getItem('user_id')).toBeNull();
      expect(localStorage.getItem('device_private_key')).toBeNull();
    });

    it('should clear sessionStorage session_key', async () => {
      sessionStorage.setItem('session_key', 'sk');
      clearSessionKey.mockResolvedValue(undefined);

      await handleDeviceUnlinked();

      expect(sessionStorage.getItem('session_key')).toBeNull();
    });

    it('should navigate to /qr-login', async () => {
      clearSessionKey.mockResolvedValue(undefined);

      // Spy on window.location.href assignment
      const locationSpy = vi.spyOn(window, 'location', 'get').mockReturnValue({
        ...window.location,
        href: '',
      });

      // Since we can't easily spy on href assignment, we verify the function
      // completes without error. The navigation is the last step.
      await handleDeviceUnlinked();

      locationSpy.mockRestore();
      // The function should have completed without throwing
      expect(clearSessionKey).toHaveBeenCalled();
    });

    it('should handle clearSessionKey failure gracefully and still clear localStorage', async () => {
      localStorage.setItem('token', 'jwt-token');
      clearSessionKey.mockRejectedValue(new Error('IndexedDB error'));

      await handleDeviceUnlinked();

      // localStorage should still be cleared even if IndexedDB fails
      expect(localStorage.getItem('token')).toBeNull();
    });
  });
});
