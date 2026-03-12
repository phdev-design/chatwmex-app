import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:app/core/crypto/crypto_service.dart';

/// Error types for audio cache operations
enum AudioCacheErrorType {
  networkError,
  decryptionError,
  fileIOError,
  invalidFormat,
}

/// Exception thrown by AudioCacheService
class AudioCacheException implements Exception {
  final AudioCacheErrorType type;
  final String message;
  final dynamic originalError;

  const AudioCacheException({
    required this.type,
    required this.message,
    this.originalError,
  });

  @override
  String toString() => 'AudioCacheException($type): $message';
}

/// Service for downloading, decrypting, and caching audio files
class AudioCacheService {
  final CryptoService _cryptoService;
  final Dio _dio;

  AudioCacheService(this._cryptoService, this._dio);

  /// Downloads, decrypts, and caches an audio file
  /// Returns the local file path of the decrypted audio
  /// Throws AudioCacheException on failure
  Future<String> getOrDownloadAudio({
    required String messageId,
    required String audioUrl,
    required String fileKey,
  }) async {
    try {
      // Check if already cached
      if (await isCached(messageId)) {
        final cachedPath = await _getCacheFilePath(messageId);
        final file = File(cachedPath);
        if (await file.exists()) {
          debugPrint('✅ Audio cache hit for message: $messageId');
          return cachedPath;
        }
      }

      debugPrint('⬇️ Downloading audio for message: $messageId');

      // Download encrypted audio
      final encryptedBytes = await _downloadEncryptedAudio(audioUrl);

      // Decrypt audio
      final decryptedBytes = await _decryptAudio(encryptedBytes, fileKey);

      // Save to cache
      final cachedPath = await _saveToCache(messageId, decryptedBytes);

      debugPrint('✅ Audio cached successfully: $cachedPath');
      return cachedPath;
    } on AudioCacheException {
      rethrow;
    } catch (e) {
      throw AudioCacheException(
        type: AudioCacheErrorType.fileIOError,
        message: 'Unexpected error: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Checks if an audio file is already cached
  Future<bool> isCached(String messageId) async {
    try {
      final filePath = await _getCacheFilePath(messageId);
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// Gets the cache file path for a message ID
  Future<String> _getCacheFilePath(String messageId) async {
    final cacheDir = await getTemporaryDirectory();
    return p.join(cacheDir.path, 'audio_$messageId.m4a');
  }

  /// Downloads encrypted audio from URL
  Future<Uint8List> _downloadEncryptedAudio(String audioUrl) async {
    try {
      final response = await _dio.get<List<int>>(
        audioUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.data == null) {
        throw AudioCacheException(
          type: AudioCacheErrorType.networkError,
          message: 'Download failed: empty response',
        );
      }

      return Uint8List.fromList(response.data!);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw AudioCacheException(
          type: AudioCacheErrorType.networkError,
          message: 'Network error: ${e.message}',
          originalError: e,
        );
      }
      throw AudioCacheException(
        type: AudioCacheErrorType.networkError,
        message: 'Download failed: ${e.message}',
        originalError: e,
      );
    } catch (e) {
      throw AudioCacheException(
        type: AudioCacheErrorType.networkError,
        message: 'Download failed: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Decrypts audio bytes using the file key
  Future<Uint8List> _decryptAudio(
    Uint8List encryptedBytes,
    String fileKey,
  ) async {
    try {
      return await _cryptoService.decryptBytes(encryptedBytes, fileKey);
    } catch (e) {
      throw AudioCacheException(
        type: AudioCacheErrorType.decryptionError,
        message: 'Decryption failed: invalid key or corrupted data',
        originalError: e,
      );
    }
  }

  /// Saves decrypted audio to cache
  Future<String> _saveToCache(
    String messageId,
    Uint8List audioBytes,
  ) async {
    try {
      final filePath = await _getCacheFilePath(messageId);
      final file = File(filePath);

      // Ensure parent directory exists
      await file.parent.create(recursive: true);

      // Write decrypted audio to file
      await file.writeAsBytes(audioBytes);

      return filePath;
    } catch (e) {
      throw AudioCacheException(
        type: AudioCacheErrorType.fileIOError,
        message: 'Failed to save cache file: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// Clears all cached audio files
  Future<void> clearCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final files = cacheDir.listSync();

      for (final file in files) {
        if (file is File && file.path.contains('audio_')) {
          await file.delete();
        }
      }

      debugPrint('✅ Audio cache cleared');
    } catch (e) {
      debugPrint('⚠️ Failed to clear audio cache: $e');
    }
  }

  /// Gets total cache size in bytes
  Future<int> getCacheSize() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final files = cacheDir.listSync();
      int totalSize = 0;

      for (final file in files) {
        if (file is File && file.path.contains('audio_')) {
          totalSize += await file.length();
        }
      }

      return totalSize;
    } catch (e) {
      debugPrint('⚠️ Failed to calculate cache size: $e');
      return 0;
    }
  }

  /// Deletes a specific cached audio file
  Future<void> deleteCachedAudio(String messageId) async {
    try {
      final filePath = await _getCacheFilePath(messageId);
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
        debugPrint('✅ Deleted cached audio for message: $messageId');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to delete cached audio: $e');
    }
  }
}

/// Riverpod provider for AudioCacheService
final audioCacheServiceProvider = Provider<AudioCacheService>((ref) {
  final cryptoService = ref.watch(cryptoServiceProvider);
  final dio = Dio(); // Create a separate Dio instance for direct URL downloads
  return AudioCacheService(cryptoService, dio);
});
