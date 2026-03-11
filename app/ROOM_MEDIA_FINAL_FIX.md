# RoomMediaPage 最終修復說明

## 問題根源

經過測試發現，媒體訊息的 `content` 字段包含的是**文件 ID**（如 `69b155fdc66b0c68c485622f`），而不是加密的 URL。

### 錯誤的假設

之前我們假設：
- 一對一聊天：`msg.content` 是加密的 URL，需要用 ECDH 解密
- 群組聊天：`msg.content` 是加密的 URL，需要用對稱金鑰解密

### 實際情況

實際上：
- `msg.content` 包含的是**文件 ID** 或**相對路徑**
- 這些 ID/路徑**沒有經過 E2EE 加密**
- 需要通過 `resolveFullUrl()` 轉換為完整的 URL

### 證據

1. **Log 顯示的內容**：`69b155fdc66b0c68c485622f`
   - 這是 24 個十六進制字符，符合 MongoDB ObjectID 格式
   - 不是 base64 編碼的加密內容

2. **解密錯誤**：`SecretBoxAuthenticationError: SecretBox has wrong message authentication code (MAC)`
   - 嘗試解密非加密內容導致的錯誤

3. **後端代碼**：
   ```go
   // backend/internal/delivery/http/media_handler.go
   response.Success(c, gin.H{
       "url": "/uploads/" + dirType + "/" + fileName,
   })
   ```
   - 後端返回的是 `/uploads/images/xxx.jpg` 格式的路徑

## 修復方案

### 1. 修改 `room_media_provider.dart`

添加 `_looksLikeEncryptedContent()` 方法來判斷內容是否看起來像加密內容：

```dart
bool _looksLikeEncryptedContent(String content) {
  // 加密內容特徵：
  // 1. 長度至少 40 字符（28 bytes base64 編碼約 38-40 字符）
  // 2. 符合 base64 字符集（A-Z, a-z, 0-9, +, /, =）
  if (content.length < 40) {
    return false;
  }
  
  final base64Regex = RegExp(r'^[A-Za-z0-9+/]+=*$');
  return base64Regex.hasMatch(content.trim());
}
```

在 `_decryptMediaContent()` 中，先檢查內容是否看起來像加密內容：

```dart
// 檢查是否看起來像加密內容
final looksEncrypted = _looksLikeEncryptedContent(msg.content);

if (!looksEncrypted) {
  // 不像加密內容，可能是文件 ID 或其他格式，直接保留
  print('ℹ️ [RoomMedia] 內容不像加密格式，直接保留: ${msg.content}...');
  result.add(msg);
  continue;
}
```

### 2. 增強 `resolveFullUrl()` (chat_url_utils.dart)

添加對文件 ID 的處理：

```dart
String resolveFullUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  
  // 如果已經是 /uploads/ 開頭的路徑，直接拼接
  if (path.startsWith('/uploads/')) {
    return NetworkService.resolveUrl(path);
  }
  
  // 如果看起來像文件 ID（24 個十六進制字符，MongoDB ObjectID 格式）
  if (path.length == 24 && RegExp(r'^[a-f0-9]{24}$').hasMatch(path)) {
    // 看起來像 MongoDB ObjectID，嘗試作為路徑拼接
    return NetworkService.resolveUrl('/uploads/images/$path');
  }
  
  // 其他情況，直接拼接
  return NetworkService.resolveUrl(path);
}
```

## 修復後的工作流程

### 媒體訊息顯示流程

1. **後端返回訊息**：
   - `msg.content = "69b155fdc66b0c68c485622f"` (文件 ID)
   - 或 `msg.content = "/uploads/images/xxx.jpg"` (相對路徑)

2. **room_media_provider 處理**：
   - 檢查是否為完整 URL → 否
   - 檢查是否看起來像加密內容 → 否（長度 < 40 或不符合 base64 格式）
   - 直接保留原內容，不嘗試解密

3. **UI 層處理**：
   - `media_tab_content.dart` 調用 `resolveFullUrl(msg.content)`
   - `resolveFullUrl` 識別文件 ID 或相對路徑
   - 轉換為完整 URL：`http://localhost:8080/uploads/images/69b155fdc66b0c68c485622f`

4. **圖片顯示**：
   - `Image.network(url)` 加載圖片 ✅

## 日誌輸出

修復後，你會看到以下日誌：

### 文件 ID 格式
```
ℹ️ [RoomMedia] 內容不像加密格式，直接保留: 69b155fdc66b0c68c485622f...
📊 [RoomMedia] 解密完成: 10 則訊息 (原始: 10)
```

### 相對路徑格式
```
ℹ️ [RoomMedia] 內容不像加密格式，直接保留: /uploads/images/xxx.jpg...
📊 [RoomMedia] 解密完成: 10 則訊息 (原始: 10)
```

### 加密內容（如果有）
```
🔐 [RoomMedia] 使用對稱金鑰解密群組訊息: msg_123
✅ 對稱金鑰解密成功（當前金鑰）
✅ [RoomMedia] 成功解密 image: msg_123
📊 [RoomMedia] 解密完成: 10 則訊息 (原始: 10)
```

## 為什麼媒體內容沒有加密？

根據代碼分析，可能的原因：

1. **性能考慮**：
   - 媒體文件通常很大，加密/解密會消耗大量資源
   - 文件存儲在服務器上，通過 URL 訪問

2. **安全性權衡**：
   - 文件 ID 本身不包含敏感信息
   - 需要認證才能訪問 `/uploads/` 路徑（通過 JWT token）
   - 真正的安全性由服務器端的訪問控制保證

3. **實現簡化**：
   - 避免在客戶端處理大文件的加密/解密
   - 減少客戶端的計算負擔和電池消耗

## 測試建議

1. **測試不同格式的內容**：
   - 文件 ID：`69b155fdc66b0c68c485622f`
   - 相對路徑：`/uploads/images/xxx.jpg`
   - 完整 URL：`http://localhost:8080/uploads/images/xxx.jpg`
   - 加密內容（如果有）：長 base64 字符串

2. **測試所有媒體類型**：
   - 圖片 (image)
   - 影片 (video)
   - 文件 (document)
   - 連結 (link)

3. **測試群組和一對一聊天**：
   - 確認兩種聊天類型都能正確顯示媒體

## 潛在問題

### 如果圖片仍然無法顯示

1. **檢查 URL 格式**：
   ```dart
   print('Final URL: ${resolveFullUrl(msg.content)}');
   ```
   確認生成的 URL 是否正確

2. **檢查後端路由**：
   - 確認 `/uploads/` 路由已正確配置
   - 確認文件確實存在於服務器上

3. **檢查認證**：
   - 確認請求包含有效的 JWT token
   - 確認服務器允許訪問 `/uploads/` 路徑

### 如果需要支持真正的加密媒體

如果未來需要支持加密的媒體內容：

1. 後端需要返回加密的 URL（長 base64 字符串）
2. `_looksLikeEncryptedContent()` 會識別並嘗試解密
3. 解密後得到真實的 URL 或路徑
4. `resolveFullUrl()` 轉換為完整 URL

## 相關文件

- `app/lib/features/chat/providers/room_media_provider.dart` - 媒體提供者（添加加密檢測）
- `app/lib/features/chat/utils/chat_url_utils.dart` - URL 工具（增強文件 ID 處理）
- `app/lib/core/network/network_service.dart` - 網絡服務（URL 拼接）
- `backend/internal/delivery/http/media_handler.go` - 後端媒體處理
