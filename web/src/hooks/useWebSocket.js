import { useEffect, useRef, useState, useCallback } from 'react';
import { decryptSessionKey } from '../crypto/webCryptoService.js';
import { saveSessionKey, clearSessionKey } from '../crypto/sessionKeyStore.js';

/**
 * @typedef {Object} ReEncryptRequestData
 * @property {string} message_id
 * @property {string} encrypted_content
 * @property {string} [new_session_key]
 */

/**
 * @typedef {Object} ReEncryptResponseData
 * @property {string} message_id
 * @property {string} new_encrypted_content
 */

/**
 * @typedef {Object} PresenceUpdateData
 * @property {string} user_id
 * @property {'online'|'offline'} status
 */

/**
 * @typedef {Object} UseWebSocketOptions
 * @property {(data: Object) => void} [onSessionKeyDelivery] — 自訂 session_key_delivery 事件處理
 * @property {(data: Object) => void} [onDeviceUnlinked] — 自訂 device_unlinked 事件處理
 * @property {(data: ReEncryptRequestData) => void} [onReEncryptRequest]
 * @property {(data: ReEncryptResponseData) => void} [onReEncryptResponse]
 * @property {(data: PresenceUpdateData) => void} [onPresenceUpdate]
 */

/**
 * useWebSocket hook — 管理 WebSocket 連線與事件處理。
 *
 * 內建處理：
 *   - `session_key_delivery`：解密 Session Key 並儲存至 IndexedDB
 *   - `device_unlinked`：清除本地會話資料並導航至登入頁面
 *
 * @param {string} token — JWT token 或 QR token
 * @param {boolean} [isQrToken=false]
 * @param {UseWebSocketOptions} [options={}]
 */
const useWebSocket = (token, isQrToken = false, options = {}) => {
  const ws = useRef(null);
  const [messages, setMessages] = useState([]);
  const [isConnected, setIsConnected] = useState(false);
  const messageQueue = useRef([]);
  const pendingAcks = useRef(new Map());
  const optionsRef = useRef(options);
  optionsRef.current = options;

  const getWsUrl = () => {
    if (import.meta.env && import.meta.env.VITE_WS_URL) {
      return import.meta.env.VITE_WS_URL;
    }
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${protocol}//${window.location.host}/ws`;
  };

  const processQueue = useCallback(() => {
    if (messageQueue.current.length === 0 || !ws.current || ws.current.readyState !== WebSocket.OPEN) return;
    const queueCpy = [...messageQueue.current];
    messageQueue.current = [];
    queueCpy.forEach(msg => {
      ws.current.send(JSON.stringify(msg));
    });
  }, []);

  useEffect(() => {
    if (!token) return;

    let reconnectTimer;
    const connect = () => {
      const baseUrl = getWsUrl();
      const socketUrl = isQrToken ? `${baseUrl}?qr_token=${token}` : `${baseUrl}?token=${token}`;
      ws.current = new WebSocket(socketUrl);

      ws.current.onopen = () => {
        console.log('WebSocket Connected');
        setIsConnected(true);
        processQueue();
      };

      ws.current.onmessage = (event) => {
        try {
          // If server sends chunks separated by newline
          const lines = event.data.split('\n').map(line => line.trim()).filter(line => line.length > 0);
          for (const line of lines) {
            const message = JSON.parse(line);
            console.log('Received:', message);

            // Handle ACK
            if (message.event === 'message_ack' && message.data && message.data.client_msg_id) {
              pendingAcks.current.delete(message.data.client_msg_id);
            }

            // Handle session_key_delivery event
            if (message.event === 'session_key_delivery') {
              if (optionsRef.current.onSessionKeyDelivery) {
                optionsRef.current.onSessionKeyDelivery(message.data);
              } else {
                handleSessionKeyDelivery(message.data);
              }
            }

            // Handle device_unlinked event
            if (message.event === 'device_unlinked') {
              if (optionsRef.current.onDeviceUnlinked) {
                optionsRef.current.onDeviceUnlinked(message.data);
              } else {
                handleDeviceUnlinked();
              }
            }

            // Handle re_encrypt_request event
            if (message.event === 're_encrypt_request') {
              const { message_id, encrypted_content } = message.data || {};
              if (!message_id || !encrypted_content) {
                console.error('re_encrypt_request: missing message_id or encrypted_content');
              } else {
                optionsRef.current.onReEncryptRequest?.(message.data);
              }
            }

            // Handle re_encrypt_response event
            if (message.event === 're_encrypt_response') {
              optionsRef.current.onReEncryptResponse?.(message.data);
            }

            // Handle presence_update event
            if (message.event === 'presence_update') {
              optionsRef.current.onPresenceUpdate?.(message.data);
            }

            setMessages((prev) => [...prev, message]);
          }
        } catch (err) {
          console.error('Error parsing message:', err);
        }
      };

      ws.current.onclose = () => {
        console.log('WebSocket Disconnected. Reconnecting in 3 seconds...');
        setIsConnected(false);
        reconnectTimer = setTimeout(() => {
          connect();
        }, 3000);
      };

      ws.current.onerror = (err) => {
        console.error('WebSocket Error', err);
        ws.current.close();
      }
    };

    connect();

    return () => {
      clearTimeout(reconnectTimer);
      if (ws.current) {
        ws.current.onclose = null; // Prevent reconnect on unmount
        ws.current.close();
      }
    };
  }, [token, processQueue]);

  const sendMessage = useCallback((receiverId, roomId, content, type = 'text') => {
    const clientMsgId = crypto.randomUUID();
    const payload = {
      event: 'chat_message',
      data: {
        receiver_id: receiverId,
        room_id: roomId,
        content: content,
        type: type,
        client_msg_id: clientMsgId
      }
    };

    if (ws.current && ws.current.readyState === WebSocket.OPEN) {
      ws.current.send(JSON.stringify(payload));

      // Basic ACK tracking
      pendingAcks.current.set(clientMsgId, {
        payload,
        timestamp: Date.now()
      });

      // Clean up un-acked messages after 10s
      setTimeout(() => {
        if (pendingAcks.current.has(clientMsgId)) {
          console.warn('Message ACK timeout for', clientMsgId);
          pendingAcks.current.delete(clientMsgId);
        }
      }, 10000);

    } else {
      console.warn('WebSocket is not connected, queueing message.');
      messageQueue.current.push(payload);
    }
  }, []);

  const sendRawEvent = useCallback((event, data) => {
    const payload = { event, data };
    if (ws.current?.readyState === WebSocket.OPEN) {
      ws.current.send(JSON.stringify(payload));
    }
  }, []);

  return { messages, sendMessage, sendRawEvent, isConnected };
};

/**
 * 預設 session_key_delivery 處理：使用私鑰解密 Session Key 並儲存至 IndexedDB。
 *
 * 注意：此預設處理需要 localStorage 中存有 `device_private_key`（base64 編碼）
 * 與事件 payload 中的 `sender_public_key`。若私鑰不可用（例如 QR 登入流程中
 * 私鑰僅存於記憶體），消費者應透過 options.onSessionKeyDelivery 提供自訂處理。
 *
 * @param {Object} data — session_key_delivery 事件的 data payload
 */
async function handleSessionKeyDelivery(data) {
  const { encrypted_key, sender_public_key } = data || {};
  if (!encrypted_key || !sender_public_key) {
    console.error('session_key_delivery: missing encrypted_key or sender_public_key');
    return;
  }

  // Retrieve the device private key from localStorage (stored as base64 by the QR login flow)
  const privateKeyBase64 = localStorage.getItem('device_private_key');
  if (!privateKeyBase64) {
    console.error('session_key_delivery: device private key not found in localStorage');
    return;
  }

  try {
    // Convert base64 private key back to Uint8Array
    const binary = atob(privateKeyBase64);
    const privateKey = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      privateKey[i] = binary.charCodeAt(i);
    }

    const sessionKeyBase64 = await decryptSessionKey(encrypted_key, sender_public_key, privateKey);
    await saveSessionKey(sessionKeyBase64);
    console.log('Session key decrypted and stored successfully');
  } catch (err) {
    console.error('Failed to decrypt/store session key:', err);
  }
}

/**
 * 預設 device_unlinked 處理：清除本地會話資料（IndexedDB + localStorage）並導航至登入頁面。
 *
 * 對應 Requirements 4.5：
 *   WHEN Web_Client 收到連結撤銷通知，THE Web_Client SHALL 清除本地會話資料並導航至登入頁面
 */
async function handleDeviceUnlinked() {
  console.log('Device unlinked — clearing local session data');

  try {
    // Clear session key from IndexedDB (and sessionStorage fallback)
    await clearSessionKey();
  } catch (err) {
    console.error('Failed to clear session key from IndexedDB:', err);
  }

  // Clear authentication and device data from localStorage
  localStorage.removeItem('token');
  localStorage.removeItem('user_id');
  localStorage.removeItem('device_private_key');

  // Clear any remaining sessionStorage data
  if (typeof sessionStorage !== 'undefined') {
    sessionStorage.removeItem('session_key');
  }

  // Navigate to login page
  window.location.href = '/qr-login';
}

export default useWebSocket;
export { handleSessionKeyDelivery, handleDeviceUnlinked };
