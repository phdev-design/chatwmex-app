#!/bin/bash

# iOS App Store 上架準備腳本
# 作者: AI Assistant
# 用途: 自動化準備 iOS 應用上架到 App Store

echo "🚀 開始準備 iOS App Store 上架..."

# 設置環境變量
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# 進入項目目錄
cd "$(dirname "$0")"

echo "📁 當前目錄: $(pwd)"

# 1. 清理項目
echo "🧹 清理項目..."
flutter clean
if [ $? -ne 0 ]; then
    echo "❌ Flutter clean 失敗"
    exit 1
fi

# 2. 獲取依賴
echo "📦 獲取 Flutter 依賴..."
flutter pub get
if [ $? -ne 0 ]; then
    echo "❌ Flutter pub get 失敗"
    exit 1
fi

# 3. 檢查 iOS 依賴
echo "🍎 檢查 iOS 依賴..."
cd ios
pod install
if [ $? -ne 0 ]; then
    echo "❌ Pod install 失敗"
    exit 1
fi
cd ..

# 4. 檢查項目配置
echo "⚙️ 檢查項目配置..."

# 檢查 pubspec.yaml
if ! grep -q "version:" pubspec.yaml; then
    echo "❌ pubspec.yaml 中缺少版本號"
    exit 1
fi

# 檢查 iOS 配置
if [ ! -f "ios/Runner/Info.plist" ]; then
    echo "❌ iOS Info.plist 文件不存在"
    exit 1
fi

# 檢查 Podfile
if [ ! -f "ios/Podfile" ]; then
    echo "❌ iOS Podfile 文件不存在"
    exit 1
fi

# 5. 構建 iOS 版本
echo "🔨 構建 iOS 版本..."
flutter build ios --release
if [ $? -ne 0 ]; then
    echo "❌ iOS 構建失敗"
    exit 1
fi

# 6. 檢查構建結果
echo "✅ 檢查構建結果..."
if [ -d "build/ios/iphoneos/Runner.app" ]; then
    echo "✅ iOS 構建成功"
    echo "📱 應用大小: $(du -sh build/ios/iphoneos/Runner.app | cut -f1)"
else
    echo "❌ iOS 構建失敗，找不到 Runner.app"
    exit 1
fi

# 7. 生成構建報告
echo "📊 生成構建報告..."
cat > build_report.txt << EOF
iOS App Store 構建報告
====================

構建時間: $(date)
Flutter 版本: $(flutter --version | head -n1)
項目路徑: $(pwd)
構建狀態: 成功

應用信息:
- Bundle ID: com.phdev.Chat2MeX
- 應用名稱: Chat2MeX
- 版本: $(grep "version:" pubspec.yaml | cut -d' ' -f2)

構建輸出:
- 位置: build/ios/iphoneos/Runner.app
- 大小: $(du -sh build/ios/iphoneos/Runner.app | cut -f1)

下一步:
1. 在 Xcode 中打開 ios/Runner.xcworkspace
2. 選擇 "Any iOS Device (arm64)"
3. 選擇 Product > Archive
4. 上傳到 App Store Connect

EOF

echo "📋 構建報告已生成: build_report.txt"

# 8. 檢查 Xcode 項目
echo "🔍 檢查 Xcode 項目..."
if [ -f "ios/Runner.xcworkspace/contents.xcworkspacedata" ]; then
    echo "✅ Xcode 工作空間存在"
else
    echo "❌ Xcode 工作空間不存在"
    exit 1
fi

# 9. 最終檢查
echo "🔍 最終檢查..."

# 檢查必要的文件
required_files=(
    "ios/Runner/Info.plist"
    "ios/Runner.xcworkspace/contents.xcworkspacedata"
    "ios/Podfile"
    "ios/Podfile.lock"
    "build/ios/iphoneos/Runner.app"
)

all_files_exist=true
for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file 不存在"
        all_files_exist=false
    fi
done

if [ "$all_files_exist" = true ]; then
    echo ""
    echo "🎉 所有檢查通過！"
    echo ""
    echo "📋 下一步操作："
    echo "1. 在 Xcode 中打開 ios/Runner.xcworkspace"
    echo "2. 選擇 'Any iOS Device (arm64)'"
    echo "3. 選擇 Product > Archive"
    echo "4. 等待構建完成"
    echo "5. 在 Xcode Organizer 中上傳到 App Store Connect"
    echo ""
    echo "📊 詳細報告請查看: build_report.txt"
else
    echo "❌ 部分文件缺失，請檢查上述錯誤"
    exit 1
fi

echo "✅ 準備完成！"
