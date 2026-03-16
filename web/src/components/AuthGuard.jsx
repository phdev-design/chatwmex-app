import React, { useMemo } from 'react';
import { Navigate } from 'react-router-dom';

/**
 * Decode a JWT token's payload without verifying the signature.
 * Returns the parsed payload object, or null if the token is malformed.
 *
 * @param {string} token — a JWT string (header.payload.signature)
 * @returns {Object|null}
 */
export function decodeJwtPayload(token) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    // Base64url → Base64 → decode
    const base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const json = atob(base64);
    return JSON.parse(json);
  } catch {
    return null;
  }
}

/**
 * Check whether a JWT token string is present and not expired.
 *
 * @param {string|null} token
 * @returns {boolean}
 */
export function isTokenValid(token) {
  if (!token) return false;

  const payload = decodeJwtPayload(token);
  if (!payload) return false;

  // If there's no exp claim, treat the token as invalid
  if (typeof payload.exp !== 'number') return false;

  // exp is in seconds; Date.now() is in milliseconds
  return payload.exp * 1000 > Date.now();
}

/**
 * Auth Guard component — validates the JWT token stored in localStorage
 * on every page load. If the token is missing or expired, redirects to
 * the QR login page.
 *
 * Validates: Requirements 8.4
 *
 * @param {{ children: React.ReactNode }} props
 */
const AuthGuard = ({ children }) => {
  const isAuthenticated = useMemo(() => {
    const token = localStorage.getItem('token');
    return isTokenValid(token);
  }, []);

  if (!isAuthenticated) {
    return <Navigate to="/qr-login" replace />;
  }

  return children;
};

export default AuthGuard;
