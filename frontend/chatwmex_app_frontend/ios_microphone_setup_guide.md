# iOS 麥克風權限完整配置指南

## 問題描述
在 iOS 實機上無法使用麥克風錄音功能，出現權限被永久拒絕的錯誤。

## 解決方案

### 1. Xcode 項目配置

#### 1.1 Info.plist 配置
確保 `ios/Runner/Info.plist` 包含以下配置：

```xml
<!-- 麥克風權限描述 -->
<key>NSMicrophoneUsageDescription</key>
<string>此應用需要麥克風權限來錄製語音訊息，讓您能夠與朋友進行語音聊天</string>

<!-- 後台音頻模式 -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

#### 1.2 Xcode 項目設置
1. 打開 `ios/Runner.xcworkspace` 在 Xcode 中
2. 選擇 Runner 項目
3. 選擇 Runner target
4. 在 "Signing & Capabilities" 標籤中：
   - 確保 "Background Modes" 已啟用
   - 勾選 "Audio, AirPlay, and Picture in Picture"

#### 1.3 音頻會話配置
在 `ios/Runner/AppDelegate.swift` 中添加音頻會話配置：

```swift
import AVFoundation

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // 配置音頻會話
    do {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try AVAudioSession.sharedInstance().setActive(true)
    } catch {
        print("音頻會話配置失敗: \(error)")
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
```

### 2. Flutter 代碼配置

#### 2.1 權限請求邏輯
在 `lib/services/voice_recording_service.dart` 中：

```dart
Future<PermissionStatus> checkAndRequestPermissions() async {
  try {
    final micPermission = await Permission.microphone.status;
    print('VoiceRecordingService: 當前麥克風權限狀態: $micPermission');

    if (micPermission.isGranted) {
      return PermissionStatus.granted;
    }
    
    // 請求權限
    return await Permission.microphone.request();
  } catch (e) {
    print('VoiceRecordingService: 權限檢查或請求時出錯: $e');
    return PermissionStatus.denied;
  }
}
```

#### 2.2 錯誤處理
在 `lib/widgets/voice_recording_widget.dart` 中：

```dart
void _showOpenSettingsDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('需要麥克風權限'),
      content: const Text('您已永久拒絕麥克風權限。請前往應用程式設定頁面手動開啟權限，才能使用錄音功能。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            openAppSettings(); // 打開應用設置
          },
          child: const Text('前往設定'),
        ),
      ],
    ),
  );
}
```

### 3. 設備設置檢查

#### 3.1 iOS 設置檢查
1. 打開 iOS 設置
2. 前往 "隱私與安全性" > "麥克風"
3. 找到 "Chat2MeX" 應用
4. 確保權限已開啟

#### 3.2 應用設置檢查
1. 在應用中，前往個人資料頁面
2. 點擊 "測試通知" 或相關設置
3. 檢查是否有權限相關的選項

### 4. 開發環境檢查

#### 4.1 Xcode 版本
- 確保使用最新版本的 Xcode
- 檢查 iOS 部署目標是否正確

#### 4.2 證書和配置文件
- 確保開發證書有效
- 檢查 Provisioning Profile 是否包含麥克風權限

#### 4.3 設備檢查
- 確保測試設備的麥克風正常工作
- 檢查是否有其他應用佔用麥克風

### 5. 常見問題解決

#### 5.1 權限被永久拒絕
**解決方案：**
1. 刪除應用
2. 重新安裝應用
3. 在設置中手動開啟權限

#### 5.2 音頻會話衝突
**解決方案：**
1. 確保音頻會話正確配置
2. 檢查是否有其他音頻應用在運行
3. 重啟應用

#### 5.3 後台音頻問題
**解決方案：**
1. 檢查 UIBackgroundModes 配置
2. 確保音頻會話支持後台播放
3. 檢查 iOS 版本兼容性

### 6. 測試步驟

#### 6.1 權限測試
```dart
// 使用診斷工具測試
await MicrophonePermissionDiagnosis.runFullDiagnosis();
```

#### 6.2 功能測試
1. 打開應用
2. 進入聊天頁面
3. 嘗試錄製語音訊息
4. 檢查是否出現權限請求對話框

#### 6.3 設置測試
1. 拒絕權限
2. 檢查是否出現引導設置的對話框
3. 點擊 "前往設定"
4. 手動開啟權限
5. 返回應用測試

### 7. 調試技巧

#### 7.1 日誌檢查
```dart
print('VoiceRecordingService: 當前麥克風權限狀態: $micPermission');
```

#### 7.2 權限狀態檢查
```dart
final status = await Permission.microphone.status;
print('權限狀態: $status');
```

#### 7.3 音頻會話檢查
```swift
print("音頻會話類別: \(AVAudioSession.sharedInstance().category)")
print("音頻會話模式: \(AVAudioSession.sharedInstance().mode)")
```

### 8. 最終檢查清單

- [ ] Info.plist 包含 NSMicrophoneUsageDescription
- [ ] Info.plist 包含 UIBackgroundModes audio
- [ ] Xcode 項目啟用 Background Modes
- [ ] AppDelegate 配置音頻會話
- [ ] Flutter 代碼正確請求權限
- [ ] 錯誤處理包含引導設置的對話框
- [ ] 設備設置中權限已開啟
- [ ] 測試設備麥克風正常工作

### 9. 聯繫支持

如果問題持續存在，請提供以下信息：
1. iOS 版本
2. 設備型號
3. Xcode 版本
4. 錯誤日誌
5. 權限狀態截圖
