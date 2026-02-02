#!/bin/bash

# 創建上傳目錄結構腳本
echo "🔧 設置上傳目錄結構..."

# 創建必要的目錄
mkdir -p ./uploads/audio
mkdir -p ./uploads/avatars

# 設置權限
chmod -R 755 ./uploads
chmod -R 777 ./uploads/audio
chmod -R 777 ./uploads/avatars

echo "✅ 目錄結構創建完成："
echo "   📁 ./uploads/"
echo "   📁 ./uploads/audio/"
echo "   📁 ./uploads/avatars/"
echo ""
echo "權限設置："
ls -la ./uploads/
