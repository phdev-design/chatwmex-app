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
