# ChatWMex Backend 環境配置說明

## 環境類型

### 1. 開發環境 (Development)
- **用途**: 本地開發和測試
- **API 地址**: `http://127.0.0.1:8080` 或 `http://192.168.100.111:8080`
- **存儲 URL**: `http://127.0.0.1:8080/uploads` 或 `http://192.168.100.111:8080/uploads`

### 2. 生產環境 (Production)
- **用途**: 正式部署
- **API 地址**: `https://api-chatwmex.phdev.uk`
- **存儲 URL**: `https://api-chatwmex.phdev.uk/uploads`

## 環境變數配置

### 基本配置
```bash
# 環境類型
ENVIRONMENT=development  # 或 production

# 服務器配置
SERVER_PORT=:8080
LOG_LEVEL=debug

# 資料庫配置
MONGO_URI=mongodb://cph0325:pp325325@143.198.17.2:27017
MONGO_DB_NAME=chatwmex_db

# 安全配置
JWT_SECRET=a_very_secret_key_that_should_be_changed
ENCRYPTION_SECRET=this-is-a-32-byte-secret-key-!!!

# 存儲配置
UPLOAD_PATH=./uploads
MAX_VOICE_FILE_SIZE=5242880
```

### 開發環境配置
```bash
# 環境設定
ENVIRONMENT=development
DOCKER_ENV=false
CONTAINER=false

# 測試主機配置
TEST_HOST=127.0.0.1:8080
# 或使用: TEST_HOST=192.168.100.111:8080

# 不使用 Cloudflare
USE_CLOUDFLARE=false
STORAGE_BASE_URL=http://127.0.0.1:8080/uploads
```

### 生產環境配置
```bash
# 環境設定
ENVIRONMENT=production
DOCKER_ENV=true
CONTAINER=true

# Cloudflare 配置
USE_CLOUDFLARE=true
STORAGE_BASE_URL=https://api-chatwmex.phdev.uk/uploads
```

## 自動環境檢測

程式會根據以下邏輯自動檢測環境：

1. 如果設定了 `ENVIRONMENT` 變數，直接使用
2. 如果 `USE_CLOUDFLARE=true`，自動設為 `production`
3. 否則設為 `development`

## 測試主機支援

開發環境支援多種測試主機：

- `127.0.0.1:8080` (預設本地測試)
- `192.168.100.111:8080` (區域網路測試)
- 可通過 `TEST_HOST` 環境變數自定義

## CORS 配置

### 開發環境
- 允許所有來源 (`*`)
- 支援 localhost 和 127.0.0.1
- 支援區域網路 IP

### 生產環境
- 只允許特定域名
- `https://chatwmex.phdev.uk`
- `https://www.chatwmex.phdev.uk`

## 部署流程

1. **GitHub** → **GitLab** → **Docker 服務器**
2. 使用 `docker-compose.prod.yml` 進行生產部署
3. 環境變數在 Docker Compose 檔案中設定
