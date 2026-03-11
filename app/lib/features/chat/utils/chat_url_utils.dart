import 'package:app/core/network/network_service.dart';

/// 🚫 絕對強制規則：將路徑或 ID 轉換為完整 URL
/// 
/// 輸入類型：
/// 1. 完整 URL (http://, https://) → 直接返回
/// 2. 相對路徑 (/uploads/...) → 拼接 baseUrl
/// 3. MongoDB ObjectID (24 個十六進制字符) → 轉換為 /uploads/images/{id} 並拼接 baseUrl
/// 4. 其他短字串 → 嘗試作為相對路徑拼接
/// 5. 長 Base64 字串（含 +/=）→ 返回空字串（表示上游解密失敗）
/// 
/// 輸出：
/// - 永遠返回完整 URL (http://...)
/// - 如果無法處理，返回空字串
String resolveFullUrl(String? path) {
  if (path == null || path.isEmpty) {
    return '';
  }
  
  // 1. 完整 URL，直接返回
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  
  // 2. 相對路徑，拼接 baseUrl
  if (path.startsWith('/uploads/')) {
    return NetworkService.resolveUrl(path);
  }
  
  // 3. 🚫 檢查是否為長 Base64 字串（表示上游解密失敗）
  if (path.length >= 40 && (path.contains('+') || path.contains('/') || path.contains('='))) {
    print('⚠️ [resolveFullUrl] 收到未解密內容');
    return '';
  }
  
  // 4. MongoDB ObjectID (24 個十六進制字符)
  if (path.length == 24 && RegExp(r'^[a-f0-9]{24}$', caseSensitive: false).hasMatch(path)) {
    return NetworkService.resolveUrl('/uploads/images/$path');
  }
  
  // 5. 其他情況：嘗試作為相對路徑拼接
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return NetworkService.resolveUrl(normalizedPath);
}

/// 從文字內容中提取所有 URL
List<String> extractAllUrls(String content) {
  final regex = RegExp(r'https?://[^\s]+', caseSensitive: false);
  return regex
      .allMatches(content)
      .map((m) => m.group(0) ?? '')
      .where((u) => u.isNotEmpty)
      .toList();
}
