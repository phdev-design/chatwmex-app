import React, { useState, useEffect } from 'react';
import { getMyRooms, searchUsers, getHistory, markAsRead } from '../api';
import useWebSocket from '../hooks/useWebSocket';

const Chat = () => {
  const [rooms, setRooms] = useState([]);
  const [users, setUsers] = useState([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedChat, setSelectedChat] = useState(null); // { id, type: 'room' | 'user', name }
  const [messages, setMessages] = useState([]);
  const [newMessage, setNewMessage] = useState('');
  const [token] = useState(localStorage.getItem('token'));
  const [userId] = useState(localStorage.getItem('user_id'));
  const { messages: wsMessages, sendMessage, isConnected } = useWebSocket(token);

  useEffect(() => {
    // Load my rooms on mount
    const fetchRooms = async () => {
      try {
        const data = await getMyRooms();
        setRooms(data || []);
      } catch (err) {
        console.error('Failed to fetch rooms:', err);
      }
    };
    fetchRooms();
  }, []);

  useEffect(() => {
    // When a new message arrives via WebSocket, append it if it belongs to current chat
    if (wsMessages.length > 0) {
      const lastMsg = wsMessages[wsMessages.length - 1];
      if (selectedChat) {
        if (
          (selectedChat.type === 'room' && lastMsg.room_id === selectedChat.id) ||
          (selectedChat.type === 'user' && (lastMsg.sender_id === selectedChat.id || lastMsg.receiver_id === selectedChat.id))
        ) {
          setMessages((prev) => [...prev, lastMsg]);
          // Mark as read if it's incoming
          if (lastMsg.sender_id !== userId) {
            markAsRead(selectedChat.id, selectedChat.type === 'room');
          }
        }
      }
    }
  }, [wsMessages, selectedChat, userId]);

  const handleSearch = async (e) => {
    e.preventDefault();
    if (!searchQuery) return;
    try {
      const results = await searchUsers(searchQuery);
      setUsers(results || []);
    } catch (err) {
      console.error('Search failed:', err);
    }
  };

  const selectChat = async (chat) => {
    setSelectedChat(chat);
    try {
      const history = await getHistory(chat.id);
      setMessages(history || []);
      // Mark messages as read when opening chat
      await markAsRead(chat.id, chat.type === 'room');
    } catch (err) {
      console.error('Failed to load history:', err);
    }
  };

  const handleSendMessage = (e) => {
    e.preventDefault();
    if (!newMessage.trim() || !selectedChat) return;

    if (selectedChat.type === 'room') {
      sendMessage(null, selectedChat.id, newMessage);
    } else {
      sendMessage(selectedChat.id, null, newMessage);
    }
    setNewMessage('');
    // Optimistic UI update could be done here, but WS will echo back
  };

  return (
    <div className="flex h-screen bg-gray-100">
      {/* Sidebar */}
      <div className="w-1/4 bg-white border-r border-gray-200 flex flex-col">
        <div className="p-4 border-b border-gray-200">
          <h2 className="text-xl font-bold mb-4">ChatWmex</h2>
          <form onSubmit={handleSearch} className="flex gap-2">
            <input
              type="text"
              placeholder="Search users..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="flex-1 p-2 border rounded"
            />
            <button type="submit" className="bg-blue-500 text-white p-2 rounded">Search</button>
          </form>
        </div>
        
        <div className="flex-1 overflow-y-auto p-4">
          <h3 className="font-semibold text-gray-500 mb-2">Rooms</h3>
          <ul>
            {rooms.map((room) => (
              <li
                key={room.id}
                onClick={() => selectChat({ id: room.id, type: 'room', name: room.name })}
                className={`p-2 cursor-pointer hover:bg-gray-100 rounded ${selectedChat?.id === room.id ? 'bg-blue-100' : ''}`}
              >
                # {room.name}
              </li>
            ))}
          </ul>

          <h3 className="font-semibold text-gray-500 mt-4 mb-2">Users</h3>
          <ul>
            {users.map((user) => (
              <li
                key={user.id}
                onClick={() => selectChat({ id: user.id, type: 'user', name: user.username })}
                className={`p-2 cursor-pointer hover:bg-gray-100 rounded ${selectedChat?.id === user.id ? 'bg-blue-100' : ''}`}
              >
                @ {user.username}
              </li>
            ))}
          </ul>
        </div>
      </div>

      {/* Chat Area */}
      <div className="flex-1 flex flex-col">
        {selectedChat ? (
          <>
            <div className="p-4 bg-white border-b border-gray-200 flex justify-between items-center">
              <h3 className="text-lg font-bold">{selectedChat.name}</h3>
              <span className={`text-sm ${isConnected ? 'text-green-500' : 'text-red-500'}`}>
                {isConnected ? 'Connected' : 'Disconnected'}
              </span>
            </div>

            <div className="flex-1 overflow-y-auto p-4 space-y-4">
              {messages.map((msg, idx) => {
                const isMe = msg.sender_id === userId;
                return (
                  <div key={idx} className={`flex ${isMe ? 'justify-end' : 'justify-start'}`}>
                    <div className={`max-w-xs lg:max-w-md px-4 py-2 rounded-lg ${isMe ? 'bg-blue-500 text-white' : 'bg-gray-200 text-gray-800'}`}>
                      <p>{msg.content}</p>
                      <span className="text-xs opacity-75 block text-right mt-1">
                        {new Date(msg.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        {isMe && msg.is_read && <span className="ml-2">✓✓</span>}
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>

            <div className="p-4 bg-white border-t border-gray-200">
              <form onSubmit={handleSendMessage} className="flex gap-2">
                <input
                  type="text"
                  placeholder="Type a message..."
                  value={newMessage}
                  onChange={(e) => setNewMessage(e.target.value)}
                  className="flex-1 p-2 border rounded"
                />
                <button type="submit" className="bg-blue-500 text-white px-6 py-2 rounded hover:bg-blue-600">
                  Send
                </button>
              </form>
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-gray-500">
            Select a chat to start messaging
          </div>
        )}
      </div>
    </div>
  );
};

export default Chat;
