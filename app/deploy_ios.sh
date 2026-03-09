#!/bin/bash
set -e # 遇到錯誤立即停止腳本執行

# ==========================================
# Chat2MeX - iOS App Store Connect 自動部署腳本
# ==========================================

APP_NAME="Chat2MeX"

# ------------------------------------------
# 1. 設定區域 (已填入您的專屬 Key)
# ------------------------------------------

API_KEY_ID="B7A4L375MZ"
ISSUER_ID="c74b3e95-5b55-43c0-8437-6d5bc4c93325"

# ------------------------------------------
# 2. 檢查環境與金鑰
# ------------------------------------------

echo "🚀 [1/6] 檢查環境中..."

if ! command -v flutter &> /dev/null; then
    echo "❌ 錯誤: 找不到 flutter 指令，請確認已安裝並加入 PATH。"
    exit 1
fi

if ! command -v xcrun &> /dev/null; then
    echo "❌ 錯誤: 找不到 xcrun 指令，請確認已安裝 Xcode。"
    exit 1
fi

# 檢查 p8 金鑰是否存在
P8_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${API_KEY_ID}.p8"
if [ ! -f "$P8_KEY_PATH" ]; then
    echo "❌ 錯誤: 找不到 App Store Connect API 金鑰檔案。"
    echo "   請確認已將 AuthKey_${API_KEY_ID}.p8 放置於 $HOME/.appstoreconnect/private_keys/ 目錄下。"
    exit 1
fi

# ------------------------------------------
# 3. 自動遞增 Build Number
# ------------------------------------------

echo "🔖 [2/6] 檢查並更新版本號..."

PUBSPEC="pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
    echo "❌ 錯誤: 找不到 $PUBSPEC 檔案。"
    exit 1
fi

# 精準讀取版本號 (例如: version: 1.0.31+1)
VERSION_LINE=$(grep "^version: " "$PUBSPEC")

if [[ -z "$VERSION_LINE" ]]; then
    echo "❌ 錯誤: 在 pubspec.yaml 找不到 'version: ' 開頭的設定。"
    exit 1
fi

# 分離出基礎版本號與 Build Number
BASE_VERSION=$(echo "$VERSION_LINE" | cut -d '+' -f 1) # 例如: version: 1.0.31
CURRENT_BUILD_NUMBER=$(echo "$VERSION_LINE" | cut -d '+' -f 2 | tr -d '\r') # 移除可能的 carriage return

if [[ -z "$CURRENT_BUILD_NUMBER" || "$BASE_VERSION" == "$CURRENT_BUILD_NUMBER" ]]; then
    echo "⚠️ 警告: 無法解析 Build Number。請確認格式為 version: x.y.z+n"
    exit 1
else
    # 計算新的 Build Number
    NEW_BUILD_NUMBER=$((CURRENT_BUILD_NUMBER + 1))
    
    # 這裡修改為只替換 + 號後面的數字，避免覆蓋整行導致格式跑掉
    # macOS 的 sed 需要 -i ''
    sed -i '' -e "s/^+${CURRENT_BUILD_NUMBER}/+${NEW_BUILD_NUMBER}/" "$PUBSPEC"
    
    echo "✅ 版本號已更新: +$CURRENT_BUILD_NUMBER -> +$NEW_BUILD_NUMBER ($BASE_VERSION+$NEW_BUILD_NUMBER)"
fi

# ------------------------------------------
# 4. 清理與安裝依賴
# ------------------------------------------

echo "🧹 [3/6] 清理專案與安裝依賴..."

flutter clean
echo "📦 下載 Flutter 套件..."
flutter pub get || { echo "❌ Flutter pub get 失敗，請檢查 pubspec.yaml。"; exit 1; }

echo "📦 安裝 iOS Pods..."
cd ios
if [ ! -f "Podfile" ]; then
    echo "❌ 錯誤: ios/Podfile 不存在。"
    exit 1
fi
# 使用 --repo-update 確保拿到最新的依賴
pod install --repo-update || { echo "❌ Pod install 失敗。"; exit 1; }
cd ..

# ------------------------------------------
# 5. 建置 IPA (封存)
# ------------------------------------------

echo "🔨 [4/6] 開始建置 $APP_NAME Release IPA..."

# 執行 Flutter 官方的 IPA 建置指令前，先確保不會產生 Multiple commands produce Info.plist 錯誤 (Xcode 16 + Flutter Bug)
sed -i '' 's/GENERATE_INFOPLIST_FILE = YES;/GENERATE_INFOPLIST_FILE = NO;/g' ios/Runner.xcodeproj/project.pbxproj

# 執行 Flutter 官方的 IPA 建置指令，建議加上 obfuscate 混淆程式碼
flutter build ipa --release --obfuscate --split-debug-info=./build/app/outputs/symbols || { echo "❌ 建置 IPA 失敗，請檢查程式碼錯誤。"; exit 1; }

# 自動搜尋產生的 IPA 檔案
IPA_PATH=$(find build/ios/ipa -name "*.ipa" | head -n 1)

if [ -z "$IPA_PATH" ] || [ ! -f "$IPA_PATH" ]; then
    echo "❌ 錯誤: 建置看似完成，但在 build/ios/ipa/ 下找不到 .ipa 檔案。"
    exit 1
fi

echo "✅ 找到 IPA 檔案: $IPA_PATH"

# ------------------------------------------
# 6. 驗證與上傳至 TestFlight (含重試機制)
# ------------------------------------------

MAX_RETRIES=3
RETRY_COUNT=0

echo "☁️  [5/6] 正在驗證 IPA 檔案..."

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if xcrun altool --validate-app \
        -f "$IPA_PATH" \
        -t ios \
        --apiKey "$API_KEY_ID" \
        --apiIssuer "$ISSUER_ID" \
        --verbose; then
        echo "✅ 驗證成功！"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        echo "⚠️ 驗證失敗 (嘗試 $RETRY_COUNT/$MAX_RETRIES)。等待 5 秒後重試..."
        sleep 5
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ 錯誤: 達到最大重試次數，驗證失敗。"
    exit 1
fi

echo "🚀 [6/6] 開始上傳至 App Store Connect..."

RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if xcrun altool --upload-app \
        -f "$IPA_PATH" \
        -t ios \
        --apiKey "$API_KEY_ID" \
        --apiIssuer "$ISSUER_ID" \
        --verbose; then
        echo "✅ 上傳成功！"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        echo "⚠️ 上傳失敗 (嘗試 $RETRY_COUNT/$MAX_RETRIES)。等待 10 秒後重試..."
        sleep 10
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "❌ 錯誤: 達到最大重試次數，上傳失敗。"
    exit 1
fi

echo "🎉==========================================🎉"
echo "   $APP_NAME 部署成功！"
echo "   版本號已更新為: +$NEW_BUILD_NUMBER"
echo "   請登入 App Store Connect 查看處理進度。"
echo "   ⚠️ 請記得將 pubspec.yaml 的變更 Commit 到 Git。"
echo "🎉==========================================🎉"