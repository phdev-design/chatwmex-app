import 'dart:io';
import 'dart:convert'; // 加入這一行
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// 圖片快取服務
/// 
/// 負責管理圖片的本地快取，避免重複下載
/// 支援 E2EE 加密圖片的快取
class ImageCacheService {
  static const String _cacheDir = 'image_cache';
  static const int _maxCacheSize = 500 * 1024 * 1024; // 500MB
  static const Duration _cacheExpiry = Duration(days: 30);

  /// 獲取快取目錄
  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(appDir.path, _cacheDir));
    
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    
    return cacheDir;
  }

  /// 生成快取檔案名稱（使用 URL 的 MD5 hash）
  String _getCacheFileName(String url) {
    final bytes = utf8.encode(url);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// 獲取快取檔案路徑
  Future<String> _getCacheFilePath(String url) async {
    final cacheDir = await _getCacheDirectory();
    final fileName = _getCacheFileName(url);
    
    // 從 URL 獲取副檔名
    final uri = Uri.tryParse(url);
    String ext = '';
    if (uri != null) {
      ext = p.extension(uri.path);
      if (ext.isEmpty) ext = '.jpg'; // 預設為 jpg
    }
    
    return p.join(cacheDir.path, '$fileName$ext');
  }

  /// 檢查快取是否存在且未過期
  Future<bool> isCached(String url) async {
    try {
      final filePath = await _getCacheFilePath(url);
      final file = File(filePath);
      
      if (!await file.exists()) {
        return false;
      }
      
      // 檢查檔案是否過期
      final stat = await file.stat();
      final age = DateTime.now().difference(stat.modified);
      
      if (age > _cacheExpiry) {
        // 過期，刪除檔案
        await file.delete();
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('❌ [ImageCache] 檢查快取失敗: $e');
      return false;
    }
  }

  /// 獲取快取的圖片檔案
  Future<File?> getCachedImage(String url) async {
    try {
      if (!await isCached(url)) {
        return null;
      }
      
      final filePath = await _getCacheFilePath(url);
      return File(filePath);
    } catch (e) {
      debugPrint('❌ [ImageCache] 獲取快取失敗: $e');
      return null;
    }
  }

  /// 下載並快取圖片
  /// 
  /// [url] 圖片 URL
  /// [imageData] 如果已經下載了圖片數據（例如解密後的數據），可以直接傳入
  Future<File?> cacheImage(String url, {Uint8List? imageData}) async {
    // URL 驗證：檢查是否為空或 null
    if (url.isEmpty) {
      debugPrint('⚠️ [ImageCache] URL 無效：空字串');
      return null;
    }
    
    // 只在需要下載時進行 URL 格式驗證（imageData 為 null）
    if (imageData == null) {
      // URL 格式驗證：檢查是否可以解析為有效 URI
      final uri = Uri.tryParse(url);
      if (uri == null) {
        debugPrint('⚠️ [ImageCache] URL 無效：無法解析 URL');
        return null;
      }
      
      // 檢查是否為有效的 URL 格式
      // 允許：完整 URL (http://, https://)、相對路徑 (/uploads/...)、MongoDB ObjectID (24 hex chars)
      // 拒絕：沒有 scheme 且沒有 host 且不是相對路徑的情況（如加密 Base64 字串）
      final hasScheme = uri.hasScheme;
      final hasHost = uri.host.isNotEmpty;
      final isRelativePath = url.startsWith('/');
      final isMaybeObjectId = url.length == 24 && RegExp(r'^[a-f0-9]{24}$').hasMatch(url);
      
      if (!hasScheme && !hasHost && !isRelativePath && !isMaybeObjectId) {
        debugPrint('⚠️ [ImageCache] URL 無效：缺少 scheme 和 host');
        return null;
      }
    }
    
    try {
      final filePath = await _getCacheFilePath(url);
      final file = File(filePath);
      
      if (imageData != null) {
        // 直接寫入提供的數據（例如解密後的圖片）
        await file.writeAsBytes(imageData);
        debugPrint('✅ [ImageCache] 快取圖片成功（從數據）: $url');
      } else {
        // 從 URL 下載
        final dio = Dio();
        await dio.download(url, filePath);
        debugPrint('✅ [ImageCache] 快取圖片成功（從 URL）: $url');
      }
      
      // 檢查快取大小，如果超過限制則清理舊檔案
      await _cleanupIfNeeded();
      
      return file;
    } catch (e) {
      debugPrint('❌ [ImageCache] 下載失敗: $e');
      return null;
    }
  }

  /// 獲取圖片（優先從快取，沒有則下載）
  Future<File?> getImage(String url) async {
    try {
      // 1. 檢查快取
      final cachedFile = await getCachedImage(url);
      if (cachedFile != null) {
        debugPrint('✅ [ImageCache] 使用快取: $url');
        return cachedFile;
      }
      
      // 2. 下載並快取
      debugPrint('📥 [ImageCache] 下載圖片: $url');
      return await cacheImage(url);
    } catch (e) {
      debugPrint('❌ [ImageCache] 獲取圖片失敗: $e');
      return null;
    }
  }

  /// 清理過期的快取檔案
  Future<void> _cleanupIfNeeded() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final files = await cacheDir.list().toList();
      
      // 計算總大小
      int totalSize = 0;
      final fileStats = <File, FileStat>{};
      
      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          fileStats[entity] = stat;
          totalSize += stat.size;
        }
      }
      
      // 如果超過限制，刪除最舊的檔案
      if (totalSize > _maxCacheSize) {
        debugPrint('⚠️ [ImageCache] 快取超過限制 ($totalSize bytes)，開始清理...');
        
        // 按修改時間排序（最舊的在前）
        final sortedFiles = fileStats.entries.toList()
          ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
        
        // 刪除最舊的檔案，直到低於限制的 80%
        final targetSize = (_maxCacheSize * 0.8).toInt();
        int currentSize = totalSize;
        
        for (final entry in sortedFiles) {
          if (currentSize <= targetSize) break;
          
          await entry.key.delete();
          currentSize -= entry.value.size;
          debugPrint('🗑️ [ImageCache] 刪除舊快取: ${entry.key.path}');
        }
        
        debugPrint('✅ [ImageCache] 清理完成，當前大小: $currentSize bytes');
      }
    } catch (e) {
      debugPrint('❌ [ImageCache] 清理快取失敗: $e');
    }
  }

  /// 清除所有快取
  Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        debugPrint('✅ [ImageCache] 已清除所有快取');
      }
    } catch (e) {
      debugPrint('❌ [ImageCache] 清除快取失敗: $e');
    }
  }

  /// 獲取快取大小
  Future<int> getCacheSize() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final files = await cacheDir.list().toList();
      
      int totalSize = 0;
      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
      
      return totalSize;
    } catch (e) {
      debugPrint('❌ [ImageCache] 獲取快取大小失敗: $e');
      return 0;
    }
  }
}

final imageCacheServiceProvider = Provider<ImageCacheService>((ref) {
  return ImageCacheService();
});
