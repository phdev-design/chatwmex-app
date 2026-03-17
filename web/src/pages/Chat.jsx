import React, { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  getMyRooms,
  searchUsers,
  getHistory,
  markAsRead,
  getFriends,
  getFriendRequests,
  sendFriendRequest,
  acceptFriendRequest,
  rejectFriendRequest,
  blockUser,
  createRoom,
  getRoomMembers,
} from '../api';
import useWebSocket from '../hooks/useWebSocket';
import { getSessionKey } from '../crypto/sessionKeyStore.js';
import {
  encryptMessage,
  decryptMessage,
  encryptForRecipient,
  base64ToUint8Array,
} from '../crypto/webCryptoService.js';

const Chat = () => {
  const navigate = useNavigate();

  // Core state
  const [rooms, setRooms] = useState([]);
  const [users, setUsers] = useState([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedChat, setSelectedChat] = useState(null);
  const [messages, setMessages] = useState([]);
  const [newMessage, setNewMessage] = useState('');
  const [token] = useState(localStorage.getItem('token'));
  const [userId] = useState(localStorage.getItem('user_id'));

  // E2EE state (4.1)
  const [sessionKey, setSessionKey] = useState(null);
  const [sessionKeyLoading, setSessionKeyLoading] = useState(true);

  // Decrypted messages map: index -> decrypted content string
  const [decryptedMessages, setDecryptedMessages] = useState(new Map());

  // Presence state (4.5)
  const [onlineUsers, setOnlineUsers] = useState(new Map());

  // Sidebar tabs (4.6)
  const [activeTab, setActiveTab] = useState('rooms');
  const [friends, setFriends] = useState([]);
  const [friendRequests, setFriendRequests] = useState([]);

  // Group creation (4.12)
  const [showCreateGroup, setShowCreateGroup] = useState(false);
  const [groupName, setGroupName] = useState('');
  const [selectedMembers, setSelectedMembers] = useState([]);
  const [createGroupError, setCreateGroupError] = useState('');

  // Friend request sent tracking (4.9)
  const [sentRequests, setSentRequests] = useState(new Set());

  // Ref to sendRawEvent so re-encrypt handler can call it without stale closure
  const sendRawEventRef = useRef(null);

  // Task 4.1: Load session key from IndexedDB on mount
  useEffect(() => {
    getSessionKey()
      .then((key) => {
        setSessionKey(key);
        setSessionKeyLoading(false);
      })
      .catch(() => setSessionKeyLoading(false));
  }, []);

  // Task 4.4: Re-encrypt request handler
  const handleReEncryptRequest = useCallback(
    async ({ message_id, encrypted_content, new_session_key }) => {
      try {
        const plaintext = await decryptMessage(encrypted_content, sessionKey);
        const targetKey = new_session_key || sessionKey;
        const reEncrypted = await encryptMessage(plaintext, targetKey);
        sendRawEventRef.current?.('re_encrypt_response', {
          message_id,
          new_encrypted_content: reEncrypted,
        });
      } catch (err) {
        console.error('re_encrypt_request handling failed:', err);
        setMessages((prev) =>
          prev.map((m) => (m.id === message_id ? { ...m, decryptError: true } : m))
        );
      }
    },
    [sessionKey]
  );

  // Task 4.5: Presence update handler
  const handlePresenceUpdate = useCallback(({ user_id, status }) => {
    setOnlineUsers((prev) => {
      const next = new Map(prev);
      next.set(user_id, status);
      return next;
    });
  }, []);

  const { messages: wsMessages, sendMessage, sendRawEvent, isConnected } = useWebSocket(token, false, {
    onReEncryptRequest: handleReEncryptRequest,
    onPresenceUpdate: handlePresenceUpdate,
  });

  // Keep ref in sync with latest sendRawEvent
  useEffect(() => {
    sendRawEventRef.current = sendRawEvent;
  }, [sendRawEvent]);

  // Load rooms on mount
  useEffect(() => {
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

  // Task 4.3: Decrypt a single message content
  const decryptContent = useCallback(
    async (msg, key) => {
      if (!key) return '🔒 無法解密';
      try {
        // Group message with ciphertexts map (4.11)
        if (msg.ciphertexts) {
          const myCiphertext = msg.ciphertexts[userId];
          if (!myCiphertext) return '🔒 無法解密（未包含本裝置）';
          return await decryptMessage(myCiphertext, key);
        }
        if (!msg.content) return '';
        return await decryptMessage(msg.content, key);
      } catch (err) {
        console.error('Decryption failed:', err);
        return '🔒 無法解密';
      }
    },
    [userId]
  );

  // Task 4.3: Decrypt history messages when chat or sessionKey changes
  useEffect(() => {
    if (!sessionKey || messages.length === 0) return;
    const decryptAll = async () => {
      const entries = await Promise.all(
        messages.map(async (msg, idx) => {
          const content = await decryptContent(msg, sessionKey);
          return [idx, content];
        })
      );
      setDecryptedMessages(new Map(entries));
    };
    decryptAll();
  }, [messages, sessionKey, decryptContent]);

  // Task 4.3: Handle incoming WebSocket messages
  useEffect(() => {
    if (wsMessages.length === 0) return;
    const lastMsg = wsMessages[wsMessages.length - 1];
    if (lastMsg.event !== 'chat_message') return;
    const data = lastMsg.data || lastMsg;

    if (!selectedChat) return;
    const belongsToChat =
      (selectedChat.type === 'room' && data.room_id === selectedChat.id) ||
      (selectedChat.type === 'user' &&
        (data.sender_id === selectedChat.id || data.receiver_id === selectedChat.id));

    if (belongsToChat) {
      setMessages((prev) => [...prev, data]);
      if (data.sender_id !== userId) {
        markAsRead(selectedChat.id, selectedChat.type === 'room').catch(() => {});
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
    setDecryptedMessages(new Map());
    try {
      const history = await getHistory(chat.id);
      setMessages(history || []);
      await markAsRead(chat.id, chat.type === 'room');
    } catch (err) {
      console.error('Failed to load history:', err);
    }
  };

  // Task 4.2 + 4.10: Encrypted send (direct and group fanout)
  const handleSendMessage = async (e) => {
    e.preventDefault();
    if (!newMessage.trim() || !selectedChat || !sessionKey) return;

    try {
      if (selectedChat.type === 'room') {
        // Task 4.10: Group fanout encrypted send
        const members = await getRoomMembers(selectedChat.id);
        const privateKeyBase64 = localStorage.getItem('device_private_key');
        const privateKeyBytes = base64ToUint8Array(privateKeyBase64);
        const ciphertexts = {};
        for (const member of members) {
          ciphertexts[member.user_id] = await encryptForRecipient(
            newMessage,
            member.public_key,
            privateKeyBytes
          );
        }
        sendRawEvent('chat_message', {
          room_id: selectedChat.id,
          ciphertexts,
          type: 'text',
          client_msg_id: crypto.randomUUID(),
        });
      } else {
        // Task 4.2: Direct message encrypted send
        const encrypted = await encryptMessage(newMessage, sessionKey);
        sendMessage(selectedChat.id, null, encrypted);
      }
      setNewMessage('');
    } catch (err) {
      console.error('Failed to send message:', err);
    }
  };

  // Task 4.6: Tab switching
  const handleTabChange = async (tab) => {
    setActiveTab(tab);
    if (tab === 'friends') {
      try {
        const data = await getFriends();
        setFriends(data || []);
      } catch (err) {
        console.error('Failed to fetch friends:', err);
      }
    } else if (tab === 'requests') {
      try {
        const data = await getFriendRequests();
        setFriendRequests(data || []);
      } catch (err) {
        console.error('Failed to fetch friend requests:', err);
      }
    }
  };

  // Task 4.7: Block friend
  const handleBlockUser = async (friendId) => {
    try {
      await blockUser(friendId);
      setFriends((prev) => prev.filter((f) => f.id !== friendId));
    } catch (err) {
      console.error('Failed to block user:', err);
    }
  };

  // Task 4.8: Accept / reject friend request
  const handleAcceptRequest = async (requestId) => {
    try {
      await acceptFriendRequest(requestId);
      setFriendRequests((prev) => prev.filter((r) => r.id !== requestId));
    } catch (err) {
      console.error('Failed to accept request:', err);
    }
  };

  const handleRejectRequest = async (requestId) => {
    try {
      await rejectFriendRequest(requestId);
      setFriendRequests((prev) => prev.filter((r) => r.id !== requestId));
    } catch (err) {
      console.error('Failed to reject request:', err);
    }
  };

  // Task 4.9: Send friend request
  const handleSendFriendRequest = async (targetUserId) => {
    try {
      await sendFriendRequest(targetUserId);
      setSentRequests((prev) => new Set([...prev, targetUserId]));
    } catch (err) {
      console.error('Failed to send friend request:', err);
    }
  };

  // Task 4.12: Create group
  const handleCreateGroup = async () => {
    if (!groupName.trim()) return;
    setCreateGroupError('');
    try {
      const newRoom = await createRoom(groupName, selectedMembers);
      setRooms((prev) => [...prev, newRoom]);
      setShowCreateGroup(false);
      setGroupName('');
      setSelectedMembers([]);
    } catch (err) {
      console.error('Failed to create group:', err);
      setCreateGroupError('建立群組失敗，請再試一次。');
    }
  };

  const toggleMember = (memberId) => {
    setSelectedMembers((prev) =>
      prev.includes(memberId) ? prev.filter((id) => id !== memberId) : [...prev, memberId]
    );
  };

  // Presence dot helper
  const PresenceDot = ({ targetUserId }) => {
    const status = isConnected ? onlineUsers.get(targetUserId) : undefined;
    const isOnline = status === 'online';
    return (
      <span style={{ color: isOnline ? '#22c55e' : '#9ca3af', marginRight: 4 }}>●</span>
    );
  };

  // Get display content for a message
  const getDisplayContent = (msg, idx) => {
    if (msg.decryptError) return '🔒 解密失敗';
    return decryptedMessages.get(idx) ?? '…';
  };

  return (
    <div className="flex h-screen bg-gray-100">
      {/* Sidebar */}
      <div className="w-1/4 bg-white border-r border-gray-200 flex flex-col">
        {/* Header with profile navigation (4.13) */}
        <div className="p-4 border-b border-gray-200">
          <div className="flex justify-between items-center mb-3">
            <h2 className="text-xl font-bold">ChatWmex</h2>
            <button
              onClick={() => navigate('/profile')}
              className="text-sm text-blue-500 hover:text-blue-700 px-2 py-1 rounded border border-blue-300 hover:border-blue-500"
            >
              個人資料
            </button>
          </div>
          <form onSubmit={handleSearch} className="flex gap-2">
            <input
              type="text"
              placeholder="搜尋用戶..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="flex-1 p-2 border rounded text-sm"
            />
            <button type="submit" className="bg-blue-500 text-white p-2 rounded text-sm">
              搜尋
            </button>
          </form>
        </div>

        {/* Search results (4.9) */}
        {users.length > 0 && (
          <div className="px-4 py-2 border-b border-gray-100">
            <p className="text-xs text-gray-400 mb-1">搜尋結果</p>
            <ul>
              {users.map((user) => (
                <li key={user.id} className="flex items-center justify-between py-1">
                  <span
                    className="cursor-pointer hover:text-blue-600 text-sm"
                    onClick={() => selectChat({ id: user.id, type: 'user', name: user.username })}
                  >
                    @ {user.username}
                  </span>
                  {sentRequests.has(user.id) ? (
                    <span className="text-xs text-gray-400">已送出</span>
                  ) : (
                    <button
                      onClick={() => handleSendFriendRequest(user.id)}
                      className="text-xs bg-green-500 text-white px-2 py-0.5 rounded hover:bg-green-600"
                    >
                      加好友
                    </button>
                  )}
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* Tab bar (4.6) */}
        <div className="flex border-b border-gray-200">
          {['rooms', 'friends', 'requests'].map((tab) => (
            <button
              key={tab}
              onClick={() => handleTabChange(tab)}
              className={`flex-1 py-2 text-xs font-medium ${
                activeTab === tab
                  ? 'border-b-2 border-blue-500 text-blue-600'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              {tab === 'rooms' ? 'Rooms' : tab === 'friends' ? 'Friends' : 'Requests'}
            </button>
          ))}
        </div>

        {/* Tab content */}
        <div className="flex-1 overflow-y-auto p-3">
          {/* Rooms Tab */}
          {activeTab === 'rooms' && (
            <>
              <button
                onClick={() => {
                  getFriends().then((data) => setFriends(data || [])).catch(() => {});
                  setShowCreateGroup(true);
                }}
                className="w-full mb-3 py-1.5 text-sm bg-blue-50 text-blue-600 border border-blue-200 rounded hover:bg-blue-100"
              >
                + 建立群組
              </button>
              <ul>
                {rooms.map((room) => (
                  <li
                    key={room.id}
                    onClick={() => selectChat({ id: room.id, type: 'room', name: room.name })}
                    className={`p-2 cursor-pointer hover:bg-gray-100 rounded text-sm ${
                      selectedChat?.id === room.id ? 'bg-blue-100' : ''
                    }`}
                  >
                    # {room.name}
                  </li>
                ))}
              </ul>
            </>
          )}

          {/* Friends Tab (4.7) */}
          {activeTab === 'friends' && (
            <ul>
              {friends.length === 0 && (
                <li className="text-sm text-gray-400 text-center py-4">尚無好友</li>
              )}
              {friends.map((friend) => (
                <li key={friend.id} className="flex items-center justify-between py-2 border-b border-gray-50">
                  <span className="flex items-center text-sm">
                    <PresenceDot targetUserId={friend.id} />
                    {friend.username}
                  </span>
                  <button
                    onClick={() => handleBlockUser(friend.id)}
                    className="text-xs text-red-500 hover:text-red-700 px-2 py-0.5 border border-red-200 rounded"
                  >
                    封鎖
                  </button>
                </li>
              ))}
            </ul>
          )}

          {/* Requests Tab (4.8) */}
          {activeTab === 'requests' && (
            <ul>
              {friendRequests.length === 0 && (
                <li className="text-sm text-gray-400 text-center py-4">無待處理請求</li>
              )}
              {friendRequests.map((req) => (
                <li key={req.id} className="flex items-center justify-between py-2 border-b border-gray-50">
                  <span className="text-sm">{req.from_user?.username ?? req.username}</span>
                  <div className="flex gap-1">
                    <button
                      onClick={() => handleAcceptRequest(req.id)}
                      className="text-xs bg-green-500 text-white px-2 py-0.5 rounded hover:bg-green-600"
                    >
                      接受
                    </button>
                    <button
                      onClick={() => handleRejectRequest(req.id)}
                      className="text-xs bg-gray-300 text-gray-700 px-2 py-0.5 rounded hover:bg-gray-400"
                    >
                      拒絕
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      {/* Chat Area */}
      <div className="flex-1 flex flex-col">
        {selectedChat ? (
          <>
            {/* Chat header with presence dot (4.5) */}
            <div className="p-4 bg-white border-b border-gray-200 flex justify-between items-center">
              <h3 className="text-lg font-bold flex items-center gap-1">
                {selectedChat.type === 'user' && (
                  <PresenceDot targetUserId={selectedChat.id} />
                )}
                {selectedChat.name}
              </h3>
              <span className={`text-sm ${isConnected ? 'text-green-500' : 'text-red-500'}`}>
                {isConnected ? '已連線' : '已斷線'}
              </span>
            </div>

            {/* Messages */}
            <div className="flex-1 overflow-y-auto p-4 space-y-4">
              {messages.map((msg, idx) => {
                const isMe = msg.sender_id === userId;
                return (
                  <div key={idx} className={`flex ${isMe ? 'justify-end' : 'justify-start'}`}>
                    <div
                      className={`max-w-xs lg:max-w-md px-4 py-2 rounded-lg ${
                        isMe ? 'bg-blue-500 text-white' : 'bg-gray-200 text-gray-800'
                      }`}
                    >
                      <p>{getDisplayContent(msg, idx)}</p>
                      <span className="text-xs opacity-75 block text-right mt-1">
                        {msg.created_at &&
                          new Date(msg.created_at).toLocaleTimeString([], {
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        {isMe && msg.is_read && <span className="ml-2">✓✓</span>}
                      </span>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Message input (4.1: disabled while loading) */}
            <div className="p-4 bg-white border-t border-gray-200">
              <form onSubmit={handleSendMessage} className="flex gap-2">
                <input
                  type="text"
                  placeholder={sessionKeyLoading ? '等待金鑰...' : '輸入訊息...'}
                  value={newMessage}
                  onChange={(e) => setNewMessage(e.target.value)}
                  disabled={sessionKeyLoading || !sessionKey}
                  className="flex-1 p-2 border rounded disabled:bg-gray-100 disabled:text-gray-400"
                />
                <button
                  type="submit"
                  disabled={sessionKeyLoading || !sessionKey}
                  className="bg-blue-500 text-white px-6 py-2 rounded hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  發送
                </button>
              </form>
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-gray-500">
            選擇聊天室開始對話
          </div>
        )}
      </div>

      {/* Create Group Dialog (4.12) */}
      {showCreateGroup && (
        <div className="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl p-6 w-96 max-h-[80vh] flex flex-col">
            <h3 className="text-lg font-bold mb-4">建立群組</h3>
            <input
              type="text"
              placeholder="群組名稱"
              value={groupName}
              onChange={(e) => setGroupName(e.target.value)}
              className="p-2 border rounded mb-3"
            />
            <p className="text-sm text-gray-500 mb-2">選擇成員：</p>
            <div className="flex-1 overflow-y-auto mb-3 border rounded p-2">
              {friends.length === 0 && (
                <p className="text-sm text-gray-400 text-center py-2">尚無好友可選</p>
              )}
              {friends.map((friend) => (
                <label key={friend.id} className="flex items-center gap-2 py-1 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={selectedMembers.includes(friend.id)}
                    onChange={() => toggleMember(friend.id)}
                  />
                  <span className="text-sm">{friend.username}</span>
                </label>
              ))}
            </div>
            {createGroupError && (
              <p className="text-sm text-red-500 mb-2">{createGroupError}</p>
            )}
            <div className="flex gap-2 justify-end">
              <button
                onClick={() => {
                  setShowCreateGroup(false);
                  setGroupName('');
                  setSelectedMembers([]);
                  setCreateGroupError('');
                }}
                className="px-4 py-2 text-sm border rounded hover:bg-gray-50"
              >
                取消
              </button>
              <button
                onClick={handleCreateGroup}
                disabled={!groupName.trim()}
                className="px-4 py-2 text-sm bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
              >
                建立
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Chat;
