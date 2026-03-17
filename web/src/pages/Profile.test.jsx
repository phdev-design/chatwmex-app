/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';

// ─── Mocks ────────────────────────────────────────────────────────────────────

vi.mock('../api', () => ({
  getProfile: vi.fn(),
  updateProfile: vi.fn(),
  getLinkedDevices: vi.fn(),
  removeDevice: vi.fn(),
}));

vi.mock('../crypto/sessionKeyStore.js', () => ({
  clearSessionKey: vi.fn(),
}));

const mockNavigate = vi.fn();
vi.mock('react-router-dom', () => ({
  useNavigate: vi.fn(() => mockNavigate),
}));

import { getProfile, updateProfile, getLinkedDevices, removeDevice } from '../api';
import { clearSessionKey } from '../crypto/sessionKeyStore.js';
import Profile from './Profile.jsx';

// ─── Setup ────────────────────────────────────────────────────────────────────

const mockProfile = { id: 'u1', username: 'testuser', avatar_url: null };
const mockDevices = [
  {
    id: 'dev-1',
    name: 'iPhone 15',
    type: 'mobile',
    last_active_at: new Date().toISOString(),
  },
];

beforeEach(() => {
  vi.clearAllMocks();
  getProfile.mockResolvedValue(mockProfile);
  getLinkedDevices.mockResolvedValue(mockDevices);
  updateProfile.mockResolvedValue(mockProfile);
  removeDevice.mockResolvedValue(undefined);
  localStorage.clear();
  localStorage.setItem('token', 'test-token');
  localStorage.setItem('user_id', 'u1');
  localStorage.setItem('device_private_key', 'test-key');
});

afterEach(() => {
  cleanup();
});

// ─── Requirement 9.5: Logout flow ─────────────────────────────────────────────

describe('Requirement 9.5: Logout flow', () => {
  it('calls clearSessionKey, removes localStorage items, and navigates to /qr-login', async () => {
    render(<Profile />);

    // Wait for profile to load
    await waitFor(() => expect(screen.getByText('Logout')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Logout'));

    await waitFor(() => {
      expect(clearSessionKey).toHaveBeenCalledTimes(1);
      expect(localStorage.getItem('token')).toBeNull();
      expect(localStorage.getItem('user_id')).toBeNull();
      expect(localStorage.getItem('device_private_key')).toBeNull();
      expect(mockNavigate).toHaveBeenCalledWith('/qr-login');
    });
  });
});

// ─── Requirement 9.6: updateProfile failure preserves input ───────────────────

describe('Requirement 9.6: updateProfile failure preserves input', () => {
  it('keeps username input value and shows error message when updateProfile throws', async () => {
    updateProfile.mockRejectedValue(new Error('Server error'));

    render(<Profile />);

    // Wait for profile to load and input to be populated
    await waitFor(() =>
      expect(screen.getByPlaceholderText('Username')).toHaveValue('testuser'),
    );

    // Change the username
    const input = screen.getByPlaceholderText('Username');
    fireEvent.change(input, { target: { value: 'newname' } });
    expect(input).toHaveValue('newname');

    // Click Save
    fireEvent.click(screen.getByText('Save'));

    await waitFor(() => {
      // Input value is preserved
      expect(screen.getByPlaceholderText('Username')).toHaveValue('newname');
      // Error message is displayed
      expect(screen.getByText('Server error')).toBeInTheDocument();
    });
  });
});

// ─── Requirement 10.5: removeDevice failure keeps device in list ──────────────

describe('Requirement 10.5: removeDevice failure keeps device in list', () => {
  it('keeps device in list and shows error message when removeDevice throws', async () => {
    removeDevice.mockRejectedValue(new Error('移除失敗'));

    render(<Profile />);

    // Wait for device to appear
    await waitFor(() => expect(screen.getByText('iPhone 15')).toBeInTheDocument());

    // Click the remove button for the device
    fireEvent.click(screen.getByText('移除'));

    await waitFor(() => {
      // Device is still in the list
      expect(screen.getByText('iPhone 15')).toBeInTheDocument();
      // Error message is displayed
      expect(screen.getByText('移除失敗')).toBeInTheDocument();
    });
  });
});
