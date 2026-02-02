# 設備信息追蹤功能說明

## 功能概述

系統會在用戶登入時自動記錄設備信息，包括 IP 地址、設備類型、操作系統、瀏覽器、設備型號等信息。這些信息用於安全監控、用戶行為分析和設備管理。

## 自動記錄的設備信息

### 基本信息
- **IP 地址**: 用戶的真實 IP 地址（支持代理檢測）
- **User-Agent**: 瀏覽器/應用程序的完整標識
- **設備類型**: mobile, desktop, tablet
- **操作系統**: iOS, Android, Windows, macOS, Linux
- **瀏覽器**: Chrome, Safari, Firefox, Edge, Opera
- **設備型號**: iPhone 13, Samsung Galaxy S21, 等

### 額外信息（需要前端配合）
- **屏幕尺寸**: 通過 `X-Screen-Size` 標頭傳送
- **語言設置**: 通過 `Accept-Language` 標頭獲取
- **時區信息**: 通過 `X-Timezone` 標頭傳送

## API 端點

### 1. 獲取用戶設備列表
- **URL**: `GET /api/v1/devices`
- **認證**: 需要 JWT Token
- **功能**: 獲取用戶所有登入過的設備信息

**響應示例**:
```json
{
  "devices": [
    {
      "id": "64f8b1234567890abcdef123",
      "user_id": "64f8b1234567890abcdef456",
      "ip_address": "192.168.1.100",
      "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)",
      "device_type": "mobile",
      "os": "iOS",
      "browser": "Safari",
      "device_model": "iPhone (iOS 15.0)",
      "screen_size": "375x667",
      "language": "zh-TW",
      "timezone": "Asia/Taipei",
      "is_mobile": true,
      "is_tablet": false,
      "is_desktop": false,
      "login_time": "2025-01-15T10:30:00Z",
      "last_active": "2025-01-15T10:30:00Z"
    }
  ],
  "count": 1
}
```

### 2. 獲取用戶登入會話
- **URL**: `GET /api/v1/sessions`
- **認證**: 需要 JWT Token
- **功能**: 獲取用戶所有登入會話記錄

**響應示例**:
```json
{
  "sessions": [
    {
      "id": "64f8b1234567890abcdef789",
      "user_id": "64f8b1234567890abcdef456",
      "device_info": {
        "ip_address": "192.168.1.100",
        "device_type": "mobile",
        "os": "iOS",
        "browser": "Safari"
      },
      "session_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "is_active": true,
      "login_time": "2025-01-15T10:30:00Z",
      "last_active": "2025-01-15T10:30:00Z"
    }
  ],
  "count": 1
}
```

### 3. 獲取當前會話信息
- **URL**: `GET /api/v1/sessions/current`
- **認證**: 需要 JWT Token
- **功能**: 獲取當前會話的詳細信息

### 4. 終止指定會話
- **URL**: `POST /api/v1/sessions/terminate?session_id=xxx`
- **認證**: 需要 JWT Token
- **功能**: 終止指定的登入會話

## 前端集成

### 1. 傳送額外設備信息

在登入請求中添加自定義標頭：

```javascript
// 登入時傳送額外信息
const loginData = {
  email: 'user@example.com',
  password: 'password123'
};

const response = await fetch('/api/v1/user/login', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Screen-Size': `${window.screen.width}x${window.screen.height}`,
    'X-Timezone': Intl.DateTimeFormat().resolvedOptions().timeZone
  },
  body: JSON.stringify(loginData)
});
```

### 2. 獲取設備列表

```javascript
// 獲取用戶設備列表
const getDevices = async () => {
  try {
    const response = await fetch('/api/v1/devices', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      }
    });
    
    const data = await response.json();
    console.log('設備列表:', data.devices);
    return data.devices;
  } catch (error) {
    console.error('獲取設備列表失敗:', error);
  }
};
```

### 3. 管理登入會話

```javascript
// 獲取登入會話
const getSessions = async () => {
  try {
    const response = await fetch('/api/v1/sessions', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      }
    });
    
    const data = await response.json();
    console.log('登入會話:', data.sessions);
    return data.sessions;
  } catch (error) {
    console.error('獲取會話失敗:', error);
  }
};

// 終止會話
const terminateSession = async (sessionId) => {
  try {
    const response = await fetch(`/api/v1/sessions/terminate?session_id=${sessionId}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      }
    });
    
    const data = await response.json();
    console.log('會話終止結果:', data);
    return data;
  } catch (error) {
    console.error('終止會話失敗:', error);
  }
};
```

## 數據庫集合

### device_info 集合
存儲用戶的設備信息記錄：
```javascript
{
  _id: ObjectId,
  user_id: ObjectId,
  ip_address: String,
  user_agent: String,
  device_type: String,
  os: String,
  browser: String,
  device_model: String,
  screen_size: String,
  language: String,
  timezone: String,
  is_mobile: Boolean,
  is_tablet: Boolean,
  is_desktop: Boolean,
  login_time: Date,
  last_active: Date,
  created_at: Date,
  updated_at: Date
}
```

### login_sessions 集合
存儲用戶的登入會話：
```javascript
{
  _id: ObjectId,
  user_id: ObjectId,
  device_info: Object, // 嵌入的設備信息
  session_token: String,
  is_active: Boolean,
  login_time: Date,
  last_active: Date,
  logout_time: Date,
  created_at: Date,
  updated_at: Date
}
```

## 安全考慮

### 1. 隱私保護
- 設備信息僅用於安全監控和用戶體驗優化
- 不收集敏感個人信息
- 遵循數據保護法規

### 2. 數據保留
- 建議設置數據保留策略
- 定期清理過期的設備信息
- 用戶可以刪除自己的設備記錄

### 3. 異常檢測
- 監控異常登入行為
- 檢測可疑的 IP 地址
- 識別異常的設備類型組合

## 監控和分析

### 1. 用戶行為分析
- 設備使用偏好
- 登入時間模式
- 地理位置分布

### 2. 安全監控
- 異常登入檢測
- 多設備同時在線
- 可疑 IP 地址

### 3. 性能優化
- 根據設備類型優化界面
- 適配不同屏幕尺寸
- 優化移動端體驗

## 部署注意事項

1. **數據庫索引**: 為 `user_id` 和 `login_time` 創建索引
2. **數據清理**: 實施定期清理策略
3. **監控告警**: 設置異常登入告警
4. **隱私合規**: 確保符合 GDPR 等法規要求
