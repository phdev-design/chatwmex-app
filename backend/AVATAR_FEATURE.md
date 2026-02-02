# 用戶頭像功能說明

## 功能概述

用戶頭像功能允許用戶上傳、更新和刪除個人頭像圖片。頭像文件會存儲在服務器上，並通過 CloudFlare CDN 提供靜態文件服務。

## API 端點

### 1. 上傳頭像
- **URL**: `POST /api/v1/avatar/upload`
- **認證**: 需要 JWT Token
- **Content-Type**: `multipart/form-data`
- **參數**: 
  - `avatar`: 圖片文件 (必需)

**請求示例**:
```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -F "avatar=@/path/to/avatar.jpg" \
  https://api-chatwmex.phdev.uk/api/v1/avatar/upload
```

**響應示例**:
```json
{
  "message": "頭像上傳成功",
  "avatar_url": "https://api-chatwmex.phdev.uk/uploads/avatars/2025/01/15/1642248000000_abc123.jpg"
}
```

### 2. 刪除頭像
- **URL**: `DELETE /api/v1/avatar/delete`
- **認證**: 需要 JWT Token

**請求示例**:
```bash
curl -X DELETE \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  https://api-chatwmex.phdev.uk/api/v1/avatar/delete
```

**響應示例**:
```json
{
  "message": "頭像刪除成功"
}
```

## 文件限制

### 支持的文件類型
- JPEG (.jpg, .jpeg)
- PNG (.png)
- GIF (.gif)
- WebP (.webp)

### 文件大小限制
- 最大文件大小: 5MB
- 建議尺寸: 200x200 到 500x500 像素

### 文件存儲結構
```
uploads/
└── avatars/
    └── 2025/
        └── 01/
            └── 15/
                └── 1642248000000_abc123.jpg
```

## 數據庫字段

用戶模型中的頭像字段：
```go
type User struct {
    // ... 其他字段
    AvatarURL *string `bson:"avatar_url,omitempty" json:"avatar_url,omitempty"`
    // ... 其他字段
}
```

## 前端集成示例

### React 上傳頭像組件
```jsx
import React, { useState } from 'react';

const AvatarUpload = () => {
  const [avatar, setAvatar] = useState(null);
  const [uploading, setUploading] = useState(false);

  const handleFileChange = (e) => {
    const file = e.target.files[0];
    if (file) {
      // 驗證文件類型
      const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
      if (!allowedTypes.includes(file.type)) {
        alert('請選擇 JPEG、PNG、GIF 或 WebP 格式的圖片');
        return;
      }

      // 驗證文件大小 (5MB)
      if (file.size > 5 * 1024 * 1024) {
        alert('文件大小不能超過 5MB');
        return;
      }

      setAvatar(file);
    }
  };

  const handleUpload = async () => {
    if (!avatar) return;

    setUploading(true);
    const formData = new FormData();
    formData.append('avatar', avatar);

    try {
      const response = await fetch('/api/v1/avatar/upload', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('token')}`
        },
        body: formData
      });

      const result = await response.json();
      if (response.ok) {
        // 更新用戶頭像 URL
        console.log('頭像上傳成功:', result.avatar_url);
      } else {
        console.error('上傳失敗:', result.error);
      }
    } catch (error) {
      console.error('上傳錯誤:', error);
    } finally {
      setUploading(false);
    }
  };

  const handleDelete = async () => {
    try {
      const response = await fetch('/api/v1/avatar/delete', {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('token')}`
        }
      });

      const result = await response.json();
      if (response.ok) {
        console.log('頭像刪除成功');
      } else {
        console.error('刪除失敗:', result.error);
      }
    } catch (error) {
      console.error('刪除錯誤:', error);
    }
  };

  return (
    <div>
      <input
        type="file"
        accept="image/*"
        onChange={handleFileChange}
      />
      {avatar && (
        <div>
          <img
            src={URL.createObjectURL(avatar)}
            alt="預覽"
            style={{ width: 100, height: 100, objectFit: 'cover' }}
          />
          <button onClick={handleUpload} disabled={uploading}>
            {uploading ? '上傳中...' : '上傳頭像'}
          </button>
        </div>
      )}
      <button onClick={handleDelete}>
        刪除頭像
      </button>
    </div>
  );
};

export default AvatarUpload;
```

## 錯誤處理

### 常見錯誤響應

1. **文件類型不支持**
```json
{
  "error": "不支持的文件類型，請上傳 JPEG、PNG、GIF 或 WebP 格式的圖片"
}
```

2. **文件大小超限**
```json
{
  "error": "文件大小不能超過 5MB"
}
```

3. **未找到上傳文件**
```json
{
  "error": "未找到上傳文件"
}
```

4. **認證失敗**
```json
{
  "error": "無法獲取用戶 ID"
}
```

## 安全考慮

1. **文件類型驗證**: 嚴格檢查 MIME 類型和文件擴展名
2. **文件大小限制**: 防止大文件攻擊
3. **用戶認證**: 所有操作都需要有效的 JWT Token
4. **文件隔離**: 每個用戶只能管理自己的頭像
5. **自動清理**: 上傳新頭像時自動刪除舊頭像

## 性能優化

1. **CDN 加速**: 通過 CloudFlare 提供靜態文件服務
2. **文件壓縮**: 建議前端在上傳前壓縮圖片
3. **緩存策略**: 設置適當的 HTTP 緩存頭
4. **存儲優化**: 使用日期目錄結構便於管理

## 部署注意事項

1. **目錄權限**: 確保 `uploads/avatars` 目錄有寫入權限
2. **磁盤空間**: 監控存儲空間使用情況
3. **備份策略**: 定期備份用戶頭像文件
4. **清理策略**: 實施定期清理未使用的頭像文件
