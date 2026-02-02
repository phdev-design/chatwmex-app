# 帳號刪除功能說明

## 功能概述

用戶可以刪除自己的帳號，這是一個不可逆的操作。系統會安全地處理所有相關數據，包括消息匿名化、設備信息刪除、會話終止等。

## 功能特點

### 1. 安全刪除機制
- 需要密碼確認
- 需要輸入確認文本 "DELETE_MY_ACCOUNT"
- 記錄刪除原因和時間
- 不可逆操作

### 2. 數據處理策略
- **消息**: 匿名化為 "已刪除用戶"，內容替換為 "[此用戶已刪除帳號]"
- **設備信息**: 完全刪除
- **登入會話**: 完全刪除
- **聊天室**: 從所有聊天室中移除
- **頭像文件**: 清理相關文件

### 3. 權限控制
- 用戶只能刪除自己的帳號
- 需要有效的 JWT Token 認證
- 需要密碼驗證

## API 端點

### 1. 刪除帳號
- **URL**: `DELETE /api/v1/account/delete`
- **認證**: 需要 JWT Token
- **請求體**:
```json
{
  "password": "用戶密碼",
  "deletion_reason": "不再使用此服務",
  "confirm_text": "DELETE_MY_ACCOUNT"
}
```

**響應示例**:
```json
{
  "message": "帳號刪除成功",
  "success": true
}
```

### 2. 獲取帳號刪除信息
- **URL**: `GET /api/v1/account/deletion-info`
- **認證**: 需要 JWT Token
- **功能**: 獲取帳號相關數據統計信息

**響應示例**:
```json
{
  "account_info": {
    "user_id": "64f8b1234567890abcdef456",
    "username": "用戶名",
    "email": "user@example.com",
    "created_at": "2025-01-15T10:30:00Z",
    "is_active": true,
    "is_online": false,
    "message_count": 150,
    "device_count": 3,
    "session_count": 5,
    "warning": "刪除帳號將無法恢復，所有相關數據將被永久刪除或匿名化"
  }
}
```

### 3. 取消帳號刪除
- **URL**: `POST /api/v1/account/cancel-deletion`
- **認證**: 需要 JWT Token
- **功能**: 如果帳號還未完全刪除，可以取消刪除

**響應示例**:
```json
{
  "message": "帳號恢復成功",
  "success": true
}
```

## 數據庫字段

### 新增的用戶字段
```javascript
{
  is_active: Boolean,        // 帳號是否活躍
  is_deleted: Boolean,       // 帳號是否已刪除
  deleted_at: Date,          // 刪除時間
  deletion_reason: String    // 刪除原因
}
```

## 前端集成

### 1. 刪除帳號確認頁面
```javascript
const AccountDeletionPage = () => {
  const [password, setPassword] = useState('');
  const [reason, setReason] = useState('');
  const [confirmText, setConfirmText] = useState('');
  const [accountInfo, setAccountInfo] = useState(null);

  useEffect(() => {
    // 獲取帳號信息
    fetchAccountInfo();
  }, []);

  const fetchAccountInfo = async () => {
    try {
      const response = await fetch('/api/v1/account/deletion-info', {
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('token')}`
        }
      });
      
      const data = await response.json();
      setAccountInfo(data.account_info);
    } catch (error) {
      console.error('獲取帳號信息失敗:', error);
    }
  };

  const handleDeleteAccount = async () => {
    if (confirmText !== 'DELETE_MY_ACCOUNT') {
      alert('請輸入正確的確認文本');
      return;
    }

    if (!password) {
      alert('請輸入密碼');
      return;
    }

    const confirmed = window.confirm(
      '此操作不可逆！確定要刪除您的帳號嗎？\n' +
      '所有相關數據將被永久刪除或匿名化。'
    );

    if (!confirmed) return;

    try {
      const response = await fetch('/api/v1/account/delete', {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('token')}`
        },
        body: JSON.stringify({
          password: password,
          deletion_reason: reason,
          confirm_text: confirmText
        })
      });

      const result = await response.json();
      if (response.ok) {
        alert('帳號刪除成功');
        // 重定向到登入頁面
        window.location.href = '/login';
      } else {
        alert('刪除失敗: ' + result.error);
      }
    } catch (error) {
      console.error('刪除帳號錯誤:', error);
    }
  };

  return (
    <div className="account-deletion-page">
      <h2>刪除帳號</h2>
      
      {accountInfo && (
        <div className="account-info">
          <h3>帳號信息</h3>
          <p>用戶名: {accountInfo.username}</p>
          <p>郵箱: {accountInfo.email}</p>
          <p>註冊時間: {new Date(accountInfo.created_at).toLocaleString()}</p>
          <p>消息數量: {accountInfo.message_count}</p>
          <p>設備數量: {accountInfo.device_count}</p>
          <p>會話數量: {accountInfo.session_count}</p>
        </div>
      )}

      <div className="warning">
        <h3>⚠️ 重要警告</h3>
        <p>{accountInfo?.warning}</p>
        <ul>
          <li>所有消息將被匿名化</li>
          <li>設備信息將被永久刪除</li>
          <li>登入會話將被終止</li>
          <li>您將從所有聊天室中移除</li>
          <li>此操作無法撤銷</li>
        </ul>
      </div>

      <form onSubmit={(e) => { e.preventDefault(); handleDeleteAccount(); }}>
        <div>
          <label>密碼確認:</label>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </div>

        <div>
          <label>刪除原因 (可選):</label>
          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="請告訴我們您刪除帳號的原因..."
          />
        </div>

        <div>
          <label>確認文本:</label>
          <input
            type="text"
            value={confirmText}
            onChange={(e) => setConfirmText(e.target.value)}
            placeholder="請輸入: DELETE_MY_ACCOUNT"
            required
          />
        </div>

        <button type="submit" className="danger-button">
          永久刪除帳號
        </button>
      </form>
    </div>
  );
};
```

### 2. 帳號狀態檢查
```javascript
const checkAccountStatus = async () => {
  try {
    const response = await fetch('/api/v1/user/profile', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      }
    });

    if (response.status === 410) {
      // 帳號已被刪除
      alert('您的帳號已被刪除');
      window.location.href = '/login';
      return;
    }

    const user = await response.json();
    if (user.user && user.user.is_deleted) {
      alert('您的帳號已被刪除');
      window.location.href = '/login';
    }
  } catch (error) {
    console.error('檢查帳號狀態失敗:', error);
  }
};
```

## 安全考慮

### 1. 身份驗證
- 需要有效的 JWT Token
- 需要密碼確認
- 需要確認文本驗證

### 2. 數據保護
- 敏感數據完全刪除
- 消息匿名化保護隱私
- 記錄刪除操作日誌

### 3. 操作確認
- 多重確認機制
- 明確的警告信息
- 不可逆操作提醒

## 錯誤處理

### 常見錯誤響應

1. **密碼不正確**
```json
{
  "error": "密碼不正確"
}
```

2. **確認文本不正確**
```json
{
  "error": "確認文本不正確，請輸入 'DELETE_MY_ACCOUNT'"
}
```

3. **帳號已被刪除**
```json
{
  "error": "帳號已經被刪除"
}
```

4. **帳號未被刪除**
```json
{
  "error": "帳號未被刪除"
}
```

## 數據清理策略

### 1. 立即清理
- 用戶設備信息
- 登入會話記錄
- 聊天室成員關係

### 2. 匿名化處理
- 用戶消息內容
- 發送者名稱
- 保持消息結構完整性

### 3. 文件清理
- 用戶頭像文件
- 相關上傳文件
- 臨時文件

## 合規性考慮

### 1. GDPR 合規
- 用戶有權刪除個人數據
- 提供完整的數據刪除
- 記錄刪除操作

### 2. 數據保留
- 法律要求的數據保留
- 審計日誌保留
- 系統日誌保留

### 3. 通知機制
- 刪除前的最後確認
- 刪除後的確認通知
- 相關服務的影響說明

## 監控和日誌

### 1. 操作日誌
- 記錄所有刪除操作
- 記錄刪除原因
- 記錄操作時間

### 2. 安全監控
- 異常刪除操作檢測
- 批量刪除檢測
- 可疑操作告警

### 3. 數據統計
- 刪除操作統計
- 用戶流失分析
- 刪除原因分析

## 部署注意事項

1. **數據庫索引**: 為 `is_deleted` 字段創建索引
2. **備份策略**: 確保重要數據有備份
3. **監控告警**: 設置異常刪除告警
4. **法律合規**: 確保符合當地法律法規
