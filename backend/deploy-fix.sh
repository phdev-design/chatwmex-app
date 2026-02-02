#!/bin/bash

echo "🔧 修復錄音功能部署腳本"
echo "================================"

# 1. 創建本地上傳目錄
echo "📁 創建本地上傳目錄..."
mkdir -p ./uploads/audio
mkdir -p ./uploads/avatars
chmod -R 755 ./uploads

echo "✅ 本地目錄創建完成"

# 2. 停止現有容器
echo "🛑 停止現有容器..."
docker-compose down

# 3. 重新構建映像
echo "🔨 重新構建 Docker 映像..."
docker-compose build --no-cache

# 4. 啟動服務
echo "🚀 啟動服務..."
docker-compose up -d

# 5. 檢查容器狀態
echo "📊 檢查容器狀態..."
docker-compose ps

# 6. 查看日誌
echo "📋 查看啟動日誌..."
docker-compose logs --tail=20

echo ""
echo "✅ 部署完成！"
echo "🌐 服務地址: http://localhost:2025"
echo "📡 API 端點: http://localhost:2025/api/v1/"
echo ""
echo "💡 如果仍有問題，請檢查："
echo "   1. 容器日誌: docker-compose logs -f"
echo "   2. 目錄權限: ls -la ./uploads/"
echo "   3. 容器內部: docker exec -it chatwmex-backend ls -la /root/uploads/"
