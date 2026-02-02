# ChatWMex Backend 部署指南

## 🚀 部署流程

### 1. GitHub → GitLab → Docker 服務器

```bash
# 1. 推送到 GitHub
git add .
git commit -m "改進環境配置系統"
git push origin main

# 2. GitLab CI/CD 會自動構建映像
# 3. 在 Docker 服務器上部署
```

### 2. 服務器部署指令

在 `root@docker-ubuntu-s-1vcpu-2gb-nyc3-01:~/chatwmex#` 執行：

```bash
# 停止現有服務
docker-compose -f docker-compose.prod.yml down

# 拉取最新映像
docker-compose -f docker-compose.prod.yml pull

# 啟動生產環境
docker-compose -f docker-compose.prod.yml up -d

# 檢查狀態
docker-compose -f docker-compose.prod.yml ps

# 查看日誌
docker-compose -f docker-compose.prod.yml logs -f
```

## 🌐 環境配置

### 生產環境 (Production)
- **API 地址**: `https://api-chatwmex.phdev.uk`
- **存儲 URL**: `https://api-chatwmex.phdev.uk/uploads`
- **端口映射**: 2025 → 8080
- **環境變數**: `ENVIRONMENT=production`

### 開發環境 (Development)
- **API 地址**: `http://127.0.0.1:8080` 或 `http://192.168.100.111:8080`
- **存儲 URL**: `http://127.0.0.1:8080/uploads` 或 `http://192.168.100.111:8080/uploads`
- **端口映射**: 8080 → 8080
- **環境變數**: `ENVIRONMENT=development`

## 🔧 環境變數說明

### 核心環境變數
- `ENVIRONMENT`: 環境類型 (production/development)
- `USE_CLOUDFLARE`: 是否使用 Cloudflare (true/false)
- `STORAGE_BASE_URL`: 存儲基礎 URL
- `TEST_HOST`: 測試主機 (開發環境用)

### 自動檢測邏輯
1. 如果設定 `ENVIRONMENT`，直接使用
2. 如果 `USE_CLOUDFLARE=true`，自動設為 `production`
3. 否則設為 `development`

## 📁 檔案結構

```
chatwmex-app-backend/
├── config/
│   └── config.go              # 環境配置邏輯
├── docker-compose.prod.yml    # 生產環境配置
├── docker-compose.dev.yml     # 開發環境配置
├── ENVIRONMENT_CONFIG.md      # 環境配置說明
├── DEPLOYMENT_GUIDE.md        # 部署指南
└── test-env.sh               # 環境測試腳本
```

## 🧪 測試環境配置

```bash
# 執行環境測試
./test-env.sh

# 測試開發環境
docker-compose -f docker-compose.dev.yml up -d

# 測試生產環境
docker-compose -f docker-compose.prod.yml up -d
```

## 🔍 故障排除

### 檢查環境配置
```bash
# 查看容器環境變數
docker exec -it chatwmex-backend env | grep -E "(ENVIRONMENT|USE_CLOUDFLARE|STORAGE_BASE_URL)"

# 查看應用程式日誌
docker-compose -f docker-compose.prod.yml logs chatwmex-backend
```

### 常見問題
1. **存儲 URL 錯誤**: 檢查 `STORAGE_BASE_URL` 設定
2. **CORS 問題**: 檢查 `AllowedOrigins` 配置
3. **環境檢測失敗**: 確認 `ENVIRONMENT` 或 `USE_CLOUDFLARE` 設定

## 📞 支援

如有問題，請檢查：
1. 環境變數設定
2. Docker 容器日誌
3. 網路連接狀態
4. 檔案權限設定
