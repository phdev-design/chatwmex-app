# 消息偽刪除功能說明

## 功能概述

用戶可以刪除自己發送的消息，但這是偽刪除（軟刪除），消息不會真正從數據庫中移除，只是標記為已刪除狀態。其他用戶將看不到已刪除的消息，但發送者可以恢復這些消息。

## 功能特點

### 1. 偽刪除機制
- 消息不會真正從數據庫中刪除
- 只是標記 `is_deleted = true`
- 記錄刪除時間和刪除者
- 其他用戶看不到已刪除的消息

### 2. 權限控制
- 用戶只能刪除自己發送的消息
- 用戶只能恢復自己刪除的消息
- 需要有效的 JWT Token 認證

### 3. 消息恢復
- 用戶可以恢復自己刪除的消息
- 恢復後消息重新對其他用戶可見
- 清除刪除標記和相關信息

## API 端點

### 1. 刪除消息
- **URL**: `DELETE /api/v1/messages/delete`
- **認證**: 需要 JWT Token
- **請求體**:
```json
{
  "message_id": "64f8b1234567890abcdef123"
}
```

**響應示例**:
```json
{
  "message": "消息刪除成功",
  "success": true
}
```

### 2. 恢復消息
- **URL**: `POST /api/v1/messages/restore`
- **認證**: 需要 JWT Token
- **請求體**:
```json
{
  "message_id": "64f8b1234567890abcdef123"
}
```

**響應示例**:
```json
{
  "message": "消息恢復成功",
  "success": true
}
```

### 3. 獲取已刪除消息列表
- **URL**: `GET /api/v1/messages/deleted`
- **認證**: 需要 JWT Token
- **功能**: 獲取用戶自己刪除的消息列表

**響應示例**:
```json
{
  "messages": [
    {
      "id": "64f8b1234567890abcdef123",
      "sender_id": "64f8b1234567890abcdef456",
      "sender_name": "用戶名",
      "room": "room_123",
      "content": "這是一條已刪除的消息",
      "timestamp": "2025-01-15T10:30:00Z",
      "type": "text",
      "is_deleted": true,
      "deleted_at": "2025-01-15T10:35:00Z",
      "deleted_by": "64f8b1234567890abcdef456"
    }
  ],
  "count": 1
}
```

## 數據庫字段

### 新增的消息字段
```javascript
{
  is_deleted: Boolean,     // 是否已刪除
  deleted_at: Date,        // 刪除時間
  deleted_by: String       // 刪除者ID
}
```

### 查詢過濾
所有消息查詢都會自動過濾已刪除的消息：
```javascript
filter = {
  room: "room_id",
  is_deleted: { $ne: true }  // 排除已刪除的消息
}
```

## 前端集成

### 1. 刪除消息
```javascript
const deleteMessage = async (messageId) => {
  try {
    const response = await fetch('/api/v1/messages/delete', {
      method: 'DELETE',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      },
      body: JSON.stringify({
        message_id: messageId
      })
    });
    
    const result = await response.json();
    if (response.ok) {
      console.log('消息刪除成功:', result.message);
      // 從界面中移除消息或顯示"已刪除"狀態
    } else {
      console.error('刪除失敗:', result.error);
    }
  } catch (error) {
    console.error('刪除消息錯誤:', error);
  }
};
```

### 2. 恢復消息
```javascript
const restoreMessage = async (messageId) => {
  try {
    const response = await fetch('/api/v1/messages/restore', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      },
      body: JSON.stringify({
        message_id: messageId
      })
    });
    
    const result = await response.json();
    if (response.ok) {
      console.log('消息恢復成功:', result.message);
      // 重新顯示消息
    } else {
      console.error('恢復失敗:', result.error);
    }
  } catch (error) {
    console.error('恢復消息錯誤:', error);
  }
};
```

### 3. 獲取已刪除消息
```javascript
const getDeletedMessages = async () => {
  try {
    const response = await fetch('/api/v1/messages/deleted', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      }
    });
    
    const result = await response.json();
    if (response.ok) {
      console.log('已刪除消息:', result.messages);
      return result.messages;
    } else {
      console.error('獲取失敗:', result.error);
    }
  } catch (error) {
    console.error('獲取已刪除消息錯誤:', error);
  }
};
```

## 用戶界面建議

### 1. 消息操作按鈕
- 為用戶自己的消息添加"刪除"按鈕
- 已刪除的消息顯示"已刪除"狀態
- 提供"恢復"按鈕給已刪除的消息

### 2. 消息狀態顯示
```javascript
// 消息組件示例
const MessageComponent = ({ message, currentUserId }) => {
  const isOwnMessage = message.sender_id === currentUserId;
  const isDeleted = message.is_deleted;
  
  if (isDeleted) {
    return (
      <div className="message deleted">
        <span className="deleted-text">此消息已被刪除</span>
        {isOwnMessage && (
          <button onClick={() => restoreMessage(message.id)}>
            恢復消息
          </button>
        )}
      </div>
    );
  }
  
  return (
    <div className="message">
      <div className="content">{message.content}</div>
      {isOwnMessage && (
        <button onClick={() => deleteMessage(message.id)}>
          刪除
        </button>
      )}
    </div>
  );
};
```

## 錯誤處理

### 常見錯誤響應

1. **消息不存在**
```json
{
  "error": "消息不存在"
}
```

2. **權限不足**
```json
{
  "error": "只能刪除自己的消息"
}
```

3. **消息已刪除**
```json
{
  "error": "消息已經被刪除"
}
```

4. **消息未刪除**
```json
{
  "error": "消息未被刪除"
}
```

## 安全考慮

### 1. 權限驗證
- 用戶只能刪除自己的消息
- 用戶只能恢復自己刪除的消息
- 所有操作都需要有效的 JWT Token

### 2. 數據完整性
- 偽刪除不會破壞數據完整性
- 可以追蹤消息的刪除歷史
- 支持數據恢復和審計

### 3. 性能優化
- 查詢時自動過濾已刪除消息
- 避免不必要的數據傳輸
- 保持界面響應速度

## 部署注意事項

1. **數據庫索引**: 為 `is_deleted` 字段創建索引以提高查詢性能
2. **數據清理**: 考慮實施定期清理策略（如刪除超過一定時間的消息）
3. **監控**: 監控刪除操作的頻率和模式
4. **備份**: 確保數據庫備份包含已刪除的消息

## 擴展功能

### 1. 批量操作
- 支持批量刪除消息
- 支持批量恢復消息

### 2. 管理員功能
- 管理員可以查看所有已刪除的消息
- 管理員可以強制刪除消息

### 3. 審計日誌
- 記錄所有刪除和恢復操作
- 提供操作歷史查詢
