# 群組聊天功能說明

## 功能概述

用戶可以創建群組並邀請其他用戶加入，支持最多 1000 人的群組聊天。群組支持不同的類型（公開、私有、僅邀請）和權限管理。

## 功能特點

### 1. 群組管理
- **創建群組**: 用戶可以創建自己的群組
- **群組類型**: 支持公開、私有、僅邀請三種類型
- **成員限制**: 支持最多 1000 人的群組
- **權限管理**: 群組創建者和管理員擁有管理權限

### 2. 成員管理
- **加入群組**: 根據群組類型決定加入方式
- **離開群組**: 成員可以主動離開群組
- **邀請機制**: 管理員可以邀請其他用戶
- **成員列表**: 查看群組成員和角色

### 3. 邀請系統
- **郵箱邀請**: 通過郵箱邀請用戶加入群組
- **邀請管理**: 查看和響應群組邀請
- **邀請過期**: 邀請有 7 天的有效期

## API 端點

### 1. 創建群組
- **URL**: `POST /api/v1/groups/create`
- **認證**: 需要 JWT Token
- **請求體**:
```json
{
  "name": "我的群組",
  "description": "這是一個測試群組",
  "group_type": "private",
  "max_members": 1000
}
```

**響應示例**:
```json
{
  "message": "群組創建成功",
  "group": {
    "id": "64f8b1234567890abcdef123",
    "name": "我的群組",
    "description": "這是一個測試群組",
    "group_type": "private",
    "max_members": 1000,
    "member_count": 1,
    "admins": ["64f8b1234567890abcdef456"],
    "created_by": "64f8b1234567890abcdef456",
    "is_active": true,
    "created_at": "2025-01-15T10:30:00Z"
  }
}
```

### 2. 獲取用戶群組列表
- **URL**: `GET /api/v1/groups`
- **認證**: 需要 JWT Token

**響應示例**:
```json
{
  "groups": [
    {
      "id": "64f8b1234567890abcdef123",
      "name": "我的群組",
      "description": "這是一個測試群組",
      "group_type": "private",
      "max_members": 1000,
      "member_count": 5,
      "admins": ["64f8b1234567890abcdef456"],
      "created_by": "64f8b1234567890abcdef456",
      "is_active": true,
      "created_at": "2025-01-15T10:30:00Z"
    }
  ],
  "count": 1
}
```

### 3. 加入群組
- **URL**: `POST /api/v1/groups/join`
- **認證**: 需要 JWT Token
- **請求體**:
```json
{
  "group_id": "64f8b1234567890abcdef123"
}
```

### 4. 離開群組
- **URL**: `POST /api/v1/groups/leave`
- **認證**: 需要 JWT Token
- **請求體**:
```json
{
  "group_id": "64f8b1234567890abcdef123"
}
```

### 5. 獲取群組成員列表
- **URL**: `GET /api/v1/groups/members?group_id=xxx`
- **認證**: 需要 JWT Token

**響應示例**:
```json
{
  "members": [
    {
      "user_id": "64f8b1234567890abcdef456",
      "username": "用戶名",
      "role": "owner",
      "joined_at": "2025-01-15T10:30:00Z",
      "is_active": true,
      "last_seen": "2025-01-15T10:30:00Z"
    }
  ],
  "count": 1
}
```

### 6. 邀請用戶加入群組
- **URL**: `POST /api/v1/groups/invite`
- **認證**: 需要 JWT Token
- **請求體**:
```json
{
  "group_id": "64f8b1234567890abcdef123",
  "invitee_email": "user@example.com",
  "message": "歡迎加入我們的群組！"
}
```

### 7. 獲取群組邀請列表
- **URL**: `GET /api/v1/groups/invitations`
- **認證**: 需要 JWT Token

**響應示例**:
```json
{
  "invitations": [
    {
      "id": "64f8b1234567890abcdef789",
      "group_id": "64f8b1234567890abcdef123",
      "group_name": "我的群組",
      "group_description": "這是一個測試群組",
      "inviter_id": "64f8b1234567890abcdef456",
      "inviter_name": "邀請者",
      "message": "歡迎加入我們的群組！",
      "expires_at": "2025-01-22T10:30:00Z",
      "created_at": "2025-01-15T10:30:00Z"
    }
  ],
  "count": 1
}
```

### 8. 響應群組邀請
- **URL**: `POST /api/v1/groups/invitations/respond`
- **認證**: 需要 JWT Token
- **請求體**:
```json
{
  "invitation_id": "64f8b1234567890abcdef789",
  "response": "accept"
}
```

## 群組類型

### 1. 公開群組 (public)
- 任何人都可以搜索和加入
- 不需要邀請
- 適合公開討論

### 2. 私有群組 (private)
- 需要知道群組 ID 才能加入
- 不需要邀請
- 適合半公開討論

### 3. 僅邀請群組 (invite_only)
- 只能通過邀請加入
- 需要管理員邀請
- 適合私密討論

## 權限管理

### 1. 群組角色
- **Owner (群組創建者)**: 擁有所有權限，不能離開群組
- **Admin (管理員)**: 可以邀請成員、管理群組
- **Member (普通成員)**: 可以發送消息、查看成員

### 2. 權限列表
- **創建群組**: 所有用戶
- **邀請成員**: 群組創建者和管理員
- **移除成員**: 群組創建者和管理員
- **修改群組信息**: 群組創建者和管理員
- **刪除群組**: 僅群組創建者

## 前端集成

### 1. 創建群組
```javascript
const createGroup = async (groupData) => {
  try {
    const response = await fetch('/api/v1/groups/create', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      },
      body: JSON.stringify({
        name: groupData.name,
        description: groupData.description,
        group_type: groupData.type,
        max_members: groupData.maxMembers || 1000
      })
    });

    const result = await response.json();
    if (response.ok) {
      console.log('群組創建成功:', result.group);
      return result.group;
    } else {
      console.error('創建失敗:', result.error);
    }
  } catch (error) {
    console.error('創建群組錯誤:', error);
  }
};
```

### 2. 獲取群組列表
```javascript
const getGroups = async () => {
  try {
    const response = await fetch('/api/v1/groups', {
      headers: {
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      }
    });

    const result = await response.json();
    if (response.ok) {
      console.log('群組列表:', result.groups);
      return result.groups;
    } else {
      console.error('獲取失敗:', result.error);
    }
  } catch (error) {
    console.error('獲取群組列表錯誤:', error);
  }
};
```

### 3. 加入群組
```javascript
const joinGroup = async (groupID) => {
  try {
    const response = await fetch('/api/v1/groups/join', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      },
      body: JSON.stringify({
        group_id: groupID
      })
    });

    const result = await response.json();
    if (response.ok) {
      console.log('成功加入群組');
      return true;
    } else {
      console.error('加入失敗:', result.error);
      return false;
    }
  } catch (error) {
    console.error('加入群組錯誤:', error);
    return false;
  }
};
```

### 4. 邀請用戶
```javascript
const inviteToGroup = async (groupID, email, message) => {
  try {
    const response = await fetch('/api/v1/groups/invite', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      },
      body: JSON.stringify({
        group_id: groupID,
        invitee_email: email,
        message: message
      })
    });

    const result = await response.json();
    if (response.ok) {
      console.log('邀請發送成功');
      return true;
    } else {
      console.error('邀請失敗:', result.error);
      return false;
    }
  } catch (error) {
    console.error('發送邀請錯誤:', error);
    return false;
  }
};
```

### 5. 響應邀請
```javascript
const respondToInvitation = async (invitationID, response) => {
  try {
    const response = await fetch('/api/v1/groups/invitations/respond', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${localStorage.getItem('token')}`
      },
      body: JSON.stringify({
        invitation_id: invitationID,
        response: response // 'accept' 或 'reject'
      })
    });

    const result = await response.json();
    if (response.ok) {
      console.log('邀請響應成功');
      return true;
    } else {
      console.error('響應失敗:', result.error);
      return false;
    }
  } catch (error) {
    console.error('響應邀請錯誤:', error);
    return false;
  }
};
```

## 數據庫集合

### chat_rooms 集合 (群組)
```javascript
{
  _id: ObjectId,
  name: String,
  description: String,
  is_group: Boolean,
  group_type: String, // public, private, invite_only
  max_members: Number, // 最大 1000
  participants: [String], // 成員 ID 列表
  admins: [String], // 管理員 ID 列表
  created_by: String,
  is_active: Boolean,
  created_at: Date,
  updated_at: Date
}
```

### group_invitations 集合
```javascript
{
  _id: ObjectId,
  group_id: ObjectId,
  inviter_id: String,
  invitee_id: String,
  invitee_email: String,
  status: String, // pending, accepted, rejected, expired
  message: String,
  expires_at: Date,
  created_at: Date,
  updated_at: Date
}
```

## 安全考慮

### 1. 權限驗證
- 只有群組管理員才能邀請成員
- 只有群組成員才能查看成員列表
- 群組創建者不能離開群組

### 2. 數據驗證
- 群組名稱不能為空
- 最大成員數不能超過 1000
- 邀請郵箱必須存在

### 3. 防止濫用
- 邀請有 7 天有效期
- 群組有最大成員數限制
- 重複邀請會被拒絕

## 性能優化

### 1. 數據庫索引
- 為 `participants` 字段創建索引
- 為 `group_type` 字段創建索引
- 為 `created_by` 字段創建索引

### 2. 查詢優化
- 使用分頁查詢群組列表
- 限制成員列表查詢數量
- 緩存群組基本信息

### 3. 實時更新
- 使用 WebSocket 推送群組更新
- 實時同步成員變更
- 即時通知邀請狀態

## 部署注意事項

1. **數據庫索引**: 為群組相關字段創建適當的索引
2. **監控**: 監控群組創建和成員增長
3. **備份**: 定期備份群組數據
4. **清理**: 實施過期邀請清理策略
