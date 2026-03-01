import { useEffect, useRef, useState } from 'react';

const useWebSocket = (token) => {
  const ws = useRef(null);
  const [messages, setMessages] = useState([]);
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    if (!token) return;

    // Connect to WebSocket
    const socketUrl = `ws://localhost:8080/ws?token=${token}`;
    ws.current = new WebSocket(socketUrl);

    ws.current.onopen = () => {
      console.log('WebSocket Connected');
      setIsConnected(true);
    };

    ws.current.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data);
        console.log('Received:', message);
        setMessages((prev) => [...prev, message]);
      } catch (err) {
        console.error('Error parsing message:', err);
      }
    };

    ws.current.onclose = () => {
      console.log('WebSocket Disconnected');
      setIsConnected(false);
    };

    return () => {
      if (ws.current) {
        ws.current.close();
      }
    };
  }, [token]);

  const sendMessage = (receiverId, roomId, content, type = 'text') => {
    if (ws.current && isConnected) {
      const payload = {
        receiver_id: receiverId,
        room_id: roomId,
        content: content,
        type: type,
      };
      ws.current.send(JSON.stringify(payload));
    } else {
      console.error('WebSocket is not connected');
    }
  };

  return { messages, sendMessage, isConnected };
};

export default useWebSocket;
