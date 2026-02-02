# Chat2MeX 部署指南

## API 配置

### 生產環境配置

應用已經配置為自動使用生產環境 API：
- **生產 URL**: `https://api-chatwmex.phdev.uk`
- **WebSocket URL**: `wss://api-chatwmex.phdev.uk`

### 環境切換

應用會根據編譯模式自動切換環境：

#### 開發環境 (Debug Mode)
- Android: `http://192.168.100.110:8080`
- iOS: `http://127.0.0.1:8080`
- 其他平台: `http://localhost:8080`

#### 生產環境 (Release Mode)
- 所有平台: `https://api-chatwmex.phdev.uk`

## 部署步驟

### 1. 構建生產版本

#### Android APK
```bash
flutter build apk --release
```

#### Android App Bundle (推薦用於 Google Play)
```bash
flutter build appbundle --release
```

#### iOS
```bash
flutter build ios --release
```

### 2. 測試生產配置

在部署前，您可以測試生產環境配置：

```dart
import '../utils/api_test.dart';

// 在應用啟動時調用
ApiTest.printApiInfo();
```

### 3. 手動測試 API 連接

```dart
// 臨時切換到生產環境進行測試
ApiConfig.setOverrideUrl('https://api-chatwmex.phdev.uk');
// 測試 API 調用
// 測試完成後重置
ApiConfig.setOverrideUrl(null);
```

## 配置驗證

### 檢查當前配置
```dart
print('當前環境: ${ApiConfig.isProduction ? "生產" : "開發"}');
print('API URL: ${ApiConfig.effectiveUrl}');
print('WebSocket URL: ${ApiConfig.socketUrl}');
```

### 重要端點
- 聊天室列表: `https://api-chatwmex.phdev.uk/api/v1/rooms`
- 訊息歷史: `https://api-chatwmex.phdev.uk/api/v1/rooms/{roomId}/messages`
- 語音上傳: `https://api-chatwmex.phdev.uk/api/v1/rooms/{roomId}/voice`
- WebSocket: `wss://api-chatwmex.phdev.uk`

## 注意事項

1. **HTTPS 要求**: 生產環境使用 HTTPS，確保所有 API 調用都通過安全連接
2. **WebSocket 安全**: 生產環境使用 WSS (WebSocket Secure)
3. **證書驗證**: 確保生產服務器的 SSL 證書有效
4. **防火牆**: 確保生產服務器允許必要的端口訪問

## 故障排除

### 如果 API 連接失敗
1. 檢查網絡連接
2. 驗證 API 服務器是否運行
3. 檢查 SSL 證書是否有效
4. 查看應用日誌中的錯誤信息

### 調試模式
在開發過程中，可以強制使用生產 URL 進行測試：
```dart
ApiConfig.setOverrideUrl('https://api-chatwmex.phdev.uk');
```
