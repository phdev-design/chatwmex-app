#!/bin/bash

# ChatWMex Backend 環境配置測試腳本

echo "🧪 測試環境配置..."
echo "========================"

# 測試開發環境
echo "📝 測試開發環境配置:"
export ENVIRONMENT=development
export USE_CLOUDFLARE=false
export TEST_HOST=127.0.0.1:8080
export STORAGE_BASE_URL=""

echo "ENVIRONMENT=$ENVIRONMENT"
echo "USE_CLOUDFLARE=$USE_CLOUDFLARE"
echo "TEST_HOST=$TEST_HOST"
echo "預期存儲 URL: http://127.0.0.1:8080/uploads"
echo ""

# 測試生產環境
echo "🌐 測試生產環境配置:"
export ENVIRONMENT=production
export USE_CLOUDFLARE=true
export STORAGE_BASE_URL=https://api-chatwmex.phdev.uk/uploads

echo "ENVIRONMENT=$ENVIRONMENT"
echo "USE_CLOUDFLARE=$USE_CLOUDFLARE"
echo "STORAGE_BASE_URL=$STORAGE_BASE_URL"
echo "預期存儲 URL: https://api-chatwmex.phdev.uk/uploads"
echo ""

# 測試自動檢測
echo "🔍 測試自動環境檢測:"
unset ENVIRONMENT
export USE_CLOUDFLARE=true
echo "USE_CLOUDFLARE=true (無 ENVIRONMENT)"
echo "預期環境: production"
echo ""

unset ENVIRONMENT
unset USE_CLOUDFLARE
echo "無環境變數"
echo "預期環境: development"
echo ""

echo "✅ 環境配置測試完成"
echo ""
echo "📋 部署指令:"
echo "開發環境: docker-compose -f docker-compose.dev.yml up -d"
echo "生產環境: docker-compose -f docker-compose.prod.yml up -d"
