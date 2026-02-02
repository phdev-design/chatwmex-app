#!/bin/bash
echo "🔧 開始修復 iOS 構建問題..."

# 清理 Flutter
echo "1️⃣ 清理 Flutter..."
flutter clean

# 清理 iOS 依賴
echo "2️⃣ 清理 iOS 依賴..."
cd ios
rm -rf Pods
rm -rf .symlinks
rm -rf Flutter/Flutter.framework
rm -rf Flutter/Flutter.podspec
rm -f Podfile.lock

# 重新獲取依賴
echo "3️⃣ 重新獲取 Flutter 依賴..."
cd ..
flutter pub get

# 重新安裝 Pod
echo "4️⃣ 重新安裝 CocoaPods..."
cd ios
pod deintegrate
pod install --repo-update

echo "✅ 修復完成！現在可以嘗試重新構建應用。"