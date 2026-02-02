#!/bin/bash

echo "🔧 修復 Docker 環境問題"
echo "================================"

# 1. 創建完整的目錄結構
echo "📁 創建上傳目錄結構..."
mkdir -p ./uploads/audio
mkdir -p ./uploads/avatars
chmod -R 755 ./uploads

echo "✅ 目錄結構創建完成"

# 2. 停止現有容器
echo "🛑 停止現有容器..."
docker-compose down

# 3. 清理舊的映像（可選）
echo "🧹 清理舊的映像..."
docker system prune -f

# 4. 重新構建映像
echo "🔨 重新構建 Docker 映像..."
docker-compose build --no-cache

# 5. 啟動服務
echo "🚀 啟動服務..."
docker-compose up -d

# 6. 等待服務啟動
echo "⏳ 等待服務啟動..."
sleep 15

# 7. 檢查容器狀態
echo "📊 檢查容器狀態..."
docker-compose ps

# 8. 檢查健康狀態
echo "🏥 檢查健康狀態..."
docker inspect --format='{{.State.Health.Status}}' chatwmex-backend 2>/dev/null || echo "健康檢查不可用"

# 9. 測試健康檢查端點
echo "🔍 測試健康檢查端點..."
curl -s http://localhost:2025/api/v1/health || echo "健康檢查端點測試失敗"

# 10. 測試路由調試端點
echo "🔍 測試路由調試端點..."
curl -s http://localhost:2025/api/v1/debug/routes || echo "路由調試失敗"

# 11. 查看日誌
echo "📋 查看啟動日誌..."
docker-compose logs --tail=30

# 12. 檢查容器內部
echo "🔍 檢查容器內部狀態..."
docker exec -it chatwmex-backend ls -la /root/uploads/ 2>/dev/null || echo "無法進入容器"

echo ""
echo "✅ 修復完成！"
echo ""
echo "🌐 測試端點："
echo "   健康檢查: http://localhost:2025/api/v1/health"
echo "   路由調試: http://localhost:2025/api/v1/debug/routes"
echo "   頭像測試: http://localhost:2025/api/v1/avatar/test"
echo "   Profile測試: http://localhost:2025/api/v1/profile/test"
echo ""
echo "💡 如果仍有問題，請檢查："
echo "   1. 容器日誌: docker-compose logs -f"
echo "   2. 健康狀態: docker inspect chatwmex-backend"
echo "   3. 容器內部: docker exec -it chatwmex-backend sh"
