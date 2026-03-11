# RoomMediaPage 絕對修復說明

## 問題根源

從 Log 可以看到：
```
🔐 [RoomMedia] 使用對稱金鑰解密群組訊息: 69b155fdc66b0c68c485622f
⚠️ 當前對稱金鑰解密失敗: SecretBoxAuthenticationError
```

這說明：
1. `69b155fdc66b0c68c485622f` 是 MongoDB ObjectID（24 個十六進制字符）
2. 程式碼錯誤地嘗試解密這個 ID
3. 即使解密失敗，`resolveFullUrl` 也沒有正確生成完整 URL

## 修復方案

### 1. room_media_provider.dart - 三重防護

在 `_decryptMediaContent` 方法中添加三重檢查，**絕對阻止**對 MongoDB ObjectID 的解密嘗試：

#### 第一重：長度檢查
```dart
// ✅ 強制檢查：如果是短字串，絕對不解密
if (msg.content.length < 40) {
  print('ℹ️ [RoomMedia] 內容太短 (${msg.content.length} 字符)，不解密: ${msg.content}');
  result.add(msg);
  continue;
}
```

#### 第二重：Hex 字串檢查
```dart
// ✅ 檢查是否為純 Hex 字串（MongoDB ObjectID 格式）
final hexRegex = RegExp(r'^[a-f0-9]+$', caseSensitive: false);
if (hexRegex.hasMatch(msg.content)) {
  print('ℹ️ [RoomMedia] 內容是純 Hex 字串，不解密: ${msg.content}');
  result.add(msg);
  continue;
}
```

#### 第三重：Base64 格式檢查
```dart
// 檢查是否看起來像加密內容（base64 格式）
final looksEncrypted = _looksLikeEncryptedContent(msg.content);

if (!looksEncrypted) {
  print('ℹ️ [RoomMedia] 內容不像加密格式，直接保留: ${msg.content}...');
  result.add(msg);
  continue;
}
```

### 2. chat_url_utils.dart - 完整 URL 生成

修改 `resolveFullUrl` 確保生成完整的 URL：

```dart
String resolveFullUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  
  // 如果已經是完整 URL，直接返回
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  
  // 如果已經是 /uploads/ 開頭的路徑，拼接 baseUrl
  if (path.startsWith('/uploads/')) {
    final fullUrl = NetworkService.resolveUrl(path);
    print('🔗 [resolveFullUrl] /uploads/ 路徑: $path -> $fullUrl');
    return fullUrl;
  }
  
  // ✅ 強制處理：如果是 24 個十六進制字符（MongoDB ObjectID）
  if (path.length == 24 && RegExp(r'^[a-f0-9]{24}$').hasMatch(path)) {
    final fullUrl = NetworkService.resolveUrl('/uploads/images/$path');
    print('🔗 [resolveFullUrl] MongoDB ObjectID: $path -> $fullUrl');
    return fullUrl;
  }
  
  // ✅ 處理其他可能的文件 ID 格式
  if (!path.contains('/') && path.length > 0) {
    final fullUrl = NetworkService.resolveUrl('/uploads/images/$path');
    print('🔗 [resolveFullUrl] 文件 ID/名稱: $path -> $fullUrl');
    return fullUrl;
  }
  
  // 其他情況，直接拼接
  final fullUrl = NetworkService.resolveUrl(path);
  print('🔗 [resolveFullUrl] 其他格式: $path -> $fullUrl');
  return fullUrl;
}
```

## 修復後的預期 Log

### 正確的流程

```
ℹ️ [RoomMedia] 內容太短 (24 字符)，不解密: 69b155fdc66b0c68c485622f
📊 [RoomMedia] 解密完成: 10 則訊息 (原始: 10)
🔗 [resolveFullUrl] MongoDB ObjectID: 69b155fdc66b0c68c485622f -> http://localhost:8080/uploads/images/69b155fdc66b0c68c485622f
```

### 不應該再看到的 Log

❌ 不應該看到：
```
🔐 [RoomMedia] 使用對稱金鑰解密群組訊息: 69b155fdc66b0c68c485622f
⚠️ 當前對稱金鑰解密失敗: SecretBoxAuthenticationError
```

## 檢查清單

修復後，請確認以下幾點：

### 1. Log 檢查
- [ ] 看到 `ℹ️ [RoomMedia] 內容太短` 或 `ℹ️ [RoomMedia] 內容是純 Hex 字串`
- [ ] **沒有**看到 `🔐 [RoomMedia] 使用對稱金鑰解密` 針對 24 字符的 ID
- [ ] 看到 `🔗 [resolveFullUrl] MongoDB ObjectID: xxx -> http://...`

### 2. URL 檢查
打開 Flutter DevTools 的 Network 面板，確認：
- [ ] 圖片請求的 URL 是完整的（包含 `http://` 或 `https://`）
- [ ] URL 格式類似：`http://localhost:8080/uploads/images/69b155fdc66b0c68c485622f`
- [ ] **不是**相對路徑：`/uploads/images/69b155fdc66b0c68c485622f`

### 3. 圖片顯示檢查
- [ ] 媒體櫃能正確顯示圖片
- [ ] 沒有出現 broken image 圖標
- [ ] 圖片能正常點擊放大

## 如果圖片仍然無法顯示

### 檢查後端文件存儲

1. **確認文件存在**：
   ```bash
   ls -la backend/cmd/server/uploads/images/
   ```
   確認 `69b155fdc66b0c68c485622f` 文件是否存在

2. **確認後端路由**：
   檢查 `backend/cmd/server/main.go` 中的靜態文件路由：
   ```go
   r.Static("/uploads", uploadsRootDir)
   ```

3. **測試直接訪問**：
   在瀏覽器中直接訪問：
   ```
   http://localhost:8080/uploads/images/69b155fdc66b0c68c485622f
   ```
   確認能否下載文件

### 檢查文件擴展名

MongoDB ObjectID 作為文件名時，可能缺少擴展名。檢查：

1. **後端上傳邏輯**：
   ```go
   // backend/internal/delivery/http/media_handler.go
   fileName := fmt.Sprintf("%s%s", uuid.New().String(), ext)
   ```
   確認文件名是否包含擴展名

2. **如果缺少擴展名**：
   修改 `resolveFullUrl` 添加默認擴展名：
   ```dart
   if (path.length == 24 && RegExp(r'^[a-f0-9]{24}$').hasMatch(path)) {
     // 嘗試添加常見的圖片擴展名
     final fullUrl = NetworkService.resolveUrl('/uploads/images/$path.jpg');
     return fullUrl;
   }
   ```

### 檢查 NetworkService.baseUrl

確認 `NetworkService.baseUrl` 返回正確的服務器地址：

```dart
// app/lib/core/network/network_service.dart
static String get baseUrl {
  if (kDebugMode) {
    if (Platform.isAndroid) return 'http://10.0.2.2:8080';
    if (Platform.isIOS) return 'http://127.0.0.1:8080';
    return 'http://localhost:8080';
  }
  // ...
}
```

在 `resolveFullUrl` 中添加 debug 輸出：
```dart
print('🔗 [NetworkService] baseUrl: ${NetworkService.baseUrl}');
```

## 測試步驟

1. **清理並重新運行**：
   ```bash
   cd app
   flutter clean
   flutter pub get
   flutter run
   ```

2. **打開媒體櫃**：
   - 進入任何聊天室
   - 點擊右上角的 "Media, Links, and Docs"
   - 切換到 "Media" 標籤

3. **查看 Log**：
   - 確認沒有解密錯誤
   - 確認 URL 生成正確

4. **檢查圖片**：
   - 確認圖片能正常顯示
   - 點擊圖片能放大查看

## 相關文件

- `app/lib/features/chat/providers/room_media_provider.dart` - 添加三重防護
- `app/lib/features/chat/utils/chat_url_utils.dart` - 完整 URL 生成
- `app/lib/core/network/network_service.dart` - Base URL 配置
- `backend/cmd/server/main.go` - 靜態文件路由
- `backend/internal/delivery/http/media_handler.go` - 媒體上傳處理
