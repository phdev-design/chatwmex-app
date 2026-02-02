# GitLab CI/CD 部署指南

## 部署流程

### 1. GitLab CI/CD 自動構建
當您推送代碼到 GitLab 時，會自動觸發以下流程：

1. **構建階段** (`build_image`)
   - 使用 Docker 構建應用程式映像
   - 推送到 GitLab Container Registry
   - 標籤：`$CI_COMMIT_SHA` 和 `latest`

2. **部署階段** (`deploy_production`)
   - 手動觸發部署到生產環境
   - 使用 SSH 連接到服務器
   - 拉取最新映像並重啟服務

### 2. 手動部署
在服務器上手動部署：

```bash
# 設定 GitLab 映像變數
export CI_REGISTRY_IMAGE=registry.gitlab.com/your-group/chatwmex-app-backend

# 執行部署腳本
./deploy.sh
```

## 環境變數設定

### GitLab CI/CD 變數
在 GitLab 專案設定中需要配置以下變數：

1. **CI/CD 變數** (Settings > CI/CD > Variables)
   - `SSH_PRIVATE_KEY`: 服務器 SSH 私鑰
   - `SERVER_HOST`: 服務器 IP (143.198.17.2)
   - `SERVER_USER`: 服務器用戶名

2. **Container Registry 設定**
   - 確保專案有 Container Registry 權限
   - 映像路徑：`registry.gitlab.com/your-group/chatwmex-app-backend`

## 部署檔案說明

### 1. `.gitlab-ci.yml`
- GitLab CI/CD 配置檔案
- 定義構建和部署流程
- 自動化 Docker 映像構建和推送

### 2. `docker-compose.prod.yml`
- 生產環境 Docker Compose 配置
- 使用 GitLab Container Registry 映像
- 包含所有必要的環境變數

### 3. `deploy.sh`
- 手動部署腳本
- 支援使用 GitLab 映像部署
- 包含健康檢查和日誌查看

## 部署步驟

### 自動部署（推薦）
1. 推送代碼到 GitLab
2. 等待 CI/CD 構建完成
3. 在 GitLab 中手動觸發部署階段

### 手動部署
1. 在服務器上設定環境變數
2. 執行部署腳本
3. 檢查服務狀態

## 映像管理

### 映像標籤
- `latest`: 最新版本
- `$CI_COMMIT_SHA`: 特定提交版本
- 可以回滾到任何歷史版本

### 清理舊映像
```bash
# 清理未使用的映像
docker system prune -f

# 清理特定映像的舊版本
docker image prune -a
```

## 監控和維護

### 查看部署狀態
```bash
# 查看容器狀態
docker-compose -f docker-compose.prod.yml ps

# 查看日誌
docker-compose -f docker-compose.prod.yml logs -f

# 查看映像資訊
docker images | grep chatwmex
```

### 回滾部署
```bash
# 使用特定版本的映像
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.prod.yml up -d --image registry.gitlab.com/your-group/chatwmex-app-backend:COMMIT_SHA
```

## 故障排除

### 常見問題
1. **映像拉取失敗**: 檢查 GitLab 權限和網路連接
2. **部署失敗**: 檢查 SSH 連接和服務器配置
3. **服務無法啟動**: 檢查環境變數和端口配置

### 日誌查看
```bash
# 查看 GitLab CI/CD 日誌
# 在 GitLab 專案中：CI/CD > Pipelines

# 查看服務器日誌
docker-compose -f docker-compose.prod.yml logs -f
```
