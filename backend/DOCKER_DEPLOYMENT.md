# ChatWMex Backend Docker 部署配置

## 部署環境資訊

- **服務器 IP**: 143.198.17.2
- **域名**: api-chatwmex.phdev.uk
- **端口映射**: 2025 (外部) -> 8080 (容器內部)
- **數據庫**: MongoDB @ 143.198.17.2:27017

## 環境變數配置

### 在 docker-compose.yml 中設定的環境變數：

```yaml
environment:
  # 数据库配置
  - MONGO_URI=mongodb://cph0325:pp325325@143.198.17.2:27017
  - MONGO_DB_NAME=chatwme_db
  - JWT_SECRET=a_very_secret_key_that_should_be_changed
  - ENCRYPTION_SECRET=this-is-a-32-byte-secret-key-!!!
  
  # CloudFlare 配置
  - USE_CLOUDFLARE=true
  - STORAGE_BASE_URL=https://api-chatwmex.phdev.uk/uploads
  
  # 文件上传配置
  - UPLOAD_PATH=./uploads
  - MAX_VOICE_FILE_SIZE=5242880
  
  # 服务器配置
  - SERVER_PORT=:8080
  - LOG_LEVEL=info
```

## 部署步驟

### 1. 使用部署腳本（推薦）
```bash
./deploy.sh
```

### 2. 手動部署
```bash
# 停止現有容器
docker-compose down

# 構建映像
docker-compose build --no-cache

# 啟動服務
docker-compose up -d

# 檢查狀態
docker-compose ps
```

## 服務訪問

- **生產環境**: https://api-chatwmex.phdev.uk
- **直接 IP 訪問**: http://143.198.17.2:2025
- **容器內部**: http://localhost:8080

## 重要配置說明

### 1. 端口映射
- Docker 容器內部使用端口 8080
- 外部訪問使用端口 2025
- CloudFlare 代理到 api-chatwmex.phdev.uk

### 2. 文件存儲
- 上傳文件存儲在 `./uploads` 目錄
- 通過 CloudFlare CDN 提供靜態文件服務
- 文件 URL 格式: `https://api-chatwmex.phdev.uk/uploads/...`

### 3. 數據庫連接
- MongoDB 服務器: 143.198.17.2:27017
- 數據庫名稱: chatwme_db
- 認證: cph0325 / pp325325

### 4. 安全配置
- JWT 密鑰用於用戶認證
- 32 字節加密密鑰用於消息加密
- 建議在生產環境中更換這些密鑰

## 監控和維護

### 查看日誌
```bash
docker-compose logs -f
```

### 重啟服務
```bash
docker-compose restart
```

### 更新服務
```bash
docker-compose pull
docker-compose up -d
```

### 健康檢查
容器包含健康檢查機制，每 30 秒檢查一次服務狀態。

## 故障排除

1. **端口衝突**: 確保端口 2025 沒有被其他服務占用
2. **數據庫連接**: 檢查 MongoDB 服務是否正常運行
3. **文件權限**: 確保 uploads 目錄有正確的寫入權限
4. **CloudFlare 配置**: 確保域名正確指向服務器 IP
