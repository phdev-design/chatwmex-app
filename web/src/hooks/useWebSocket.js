import { useEffect, useRef, useState, useCallback } from 'react';

const useWebSocket = (token, isQrToken = false) => {
  const ws = useRef(null);
  const [messages, setMessages] = useState([]);
  const [isConnected, setIsConnected] = useState(false);
  const messageQueue = useRef([]);
  const pendingAcks = useRef(new Map());

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

  return { messages, sendMessage, isConnected };
};

export default useWebSocket;
