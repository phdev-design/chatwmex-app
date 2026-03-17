import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { getProfile, updateProfile, getLinkedDevices, removeDevice } from '../api';
import { clearSessionKey } from '../crypto/sessionKeyStore.js';

export default function Profile() {
  const navigate = useNavigate();

  const [profile, setProfile] = useState(null);
  const [username, setUsername] = useState('');
  const [saveStatus, setSaveStatus] = useState(null); // 'saved' | 'error' | null
  const [saveError, setSaveError] = useState('');

  const [devices, setDevices] = useState([]);
  const [deviceErrors, setDeviceErrors] = useState({}); // deviceId -> error message

  useEffect(() => {
    getProfile().then((data) => {
      setProfile(data);
      setUsername(data.username || '');
    });
    getLinkedDevices().then(setDevices);
  }, []);

  const handleSave = async () => {
    setSaveStatus(null);
    setSaveError('');
    try {
      await updateProfile(username, profile?.avatar_url);
      setSaveStatus('saved');
    } catch (err) {
      setSaveStatus('error');
      setSaveError(err.message || '儲存失敗');
      // preserve input — username state is kept as-is
    }
  };

  const handleRemoveDevice = async (deviceId) => {
    setDeviceErrors((prev) => ({ ...prev, [deviceId]: '' }));
    try {
      await removeDevice(deviceId);
      setDevices((prev) => prev.filter((d) => d.id !== deviceId));
    } catch (err) {
      setDeviceErrors((prev) => ({
        ...prev,
        [deviceId]: err.message || '移除失敗',
      }));
    }
  };

  const handleLogout = async () => {
    await clearSessionKey();
    localStorage.removeItem('token');
    localStorage.removeItem('user_id');
    localStorage.removeItem('device_private_key');
    navigate('/qr-login');
  };

  const formatLastActive = (isoString) => {
    if (!isoString) return '';
    const diff = Date.now() - new Date(isoString).getTime();
    const minutes = Math.floor(diff / 60000);
    if (minutes < 1) return 'now';
    if (minutes < 60) return `${minutes}m`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours}h`;
    const days = Math.floor(hours / 24);
    return `${days}d`;
  };

  return (
    <div style={{ maxWidth: 480, margin: '0 auto', padding: '16px' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: 24 }}>
        <button onClick={() => navigate(-1)} style={{ marginRight: 12 }}>←</button>
        <h2 style={{ margin: 0 }}>Profile</h2>
      </div>

      {/* Avatar + Username */}
      <div style={{ display: 'flex', alignItems: 'center', marginBottom: 16 }}>
        <div style={{
          width: 48, height: 48, borderRadius: '50%',
          background: '#ccc', display: 'flex', alignItems: 'center',
          justifyContent: 'center', marginRight: 12, fontSize: 20,
        }}>
          {profile?.avatar_url
            ? <img src={profile.avatar_url} alt="avatar" style={{ width: '100%', borderRadius: '50%' }} />
            : (profile?.username?.[0] || '?').toUpperCase()}
        </div>
        <span style={{ fontWeight: 'bold' }}>{profile?.username}</span>
      </div>

      {/* Edit Username */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <input
          value={username}
          onChange={(e) => { setUsername(e.target.value); setSaveStatus(null); }}
          placeholder="Username"
          style={{ flex: 1, padding: '6px 10px', borderRadius: 4, border: '1px solid #ccc' }}
        />
        <button onClick={handleSave} style={{ padding: '6px 14px' }}>Save</button>
      </div>
      {saveStatus === 'saved' && (
        <div style={{ color: 'green', marginBottom: 8 }}>已儲存</div>
      )}
      {saveStatus === 'error' && (
        <div style={{ color: 'red', marginBottom: 8 }}>{saveError}</div>
      )}

      {/* Linked Devices */}
      <h3 style={{ marginTop: 24, marginBottom: 8 }}>Linked Devices</h3>
      {devices.length === 0 ? (
        <div style={{ color: '#888' }}>No linked devices</div>
      ) : (
        <ul style={{ listStyle: 'none', padding: 0, margin: 0 }}>
          {devices.map((device) => (
            <li key={device.id} style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '8px 12px', border: '1px solid #eee', borderRadius: 6, marginBottom: 6,
            }}>
              <span>
                <strong>{device.name}</strong>
                {'  '}{device.type}
                {'  '}{formatLastActive(device.last_active_at)}
              </span>
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
                <button onClick={() => handleRemoveDevice(device.id)} style={{ padding: '2px 10px' }}>
                  移除
                </button>
                {deviceErrors[device.id] && (
                  <span style={{ color: 'red', fontSize: 12 }}>{deviceErrors[device.id]}</span>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}

      {/* Logout */}
      <div style={{ marginTop: 32 }}>
        <button
          onClick={handleLogout}
          style={{ padding: '8px 24px', background: '#e53e3e', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer' }}
        >
          Logout
        </button>
      </div>
    </div>
  );
}
