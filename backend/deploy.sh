#!/bin/bash

# ChatWMex Backend Docker 部署腳本
# 服務器 IP: 143.198.17.2
# 域名: api-chatwmex.phdev.uk
# 端口映射: 2025 -> 8080
# 使用 GitLab Container Registry 映像

echo "🚀 開始部署 ChatWMex Backend..."

# 設定 GitLab 映像變數（如果未設定）
if [ -z "$CI_REGISTRY_IMAGE" ]; then
    echo "⚠️  請設定 CI_REGISTRY_IMAGE 環境變數"
    echo "例如: export CI_REGISTRY_IMAGE=registry.gitlab.com/your-group/chatwmex-app-backend"
    exit 1
fi

# 停止現有容器
echo "📦 停止現有容器..."
docker-compose -f docker-compose.prod.yml down

# 拉取最新映像
echo "📥 拉取最新映像..."
docker-compose -f docker-compose.prod.yml pull

# 啟動服務
echo "▶️  啟動服務..."
docker-compose -f docker-compose.prod.yml up -d

# 檢查服務狀態
echo "🔍 檢查服務狀態..."
docker-compose -f docker-compose.prod.yml ps

# 顯示日誌
echo "📋 顯示服務日誌..."
docker-compose -f docker-compose.prod.yml logs -f --tail=50

echo "✅ 部署完成！"
echo "🌐 服務地址: https://api-chatwmex.phdev.uk"
echo "🔗 本地測試: http://143.198.17.2:2025"
echo "📦 使用映像: $CI_REGISTRY_IMAGE:latest"
