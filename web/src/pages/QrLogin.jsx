import React, { useEffect, useState, useCallback, useRef } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { useNavigate } from 'react-router-dom';
import useWebSocket from '../hooks/useWebSocket';
import axios from 'axios';
import { generateX25519KeyPair, decryptSessionKey } from '../crypto/webCryptoService';

const QR_TOKEN_LIFETIME = 180; // 3 minutes in seconds
const AUTO_REFRESH_THRESHOLD = 30; // Auto-refresh when <= 30 seconds remain

const QrLogin = () => {
    const [qrToken, setQrToken] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [countdown, setCountdown] = useState(QR_TOKEN_LIFETIME);
    const [expired, setExpired] = useState(false);
    const [waitingScan, setWaitingScan] = useState(false);
    const autoRefreshedRef = useRef(false);
    const keyPairRef = useRef(null);
    const navigate = useNavigate();

    const { messages } = useWebSocket(qrToken, true);

    // Fetch a new QR token from the backend
    const fetchToken = useCallback(async () => {
        setLoading(true);
        setError(null);
        setExpired(false);
        setWaitingScan(false);
        autoRefreshedRef.current = false;

        // Generate a fresh X25519 key pair for this QR session
        keyPairRef.current = generateX25519KeyPair();

        try {
            const apiUrl = import.meta.env.VITE_API_URL || '';
            const res = await axios.get(`${apiUrl}/api/v1/auth/qr/generate`, {
                params: { public_key: keyPairRef.current.publicKey },
            });
            if (res.data && res.data.data && res.data.data.qr_token) {
                setQrToken(res.data.data.qr_token);
                setCountdown(QR_TOKEN_LIFETIME);
                setWaitingScan(true);
            } else {
                setError('Failed to fetch QR token');
            }
        } catch (err) {
            console.error('QR Generate Error:', err);
            setError('Error connecting to server');
        } finally {
            setLoading(false);
        }
    }, []);

    // Initialize QR Token on mount
    useEffect(() => {
        fetchToken();
    }, [fetchToken]);

    // Countdown timer - decrement every second
    useEffect(() => {
        if (loading || error || expired) return;

        const interval = setInterval(() => {
            setCountdown((prev) => {
                if (prev <= 1) {
                    setExpired(true);
                    setWaitingScan(false);
                    return 0;
                }
                return prev - 1;
            });
        }, 1000);

        return () => clearInterval(interval);
    }, [loading, error, expired]);

    // Auto-refresh QR code when countdown reaches threshold (30 seconds)
    useEffect(() => {
        if (countdown <= AUTO_REFRESH_THRESHOLD && countdown > 0 && !autoRefreshedRef.current && !expired) {
            autoRefreshedRef.current = true;
            fetchToken();
        }
    }, [countdown, expired, fetchToken]);

    // Listen for login success event from WebSocket
    useEffect(() => {
        if (messages.length > 0) {
            const latestMsg = messages[messages.length - 1];
            if (latestMsg.event === 'qr_login_success' && latestMsg.data && latestMsg.data.token) {
                localStorage.setItem('token', latestMsg.data.token);
                // Don't navigate yet — wait for session_key_delivery
            }
        }
    }, [messages]);

    // Listen for session_key_delivery event and decrypt the session key
    useEffect(() => {
        if (messages.length === 0) return;

        const latestMsg = messages[messages.length - 1];
        if (latestMsg.event !== 'session_key_delivery') return;

        const { encrypted_key, sender_public_key } = latestMsg.data || {};
        if (!encrypted_key || !keyPairRef.current) return;

        // Use sender_public_key from the event if available, otherwise fall back
        // to the primary device's public key that would be provided in the payload
        const senderPubKey = sender_public_key;
        if (!senderPubKey) {
            console.error('session_key_delivery missing sender_public_key');
            navigate('/chat');
            return;
        }

        decryptSessionKey(encrypted_key, senderPubKey, keyPairRef.current.privateKey)
            .then((sessionKeyBase64) => {
                // Store session key for message decryption (Task 8.3 will move this to IndexedDB)
                sessionStorage.setItem('session_key', sessionKeyBase64);
                navigate('/chat');
            })
            .catch((err) => {
                console.error('Failed to decrypt session key:', err);
                // Navigate anyway — the chat page can handle missing key gracefully
                navigate('/chat');
            });
    }, [messages, navigate]);

    // Format countdown as MM:SS
    const formatTime = (seconds) => {
        const mins = Math.floor(seconds / 60);
        const secs = seconds % 60;
        return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    };

    return (
        <div className="min-h-screen bg-gray-100 flex flex-col items-center justify-center p-4">
            <div className="bg-white p-8 rounded-2xl shadow-xl w-full max-w-sm text-center">
                <h2 className="text-3xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-blue-500 to-purple-600 mb-2">
                    QR Login
                </h2>
                <p className="text-gray-500 mb-8 font-medium">使用 ChatWMEX 手機版掃描 QR Code 登入</p>

                <div className="flex flex-col justify-center items-center h-64 w-64 mx-auto bg-gray-50 rounded-xl border border-gray-100 overflow-hidden shadow-inner p-4">
                    {loading ? (
                        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500"></div>
                    ) : error ? (
                        <p className="text-red-500">{error}</p>
                    ) : expired ? (
                        <div className="flex flex-col items-center gap-3">
                            <p className="text-gray-500 font-medium">QR Code 已過期</p>
                            <button
                                onClick={fetchToken}
                                className="px-4 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 transition-colors font-medium"
                            >
                                重新產生
                            </button>
                        </div>
                    ) : qrToken ? (
                        <QRCodeSVG value={qrToken} size={200} level="H" />
                    ) : (
                        <p className="text-gray-500">No token</p>
                    )}
                </div>

                {/* Countdown timer */}
                {!loading && !error && !expired && qrToken && (
                    <p className="text-sm text-gray-400 mt-3">
                        有效時間：<span className={countdown <= 30 ? 'text-red-500 font-medium' : ''}>{formatTime(countdown)}</span>
                    </p>
                )}

                {/* Waiting for scan animation */}
                {waitingScan && !loading && !error && !expired && qrToken && (
                    <div className="flex items-center justify-center gap-2 mt-3">
                        <span className="relative flex h-3 w-3">
                            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75"></span>
                            <span className="relative inline-flex rounded-full h-3 w-3 bg-blue-500"></span>
                        </span>
                        <span className="text-sm text-gray-500">等待掃描中...</span>
                    </div>
                )}

                <p className="text-sm text-gray-400 mt-5 mb-4">
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
