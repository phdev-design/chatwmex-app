import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as fc from 'fast-check';

// Mock the axios module before importing api functions
vi.mock('./axios', () => {
  const mockApi = {
    get: vi.fn(),
    post: vi.fn(),
    put: vi.fn(),
    delete: vi.fn(),
  };
  return { default: mockApi };
});

import api from './axios';
import {
  getFriends,
  sendFriendRequest,
  acceptFriendRequest,
  rejectFriendRequest,
  blockUser,
  unblockUser,
  getFriendRequests,
  createRoom,
  getRoomMembers,
  getLinkedDevices,
  removeDevice,
  getProfile,
  updateProfile,
} from './index';

beforeEach(() => {
  vi.clearAllMocks();
});

// Helper: make axios mock resolve with data
const mockResolve = (data) => ({ data });

// ─── Unit Tests: Endpoint & Method Verification ───────────────────────────────

describe('getFriends', () => {
  it('calls GET /friends', async () => {
    api.get.mockResolvedValueOnce(mockResolve([]));
    await getFriends();
    expect(api.get).toHaveBeenCalledWith('/friends');
  });
});

describe('sendFriendRequest', () => {
  it('calls POST /friends/request with { user_id }', async () => {
    api.post.mockResolvedValueOnce(mockResolve({}));
    await sendFriendRequest('user-123');
    expect(api.post).toHaveBeenCalledWith('/friends/request', { user_id: 'user-123' });
  });
});

describe('acceptFriendRequest', () => {
  it('calls POST /friends/accept with { request_id }', async () => {
    api.post.mockResolvedValueOnce(mockResolve({}));
    await acceptFriendRequest('req-456');
    expect(api.post).toHaveBeenCalledWith('/friends/accept', { request_id: 'req-456' });
  });
});

describe('rejectFriendRequest', () => {
  it('calls POST /friends/reject with { request_id }', async () => {
    api.post.mockResolvedValueOnce(mockResolve({}));
    await rejectFriendRequest('req-789');
    expect(api.post).toHaveBeenCalledWith('/friends/reject', { request_id: 'req-789' });
  });
});

describe('blockUser', () => {
  it('calls POST /friends/block with { user_id }', async () => {
    api.post.mockResolvedValueOnce(mockResolve({}));
    await blockUser('user-abc');
    expect(api.post).toHaveBeenCalledWith('/friends/block', { user_id: 'user-abc' });
  });
});

describe('unblockUser', () => {
  it('calls POST /friends/unblock with { user_id }', async () => {
    api.post.mockResolvedValueOnce(mockResolve({}));
    await unblockUser('user-abc');
    expect(api.post).toHaveBeenCalledWith('/friends/unblock', { user_id: 'user-abc' });
  });
});

describe('getFriendRequests', () => {
  it('calls GET /friends/requests', async () => {
    api.get.mockResolvedValueOnce(mockResolve([]));
    await getFriendRequests();
    expect(api.get).toHaveBeenCalledWith('/friends/requests');
  });
});

describe('createRoom', () => {
  it('calls POST /rooms with { name, member_ids }', async () => {
    api.post.mockResolvedValueOnce(mockResolve({}));
    await createRoom('My Room', ['u1', 'u2']);
    expect(api.post).toHaveBeenCalledWith('/rooms', { name: 'My Room', member_ids: ['u1', 'u2'] });
  });
});

describe('getRoomMembers', () => {
  it('calls GET /rooms/{roomId}/members', async () => {
    api.get.mockResolvedValueOnce(mockResolve([]));
    await getRoomMembers('room-99');
    expect(api.get).toHaveBeenCalledWith('/rooms/room-99/members');
  });
});

describe('getLinkedDevices', () => {
  it('calls GET /devices', async () => {
    api.get.mockResolvedValueOnce(mockResolve([]));
    await getLinkedDevices();
    expect(api.get).toHaveBeenCalledWith('/devices');
  });
});

describe('removeDevice', () => {
  it('calls DELETE /devices/{deviceId}', async () => {
    api.delete.mockResolvedValueOnce(mockResolve({}));
    await removeDevice('dev-42');
    expect(api.delete).toHaveBeenCalledWith('/devices/dev-42');
  });
});

describe('getProfile', () => {
  it('calls GET /users/me', async () => {
    api.get.mockResolvedValueOnce(mockResolve({}));
    await getProfile();
    expect(api.get).toHaveBeenCalledWith('/users/me');
  });
});

describe('updateProfile', () => {
  it('calls PUT /users/me with { username, avatar_url }', async () => {
    api.put.mockResolvedValueOnce(mockResolve({}));
    await updateProfile('alice', 'https://example.com/avatar.png');
    expect(api.put).toHaveBeenCalledWith('/users/me', {
      username: 'alice',
      avatar_url: 'https://example.com/avatar.png',
    });
  });
});

// ─── Property 7: API Non-2xx Throws Error ─────────────────────────────────────
// Feature: web-e2ee-full-feature, Property 7: API non-2xx throws error

// All API functions that should throw on non-2xx responses
const apiFunctions = [
  { name: 'getFriends', fn: () => getFriends(), mockMethod: 'get' },
  { name: 'sendFriendRequest', fn: () => sendFriendRequest('u1'), mockMethod: 'post' },
  { name: 'acceptFriendRequest', fn: () => acceptFriendRequest('r1'), mockMethod: 'post' },
  { name: 'rejectFriendRequest', fn: () => rejectFriendRequest('r1'), mockMethod: 'post' },
  { name: 'blockUser', fn: () => blockUser('u1'), mockMethod: 'post' },
  { name: 'unblockUser', fn: () => unblockUser('u1'), mockMethod: 'post' },
  { name: 'getFriendRequests', fn: () => getFriendRequests(), mockMethod: 'get' },
  { name: 'createRoom', fn: () => createRoom('r', ['u1']), mockMethod: 'post' },
  { name: 'getRoomMembers', fn: () => getRoomMembers('room1'), mockMethod: 'get' },
  { name: 'getLinkedDevices', fn: () => getLinkedDevices(), mockMethod: 'get' },
  { name: 'removeDevice', fn: () => removeDevice('d1'), mockMethod: 'delete' },
  { name: 'getProfile', fn: () => getProfile(), mockMethod: 'get' },
  { name: 'updateProfile', fn: () => updateProfile('u', null), mockMethod: 'put' },
];

describe('Property 7: API non-2xx throws error', () => {
  it('all API functions throw when axios rejects with a 4xx/5xx error', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.integer({ min: 400, max: 599 }),
        fc.constantFrom(...apiFunctions),
        async (statusCode, { fn, mockMethod }) => {
          vi.clearAllMocks();

          // Simulate axios throwing an error with a response status (as axios does for non-2xx)
          const axiosError = new Error(`Request failed with status code ${statusCode}`);
          axiosError.response = { status: statusCode };
          api[mockMethod].mockRejectedValueOnce(axiosError);

          await expect(fn()).rejects.toThrow();
        }
      ),
      { numRuns: 100 }
    );
  });
});
