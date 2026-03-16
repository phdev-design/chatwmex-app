import { describe, it, expect } from 'vitest';
import { decodeJwtPayload, isTokenValid } from './AuthGuard.jsx';

// --- Unit tests for helper functions ---

/**
 * Build a fake JWT with the given payload (no real signature).
 */
function fakeJwt(payload) {
  const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = btoa(JSON.stringify(payload));
  return `${header}.${body}.fake-signature`;
}

describe('decodeJwtPayload', () => {
  it('should decode a valid JWT payload', () => {
    const payload = { sub: 'user123', exp: 9999999999 };
    const token = fakeJwt(payload);
    expect(decodeJwtPayload(token)).toEqual(payload);
  });

  it('should return null for a token with fewer than 3 parts', () => {
    expect(decodeJwtPayload('only.two')).toBeNull();
    expect(decodeJwtPayload('single')).toBeNull();
  });

  it('should return null for a token with invalid base64 payload', () => {
    expect(decodeJwtPayload('a.!!!.c')).toBeNull();
  });

  it('should return null for a token whose payload is not valid JSON', () => {
    const header = btoa('{}');
    const body = btoa('not json{');
    expect(decodeJwtPayload(`${header}.${body}.sig`)).toBeNull();
  });

  it('should handle base64url characters (- and _)', () => {
    // Manually craft a payload that would use base64url chars
    const payload = { data: 'test+value/here' };
    const json = JSON.stringify(payload);
    const base64url = btoa(json).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    const token = `header.${base64url}.sig`;
    expect(decodeJwtPayload(token)).toEqual(payload);
  });
});

describe('isTokenValid', () => {
  it('should return false for null or empty token', () => {
    expect(isTokenValid(null)).toBe(false);
    expect(isTokenValid('')).toBe(false);
    expect(isTokenValid(undefined)).toBe(false);
  });

  it('should return false for a malformed token', () => {
    expect(isTokenValid('not-a-jwt')).toBe(false);
  });

  it('should return false for a token without exp claim', () => {
    const token = fakeJwt({ sub: 'user123' });
    expect(isTokenValid(token)).toBe(false);
  });

  it('should return false for an expired token', () => {
    // exp in the past (1 second ago)
    const exp = Math.floor(Date.now() / 1000) - 1;
    const token = fakeJwt({ sub: 'user123', exp });
    expect(isTokenValid(token)).toBe(false);
  });

  it('should return true for a token with future exp', () => {
    // exp 1 hour from now
    const exp = Math.floor(Date.now() / 1000) + 3600;
    const token = fakeJwt({ sub: 'user123', exp });
    expect(isTokenValid(token)).toBe(true);
  });

  it('should return false when exp is not a number', () => {
    const token = fakeJwt({ sub: 'user123', exp: 'not-a-number' });
    expect(isTokenValid(token)).toBe(false);
  });
});

// --- Integration-style tests verifying isTokenValid with realistic token scenarios ---

describe('AuthGuard token validation scenarios', () => {
  it('should reject when no token is provided (simulates empty localStorage)', () => {
    expect(isTokenValid(null)).toBe(false);
  });

  it('should reject an expired token (simulates stale localStorage)', () => {
    const exp = Math.floor(Date.now() / 1000) - 60;
    const expiredToken = fakeJwt({ sub: 'user123', exp });
    expect(isTokenValid(expiredToken)).toBe(false);
  });

  it('should accept a valid token (simulates fresh localStorage)', () => {
    const exp = Math.floor(Date.now() / 1000) + 3600;
    const validToken = fakeJwt({ sub: 'user123', exp });
    expect(isTokenValid(validToken)).toBe(true);
  });

  it('should reject a token that expires exactly now (boundary)', () => {
    const exp = Math.floor(Date.now() / 1000);
    const token = fakeJwt({ sub: 'user123', exp });
    expect(isTokenValid(token)).toBe(false);
  });
});
