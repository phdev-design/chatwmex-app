#!/bin/bash

echo "🔧 修復頭像上傳功能"
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

# 3. 重新構建映像
echo "🔨 重新構建 Docker 映像..."
docker-compose build --no-cache

# 4. 啟動服務
echo "🚀 啟動服務..."
docker-compose up -d

# 5. 等待服務啟動
echo "⏳ 等待服務啟動..."
sleep 10

# 6. 檢查容器狀態
echo "📊 檢查容器狀態..."
docker-compose ps

# 7. 測試健康檢查
echo "🏥 測試健康檢查..."
curl -s http://localhost:2025/api/v1/health || echo "健康檢查失敗"

# 8. 測試路由調試端點
echo "🔍 測試路由調試端點..."
curl -s http://localhost:2025/api/v1/debug/routes || echo "路由調試失敗"

# 9. 測試頭像路由
echo "🖼️ 測試頭像路由..."
curl -s http://localhost:2025/api/v1/avatar/test || echo "頭像路由測試失敗"

# 10. 測試 profile 路由
echo "👤 測試 profile 路由..."
curl -s http://localhost:2025/api/v1/profile/test || echo "Profile 路由測試失敗"

# 11. 查看日誌
echo "📋 查看啟動日誌..."
docker-compose logs --tail=20

echo ""
echo "✅ 修復完成！"
echo ""
echo "🌐 測試端點："
echo "   健康檢查: http://localhost:2025/api/v1/health"
echo "   路由調試: http://localhost:2025/api/v1/debug/routes"
echo "   頭像測試: http://localhost:2025/api/v1/avatar/test"
echo "   Profile測試: http://localhost:2025/api/v1/profile/test"
echo "   頭像上傳: http://localhost:2025/api/v1/avatar/upload (POST)"
echo "   Profile頭像: http://localhost:2025/api/v1/profile/avatar (POST/PUT)"
echo ""
echo "💡 如果仍有問題，請檢查："
echo "   1. 容器日誌: docker-compose logs -f"
echo "   2. 目錄權限: ls -la ./uploads/"
echo "   3. 容器內部: docker exec -it chatwmex-backend ls -la /root/uploads/"
