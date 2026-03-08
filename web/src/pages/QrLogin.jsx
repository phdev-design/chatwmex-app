import React, { useEffect, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { useNavigate } from 'react-router-dom';
import useWebSocket from '../hooks/useWebSocket';
import axios from 'axios';

const QrLogin = () => {
    const [qrToken, setQrToken] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const navigate = useNavigate();

    const { messages } = useWebSocket(qrToken, true);

    // Initialize QR Token
    useEffect(() => {
        const fetchToken = async () => {
            try {
                const apiUrl = import.meta.env.VITE_API_URL || '';
                const res = await axios.get(`${apiUrl}/api/v1/auth/qr/generate`);
                if (res.data && res.data.data && res.data.data.qr_token) {
                    setQrToken(res.data.data.qr_token);
                } else {
                    setError('Failed to fetch QR token');
                }
            } catch (err) {
                console.error('QR Generate Error:', err);
                setError('Error connecting to server');
            } finally {
                setLoading(false);
            }
        };
        fetchToken();
    }, []);

    // Listen for login success event from WebSocket
    useEffect(() => {
        if (messages.length > 0) {
            const latestMsg = messages[messages.length - 1];
            if (latestMsg.event === 'qr_login_success' && latestMsg.data && latestMsg.data.token) {
                // Log the user in
                localStorage.setItem('token', latestMsg.data.token);
                // Navigate to home/chat
                navigate('/chat');
            }
        }
    }, [messages, navigate]);

    return (
        <div className="min-h-screen bg-gray-100 flex flex-col items-center justify-center p-4">
            <div className="bg-white p-8 rounded-2xl shadow-xl w-full max-w-sm text-center">
                <h2 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-500 to-purple-600 mb-2">
                    QR Login
                </h2>
                <p className="text-gray-500 mb-8 font-medium">Scan with your Chatwmex App to log in instantly.</p>

                <div className="flex justify-center items-center h-64 w-64 mx-auto bg-gray-50 rounded-xl border border-gray-100 overflow-hidden shadow-inner p-4">
                    {loading ? (
                        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
                    ) : error ? (
                        <p className="text-red-500">{error}</p>
                    ) : qrToken ? (
                        <QRCodeSVG value={qrToken} size={200} level="H" />
                    ) : (
                        <p className="text-gray-500">No token</p>
                    )}
                </div>

                <p className="text-sm text-gray-400 mt-8 mb-4">
                    Make sure your mobile app is updated to support QR scanning.
                </p>

                <button
                    onClick={() => navigate('/login')}
                    className="text-blue-500 hover:text-blue-700 font-medium transition-colors"
                >
                    Use Email / Password instead
                </button>
            </div>
        </div>
    );
};

export default QrLogin;
