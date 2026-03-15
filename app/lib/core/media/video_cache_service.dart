import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:app/core/crypto/crypto_service.dart';

/// Error types for video cache operations
enum VideoCacheErrorType {
  networkError,
  decryptionError,
  fileIOError,
  invalidFormat,
}

/// Exception thrown by VideoCacheService
class VideoCacheException implements Exception {
  final VideoCacheErrorType type;
  final String message;
  final dynamic originalError;

  const VideoCacheException({
    required this.type,
    required this.message,
    this.originalError,
  });

  @override
  String toString() => 'VideoCacheException($type): $message';
}

/// Service for downloading, decrypting, and caching video files
class VideoCacheService {
  final CryptoService _cryptoService;
  final Dio _dio;

  VideoCacheService(this._cryptoService, this._dio);

  /// Downloads, decrypts, and caches a video file
  /// Returns the local file path of the decrypted video
  /// Throws VideoCacheException on failure
  Future<String> getOrDownloadVideo({
    required String messageId,
    required String videoUrl,
    required String fileKey,
  }) async {
    try {
      // Check if already cached
      if (await isCached(messageId)) {
        final cachedPath = await getCacheFilePath(messageId);
        final file = File(cachedPath);
        if (await file.exists()) {
          debugPrint('✅ Video cache hit for message: $messageId');
          return cachedPath;
        }
      }

      debugPrint('⬇️ Downloading video for message: $messageId');

      // Download encrypted video
      final encryptedBytes = await _downloadEncryptedVideo(videoUrl);

      // Decrypt video
      final decryptedBytes = await _decryptVideo(encryptedBytes, fileKey);

      // Save to cache
      final cachedPath = await _saveToCache(messageId, decryptedBytes);

      debugPrint('✅ Video cached successfully: $cachedPath');
      return cachedPath;
    } on VideoCacheException {
      rethrow;
    } catch (e) {
      throw VideoCacheException(
        type: VideoCacheErrorType.fileIOError,
        message: 'Unexpected error: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Checks if a video file is already cached and valid
  /// Verifies the file exists and is readable
  Future<bool> isCached(String messageId) async {
    try {
      final filePath = await getCacheFilePath(messageId);
      final file = File(filePath);
      
      // Check if file exists
      if (!await file.exists()) {
        return false;
      }
      
      // Verify file is readable by checking its length
      final length = await file.length();
      
      // Video files should have some content
      if (length == 0) {
        debugPrint('⚠️ Cached file is empty, marking as invalid: $messageId');
        await file.delete();
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('⚠️ Error validating cached file: $e');
      try {
        final filePath = await getCacheFilePath(messageId);
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('✅ Deleted corrupted cache file: $messageId');
        }
      } catch (deleteError) {
        debugPrint('⚠️ Failed to delete corrupted file: $deleteError');
      }
      return false;
    }
  }

  /// Gets the cache file path for a message ID
  Future<String> getCacheFilePath(String messageId) async {
    final cacheDir = await getTemporaryDirectory();
    return p.join(cacheDir.path, 'video_$messageId.mp4');
  }

  /// Downloads encrypted video from URL
  Future<Uint8List> _downloadEncryptedVideo(String videoUrl) async {
    try {
      final response = await _dio.get<List<int>>(
        videoUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60), // Longer timeout for videos
        ),
      );

      if (response.data == null) {
        throw VideoCacheException(
          type: VideoCacheErrorType.networkError,
          message: 'Download failed: empty response',
        );
      }

      return Uint8List.fromList(response.data!);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw VideoCacheException(
          type: VideoCacheErrorType.networkError,
          message: 'Network error: ${e.message}',
          originalError: e,
        );
      }
      throw VideoCacheException(
        type: VideoCacheErrorType.networkError,
        message: 'Download failed: ${e.message}',
        originalError: e,
      );
    } catch (e) {
      throw VideoCacheException(
        type: VideoCacheErrorType.networkError,
        message: 'Download failed: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Decrypts video bytes using the file key
  Future<Uint8List> _decryptVideo(
    Uint8List encryptedBytes,
    String fileKey,
  ) async {
    try {
      return await _cryptoService.decryptBytes(encryptedBytes, fileKey);
    } catch (e) {
      throw VideoCacheException(
        type: VideoCacheErrorType.decryptionError,
        message: 'Decryption failed: invalid key or corrupted data',
        originalError: e,
      );
    }
  }

  /// Saves decrypted video to cache
  Future<String> _saveToCache(
    String messageId,
    Uint8List videoBytes,
  ) async {
    try {
      final filePath = await getCacheFilePath(messageId);
      final file = File(filePath);

      // Ensure parent directory exists
      await file.parent.create(recursive: true);

      // Write decrypted video to file
      await file.writeAsBytes(videoBytes);

      return filePath;
    } catch (e) {
      throw VideoCacheException(
        type: VideoCacheErrorType.fileIOError,
        message: 'Failed to save cache file: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Clears all cached video files
  Future<void> clearCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final files = cacheDir.listSync();

      for (final file in files) {
        if (file is File && file.path.contains('video_')) {
          await file.delete();
        }
      }

      debugPrint('✅ Video cache cleared');
    } catch (e) {
      debugPrint('⚠️ Failed to clear video cache: $e');
    }
  }

  /// Gets total cache size in bytes
  Future<int> getCacheSize() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final files = cacheDir.listSync();
      int totalSize = 0;

      for (final file in files) {
        if (file is File && file.path.contains('video_')) {
          totalSize += await file.length();
        }
      }

      return totalSize;
    } catch (e) {
      debugPrint('⚠️ Failed to calculate cache size: $e');
      return 0;
    }
  }

  /// Deletes a specific cached video file
  Future<void> deleteCachedVideo(String messageId) async {
    try {
      final filePath = await getCacheFilePath(messageId);
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        debugPrint('✅ Deleted cached video for message: $messageId');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to delete cached video: $e');
    }
  }
}

/// Riverpod provider for VideoCacheService
final videoCacheServiceProvider = Provider<VideoCacheService>((ref) {
  final cryptoService = ref.watch(cryptoServiceProvider);
  final dio = Dio();
  return VideoCacheService(cryptoService, dio);
});
