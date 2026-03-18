#!/bin/bash
set -e # 遇到錯誤立即停止腳本執行

# ==========================================
# Chat2MeX Frontend - NAS Docker 自動建置與推送腳本
# ==========================================

# 設定目標 Registry 與 Image 名稱
REGISTRY="192.168.100.104:5100"
IMAGE_NAME="chatwmex-frontend"

echo "🚀 [1/4] 檢查環境..."

# ------------------------------------------
# 讀取環境變數 (選用，前端通常透過 Build Args 注入)
# ------------------------------------------
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    echo "✅ 已載入 $ENV_FILE"
else
    echo "ℹ️  未找到 $ENV_FILE，略過載入（使用預設值或 Build Args）"
fi

# ------------------------------------------
# 決定版本號
# ------------------------------------------
echo "🔖 [2/4] 決定版本號..."

if [ -n "$APP_VERSION" ]; then
    VERSION="$APP_VERSION"
    echo "✅ 偵測到環境變數 APP_VERSION，使用版本: $VERSION"
else
    VERSION="$(date +%Y%m%d.%H%M)"
    echo "ℹ️  未手動指定版本，自動使用時間戳作為版本: $VERSION"
fi

FULL_IMAGE_TAG="$REGISTRY/$IMAGE_NAME:v$VERSION"
LATEST_TAG="$REGISTRY/$IMAGE_NAME:latest"

echo "========================================"
echo "📦 版本  : $VERSION"
echo "🏷️  Tag   : $FULL_IMAGE_TAG"
echo "🏷️  Latest: $LATEST_TAG"
echo "========================================"

# ------------------------------------------
# 執行 Docker Build
# 若前端需要在 Build 時注入 API URL，可透過 --build-arg 傳入
# 例如：VITE_API_URL 需要寫在 vite.config.js 的 define 或直接用 import.meta.env
# ------------------------------------------
echo "🔨 [3/4] 開始構建 Docker 映像..."

VITE_API_URL="${VITE_API_URL:-}"

if [ -n "$VITE_API_URL" ]; then
    echo "🌐 注入 VITE_API_URL=$VITE_API_URL"
    docker buildx build \
        --platform linux/amd64 \
        --build-arg VITE_API_URL="$VITE_API_URL" \
        -t "$FULL_IMAGE_TAG" \
        -t "$LATEST_TAG" \
        --load \
        .
else
    docker buildx build \
        --platform linux/amd64 \
        -t "$FULL_IMAGE_TAG" \
        -t "$LATEST_TAG" \
        --load \
        .
fi

# ------------------------------------------
# 推送至 NAS Registry
# ------------------------------------------
echo "⬆️  [4/4] 開始推送映像至 NAS ($REGISTRY)..."

docker push "$FULL_IMAGE_TAG"
docker push "$LATEST_TAG"

echo "🎉==========================================🎉"
echo "   ✅ 成功! 前端映像檔已推送完畢:"
echo "      $FULL_IMAGE_TAG"
echo "      $LATEST_TAG"
echo "🎉==========================================🎉"