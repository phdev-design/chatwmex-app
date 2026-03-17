import api from './axios';

export const login = async (username, password) => {
  const response = await api.post('/users/login', { username, password });
  return response.data;
};

export const register = async (username, password, email) => {
  const response = await api.post('/users/register', { username, password, email });
  return response.data;
};

export const getMyRooms = async () => {
  const response = await api.get('/rooms/my');
  return response.data;
};

export const searchUsers = async (query) => {
  const response = await api.get(`/users/search?q=${query}`);
  return response.data;
};

export const getHistory = async (contactId, limit = 50, offset = 0) => {
  // contactId can be UserID or RoomID
  const response = await api.get(`/messages/history?contact_id=${contactId}&limit=${limit}&offset=${offset}`);
  return response.data;
};

export const markAsRead = async (conversationId, isRoom) => {
  const response = await api.post('/messages/read', { conversation_id: conversationId, is_room: isRoom });
  return response.data;
};

// Friends API
export const getFriends = async () => {
  const response = await api.get('/friends');
  return response.data;
};

export const sendFriendRequest = async (userId) => {
  const response = await api.post('/friends/request', { user_id: userId });
  return response.data;
};

export const acceptFriendRequest = async (requestId) => {
  const response = await api.post('/friends/accept', { request_id: requestId });
  return response.data;
};

export const rejectFriendRequest = async (requestId) => {
  const response = await api.post('/friends/reject', { request_id: requestId });
  return response.data;
};

export const blockUser = async (userId) => {
  const response = await api.post('/friends/block', { user_id: userId });
  return response.data;
};

export const unblockUser = async (userId) => {
  const response = await api.post('/friends/unblock', { user_id: userId });
  return response.data;
};

export const getFriendRequests = async () => {
  const response = await api.get('/friends/requests');
  return response.data;
};

// Rooms API
export const createRoom = async (name, memberIds) => {
  const response = await api.post('/rooms', { name, member_ids: memberIds });
  return response.data;
};

export const getRoomMembers = async (roomId) => {
  const response = await api.get(`/rooms/${roomId}/members`);
  return response.data;
};

// Devices API
export const getLinkedDevices = async () => {
  const response = await api.get('/devices');
  return response.data;
};

export const removeDevice = async (deviceId) => {
  const response = await api.delete(`/devices/${deviceId}`);
  return response.data;
};

// Profile API
export const getProfile = async () => {
  const response = await api.get('/users/me');
  return response.data;
};

export const updateProfile = async (username, avatarUrl) => {
  const response = await api.put('/users/me', { username, avatar_url: avatarUrl });
  return response.data;
};
