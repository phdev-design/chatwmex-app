# iOS App Store 上架檢查清單

## ✅ 已完成的修復

### 1. CocoaPods 依賴問題
- ✅ 修復了編碼問題（設置 LANG=en_US.UTF-8）
- ✅ 更新了 Podfile 平台版本設置
- ✅ 成功運行 `pod install`
- ✅ iOS 構建成功

### 2. 項目配置
- ✅ Bundle ID: com.phdev.Chat2MeX
- ✅ 應用名稱: Chat2MeX
- ✅ 版本號: 1.0.20+20
- ✅ 最低 iOS 版本: 13.0

### 3. 權限設置
- ✅ 相機權限: "This app needs camera access to take profile pictures"
- ✅ 麥克風權限: "This app needs microphone access to record voice messages"
- ✅ 相簿權限: "This app needs photo library access to select profile pictures"

## 📋 App Store 上架前檢查

### 1. 代碼簽名
- [ ] 確認開發者帳號已加入 Apple Developer Program
- [ ] 檢查 Bundle ID 是否已註冊
- [ ] 確認 Provisioning Profile 設置正確
- [ ] 檢查證書是否有效

### 2. 應用信息
- [ ] 應用名稱: Chat2MeX
- [ ] 應用描述準備完成
- [ ] 關鍵詞設置
- [ ] 應用圖標 (1024x1024)
- [ ] 截圖準備 (各種設備尺寸)

### 3. 技術要求
- [ ] 最低 iOS 版本: 13.0
- [ ] 支援的設備: iPhone, iPad
- [ ] 網路權限設置
- [ ] 後台模式設置（如果需要）

### 4. 測試
- [ ] 在真機上測試所有功能
- [ ] 測試離線模式
- [ ] 測試網路連接
- [ ] 測試語音消息功能
- [ ] 測試圖片上傳功能

## 🚀 上架步驟

### 1. 準備構建
```bash
# 清理項目
flutter clean
flutter pub get

# 構建 iOS 版本
flutter build ios --release
```

### 2. 在 Xcode 中
1. 打開 `ios/Runner.xcworkspace`
2. 選擇 "Any iOS Device (arm64)"
3. 選擇 Product > Archive
4. 等待構建完成

### 3. 上傳到 App Store Connect
1. 在 Xcode Organizer 中選擇 Archive
2. 點擊 "Distribute App"
3. 選擇 "App Store Connect"
4. 選擇 "Upload"
5. 等待上傳完成

### 4. 在 App Store Connect 中
1. 登入 App Store Connect
2. 選擇應用
3. 填寫應用信息
4. 上傳截圖和圖標
5. 提交審核

## ⚠️ 注意事項

### 1. 常見問題
- 確保所有依賴都是最新版本
- 檢查是否有未使用的權限
- 確保應用符合 App Store 審核指南

### 2. 審核要點
- 應用功能完整性
- 用戶界面友好性
- 隱私政策（如果需要）
- 應用描述準確性

### 3. 回退計劃
- 如果審核被拒，準備修復方案
- 保持代碼版本控制
- 準備多個版本號

## 📞 支援信息

如果遇到問題，請檢查：
1. Xcode 版本是否最新
2. Flutter 版本是否最新
3. CocoaPods 是否最新
4. 開發者帳號狀態

## 🎯 成功指標

- [ ] 構建無錯誤
- [ ] 上傳成功
- [ ] 審核通過
- [ ] 應用上架
