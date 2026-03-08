#!/bin/bash
set -e # 遇到錯誤立即停止腳本執行

# ==========================================
# Chat2MeX Backend - NAS Docker 自動建置與推送腳本
# ==========================================

# 設定目標 Registry 與 Image 名稱
REGISTRY="192.168.100.104:5100"
IMAGE_NAME="chatwmex-backend"

echo "🚀 [1/4] 檢查環境與環境變數..."

ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    echo "✅ 已載入 $ENV_FILE"
else
    echo "⚠️ 找不到 $ENV_FILE，將自動建立並生成基礎設定..."
fi

# 自動生成 JWT_SECRET (若不存在或長度不足)
if [ -z "$JWT_SECRET" ] || [ ${#JWT_SECRET} -lt 32 ]; then
    echo "🔑 正在生成新的 JWT_SECRET..."
    if command -v openssl >/dev/null 2>&1; then
        JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')
    else
        JWT_SECRET=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48)
    fi
    
    if [ -f "$ENV_FILE" ] && grep -q '^JWT_SECRET=' "$ENV_FILE"; then
        tmp_env="$(mktemp)"
        awk -v v="$JWT_SECRET" 'BEGIN{found=0} /^JWT_SECRET=/{print "JWT_SECRET="v; found=1; next} {print} END{if(!found) print "JWT_SECRET="v}' "$ENV_FILE" > "$tmp_env"
        mv "$tmp_env" "$ENV_FILE"
    else
        echo "JWT_SECRET=$JWT_SECRET" >> "$ENV_FILE"
    fi
    echo "✅ JWT_SECRET 已生成並寫入 $ENV_FILE"
fi

# ------------------------------------------
# 1. 決定版本號 (使用時間戳或環境變數)
# ------------------------------------------

echo "🔖 [2/4] 決定版本號..."

# 如果 .env 裡面有設定 APP_VERSION (例如 APP_VERSION=1.0.0)，就用它
if [ -n "$APP_VERSION" ]; then
    VERSION="$APP_VERSION"
    echo "✅ 偵測到環境變數 APP_VERSION，使用版本: $VERSION"
else
    # 預設：使用當前日期與時間當作版本號 (例如: 20260308.1200)
    VERSION="$(date +%Y%m%d.%H%M)"
    echo "ℹ️  未手動指定版本，自動使用時間戳作為版本: $VERSION"
fi

FULL_IMAGE_TAG="$REGISTRY/$IMAGE_NAME:v$VERSION"

echo "========================================"
echo "📦 版本: $VERSION"
echo "🏷️  Tag : $FULL_IMAGE_TAG"
echo "========================================"

# ------------------------------------------
# 2. 執行 Docker Build
# ------------------------------------------

echo "🔨 [3/4] 開始構建 Docker 映像 (Building image)..."

# 注意：--load 參數用於將構建好的映像載入到本地 Docker daemon
docker buildx build --platform linux/amd64 -t "$FULL_IMAGE_TAG" --load .

# ------------------------------------------
# 3. 執行 Docker Push
# ------------------------------------------

echo "⬆️  [4/4] 開始推送映像至 NAS ($REGISTRY)..."

docker push "$FULL_IMAGE_TAG"

echo "🎉==========================================🎉"
echo "   ✅ 成功! 後端映像檔已推送完畢:"
echo "      $FULL_IMAGE_TAG"
echo "🎉==========================================🎉"