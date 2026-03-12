# 圖片優化實作說明

## 概述

本次更新實現了三個主要目標：
1. 修正 iPhone 上傳圖片 400 錯誤（HEIC 格式和大小問題）
2. 實作圖片壓縮功能
3. 實作圖片本地快取機制

## 目標一 & 二：圖片壓縮與格式轉換

### 修改的檔案

#### 1. `app/lib/core/media/media_service.dart`

**主要變更**：
- 添加了 `compressImage()` 方法，自動壓縮圖片到 5MB 以下
- 修改了 `pickImage()` 方法，在選擇圖片時自動進行壓縮
- 使用 `flutter_image_compress` 套件進行圖片壓縮
- 自動將 HEIC 等格式轉換為 JPEG

**功能特點**：
- 自動檢測圖片大小，如果小於 5MB 且格式支援，則不進行壓縮
- 根據原始檔案大小動態調整壓縮品質（50-85%）
- 如果第一次壓縮後仍超過 5MB，會進行第二次壓縮
- 支援的輸出格式：JPEG（最相容）
- 自動調整圖片尺寸（最大 1920x1920，超大圖片會縮小到 1280x1280）

**使用方式**：
```dart
// 在聊天室輸入框或其他地方選擇圖片
final mediaService = ref.read(mediaServiceProvider);
final imageFile = await mediaService.pickImage(ImageSource.gallery);
// imageFile 已經是壓縮後的圖片，可以直接上傳
```

### 壓縮邏輯說明

1. **檢查原始檔案**：
   - 如果 < 5MB 且格式支援（jpg, jpeg, png, webp），直接返回
   - 否則進入壓縮流程

2. **第一次壓縮**：
   - 品質：根據檔案大小動態計算（50-85%）
   - 格式：統一轉換為 JPEG
   - 尺寸：最大 1920x1920（超大檔案會縮小到 1280x1280）

3. **第二次壓縮**（如果需要）：
   - 如果第一次壓縮後仍 > 5MB
   - 品質：50%
   - 尺寸：1280x1280

## 目標三：圖片本地快取機制

### 新增的檔案

#### 1. `app/lib/core/media/image_cache_service.dart`

**功能**：
- 管理圖片的本地快取
- 自動清理過期快取（30 天）
- 限制快取大小（最大 500MB）
- 支援 E2EE 加密圖片的快取

**主要方法**：
- `getImage(String url)`: 獲取圖片（優先從快取，沒有則下載）
- `cacheImage(String url, {Uint8List? imageData})`: 快取圖片
- `getCachedImage(String url)`: 獲取快取的圖片
- `isCached(String url)`: 檢查是否已快取
- `clearAllCache()`: 清除所有快取
- `getCacheSize()`: 獲取快取大小

**快取策略**：
- 使用 URL 的 MD5 hash 作為檔案名稱
- 快取位置：`Application Documents Directory/image_cache/`
- 自動清理：當快取超過 500MB 時，刪除最舊的檔案
- 過期時間：30 天

#### 2. `app/lib/core/media/cached_network_image_widget.dart`

**功能**：
- 提供一個帶快取功能的圖片 Widget
- 自動處理載入狀態和錯誤狀態
- 優先從本地快取讀取，沒有則下載

**使用方式**：
```dart
CachedNetworkImageWidget(
  imageUrl: 'https://example.com/image.jpg',
  fit: BoxFit.cover,
  width: 200,
  height: 200,
  placeholder: CircularProgressIndicator(),
  errorWidget: Icon(Icons.broken_image),
)
```

### 修改的檔案

#### 1. `app/lib/features/chat/ui/widgets/message_bubble.dart`

**變更**：
- 將 `Image.network` 替換為 `CachedNetworkImageWidget`
- 聊天室中的圖片訊息現在會自動快取
- Link preview 的圖片也使用快取

**效果**：
- 第一次載入圖片時會下載並快取
- 之後再次載入相同圖片時，直接從本地讀取
- 大幅減少網路流量和載入時間

#### 2. `app/lib/features/chat/ui/photo_screen.dart`

**變更**：
- 修改為 `ConsumerStatefulWidget` 以使用 Riverpod
- `_downloadToTemp()` 方法優先從快取獲取圖片
- 圖片顯示使用 `FutureBuilder` 配合快取服務
- 下載的圖片會自動快取

**效果**：
- 打開圖片預覽時，優先使用快取
- 分享、裁剪、儲存功能都使用快取的圖片
- 避免重複下載相同圖片

## E2EE 相容性說明

### 快取加密圖片的處理

由於專案使用端對端加密（E2EE），圖片在傳輸時可能是加密的。快取服務提供了兩種方式來處理：

1. **直接快取 URL**：
   - 如果圖片 URL 本身就是解密後的圖片
   - 直接使用 `getImage(url)` 即可

2. **快取解密後的數據**：
   - 如果需要先解密圖片
   - 使用 `cacheImage(url, imageData: decryptedBytes)`
   - 將解密後的圖片數據傳入快取

### 建議的 E2EE 整合方式

如果圖片需要解密，建議在 `CryptoService` 中添加圖片解密方法：

```dart
// 在 crypto_service.dart 中
Future<Uint8List?> decryptImage(String encryptedUrl, String publicKey) async {
  // 1. 下載加密的圖片
  final response = await dio.get(encryptedUrl, options: Options(responseType: ResponseType.bytes));
  final encryptedBytes = response.data as Uint8List;
  
  // 2. 解密圖片
  final decryptedBytes = await decrypt(encryptedBytes, publicKey);
  
  // 3. 快取解密後的圖片
  final cacheService = ref.read(imageCacheServiceProvider);
  await cacheService.cacheImage(encryptedUrl, imageData: decryptedBytes);
  
  return decryptedBytes;
}
```

然後在 `CachedNetworkImageWidget` 中使用：

```dart
// 如果圖片需要解密
final cryptoService = ref.read(cryptoServiceProvider);
final decryptedBytes = await cryptoService.decryptImage(imageUrl, publicKey);
// 圖片已經自動快取，下次直接從本地讀取
```

## 測試建議

### 測試圖片壓縮

1. **iPhone HEIC 格式測試**：
   - 使用 iPhone 拍攝照片（HEIC 格式）
   - 在聊天室中選擇該照片
   - 確認上傳成功（不再出現 400 錯誤）
   - 檢查上傳的圖片大小 < 5MB

2. **大圖片測試**：
   - 選擇一張 > 5MB 的圖片
   - 確認壓縮後 < 5MB
   - 確認圖片品質可接受

3. **小圖片測試**：
   - 選擇一張 < 5MB 的 JPEG 圖片
   - 確認不會被過度壓縮

### 測試圖片快取

1. **首次載入測試**：
   - 清除應用數據
   - 打開聊天室，載入包含圖片的訊息
   - 觀察圖片下載過程
   - 檢查快取目錄是否有檔案

2. **快取命中測試**：
   - 關閉並重新打開聊天室
   - 觀察圖片載入速度（應該很快）
   - 確認沒有網路請求（可以開啟飛航模式測試）

3. **快取清理測試**：
   - 在設定頁面添加「清除圖片快取」功能
   - 測試清除後圖片重新下載

4. **快取大小限制測試**：
   - 載入大量圖片（> 500MB）
   - 確認舊圖片被自動清理
   - 確認快取大小不超過限制

## 效能提升

### 預期效果

1. **上傳速度**：
   - 壓縮後的圖片更小，上傳更快
   - 減少網路流量

2. **載入速度**：
   - 第一次載入：與之前相同
   - 第二次載入：幾乎瞬間顯示（從本地讀取）
   - 減少 90% 以上的網路請求

3. **流量節省**：
   - 重複查看相同圖片時不消耗流量
   - 對於經常查看的聊天室，流量節省明顯

4. **用戶體驗**：
   - 圖片載入更流暢
   - 離線時仍可查看已快取的圖片
   - 減少等待時間

## 後續優化建議

1. **添加快取管理 UI**：
   - 在設定頁面顯示快取大小
   - 提供清除快取按鈕
   - 允許用戶設定快取大小限制

2. **預載入優化**：
   - 在背景預載入即將顯示的圖片
   - 提升滾動流暢度

3. **智能壓縮**：
   - 根據網路狀況動態調整壓縮品質
   - WiFi 下使用較高品質，行動網路下使用較低品質

4. **快取統計**：
   - 記錄快取命中率
   - 分析哪些圖片最常被訪問
   - 優化快取策略

## 故障排除

### 問題：圖片壓縮失敗

**可能原因**：
- 圖片格式不支援
- 磁碟空間不足

**解決方案**：
- 檢查錯誤日誌
- 確保有足夠的暫存空間
- 降低壓縮品質或尺寸

### 問題：快取不生效

**可能原因**：
- 快取目錄權限問題
- URL 變化（每次都不同）

**解決方案**：
- 檢查應用權限
- 確認 URL 是穩定的
- 檢查快取目錄是否存在

### 問題：快取佔用過多空間

**解決方案**：
- 降低 `_maxCacheSize` 限制
- 縮短 `_cacheExpiry` 時間
- 手動清除快取

## 相關檔案清單

### 新增檔案
- `app/lib/core/media/image_cache_service.dart`
- `app/lib/core/media/cached_network_image_widget.dart`
- `IMAGE_OPTIMIZATION_IMPLEMENTATION.md`

### 修改檔案
- `app/lib/core/media/media_service.dart`
- `app/lib/features/chat/ui/widgets/message_bubble.dart`
- `app/lib/features/chat/ui/photo_screen.dart`

### 依賴套件
- `flutter_image_compress: ^2.4.0` (已存在)
- `crypto: ^3.0.7` (已存在，用於 MD5 hash)
- `path_provider: ^2.1.5` (已存在)
- `dio: ^5.9.1` (已存在)
