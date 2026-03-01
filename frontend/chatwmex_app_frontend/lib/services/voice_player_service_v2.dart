import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_session_service.dart';

/// 使用 just_audio 的語音播放服務 V2
/// 更新：實現了智能預緩存策略，優化了播放和緩存邏輯。
class VoicePlayerServiceV2 {
  AudioPlayer? _player;
  String? _messageId;
  bool _isPlaying = false;
  bool _isPaused = false;
  bool _isCompleted = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  // 狀態流控制器
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  // 公開的流
  Stream<bool> get playingStream => _playingController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  bool get isCompleted => _isCompleted;
  Duration get duration => _duration;
  Duration get position => _position;

  // 🔥 方案 A：智能預緩存 - 修改播放邏輯
  Future<bool> playVoice(String messageId, String audioUrl,
      {int? fileSize}) async {
    _messageId = messageId;
    try {
      // 驗證檔案大小邏輯保持不變...
      if (fileSize != null && fileSize == 0) {
      } else if (fileSize == null) {}

      // 檢查是否需要創建新播放器
      bool needNewPlayer = _player == null;

      if (_player != null) {
        await _player!.stop();
      }

      // 激活音頻會話
      final audioSession = AudioSessionService();
      final sessionActivated = await audioSession.activate();
      if (!sessionActivated) {
        return false;
      }

      // 創建播放器
      if (needNewPlayer) {
        _player = AudioPlayer();
        _setupPlayerListeners();
      }

      // 🔥 智能預緩存策略 (已修改為在所有平台和模式下均啟用)
      final cachedPath = await _getCachedFileIfExists(messageId, audioUrl);
      if (cachedPath != null) {
        await _player!.setFilePath(cachedPath);
      } else {
        await _player!.setUrl(audioUrl);

        // 🔥 關鍵改進：在背景下載並緩存文件
        _startBackgroundCaching(messageId, audioUrl);
      }

      // 開始播放
      await _player!.play();
      _isPlaying = true;
      _isPaused = false;
      _isCompleted = false;

      // 🔥 修復：檢查 StreamController 是否已關閉
      if (!_playingController.isClosed) {
        _playingController.add(true);
      }
      return true;
    } catch (e) {
      _isPlaying = false;
      _isPaused = false;

      // 🔥 修復：檢查 StreamController 是否已關閉
      if (!_playingController.isClosed) {
        _playingController.add(false);
      }
      return false;
    }
  }

  /// 處理播放完成
  void _handlePlaybackCompleted() async {
    if (_isCompleted) {
      return;
    }
    try {
      _isCompleted = true;
      if (_player != null) {
        await _player!.stop();
      }
      _isPlaying = false;
      _isPaused = false;
      _position = Duration.zero;

      // 🔥 修復：檢查 StreamController 是否已關閉
      if (!_playingController.isClosed) {
        _playingController.add(false);
      }
      if (!_positionController.isClosed) {
        _positionController.add(Duration.zero);
      }
    } catch (e) {}
  }

  /// 設置播放器監聽器
  void _setupPlayerListeners() {
    if (_player == null) return;

    _player!.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _isPaused =
          !state.playing && state.processingState == ProcessingState.ready;

      // 🔥 修復：檢查 StreamController 是否已關閉
      if (!_playingController.isClosed) {
        _playingController.add(_isPlaying);
      }

      if (!state.playing) {
        if (state.processingState == ProcessingState.completed) {
          _handlePlaybackCompleted();
        } else if (state.processingState == ProcessingState.idle &&
            _position >= _duration &&
            _duration != Duration.zero) {
          _handlePlaybackCompleted();
        }
      }
    });

    _player!.positionStream.listen((position) {
      _position = position;

      // 🔥 修復：檢查 StreamController 是否已關閉
      if (!_positionController.isClosed) {
        _positionController.add(position);
      }

      if (_duration != Duration.zero && position >= _duration) {
        if (_isPlaying) {
          _handlePlaybackCompleted();
        }
      }
    });

    _player!.durationStream.listen((duration) {
      if (duration != null) {
        _duration = duration;

        // 🔥 修復：檢查 StreamController 是否已關閉
        if (!_durationController.isClosed) {
          _durationController.add(duration);
        }
      }
    });

    _player!.errorStream.listen((error) {
      _isPlaying = false;
      _isPaused = false;

      // 🔥 修復：檢查 StreamController 是否已關閉
      if (!_playingController.isClosed) {
        _playingController.add(false);
      }
    });
  }

  /// 暫停播放
  Future<void> pauseVoice() async {
    try {
      if (_player != null && _isPlaying) {
        await _player!.pause();
        _isPlaying = false;
        _isPaused = true;

        // 🔥 修復：檢查 StreamController 是否已關閉
        if (!_playingController.isClosed) {
          _playingController.add(false);
        }
      }
    } catch (e) {}
  }

  /// 繼續播放
  Future<void> resumeVoice() async {
    try {
      if (_player != null && _isPaused) {
        await _player!.play();
        _isPlaying = true;
        _isPaused = false;

        // 🔥 修復：檢查 StreamController 是否已關閉
        if (!_playingController.isClosed) {
          _playingController.add(true);
        }
      }
    } catch (e) {}
  }

  /// 停止播放
  Future<void> stopVoice() async {
    try {
      if (_player != null) {
        await _player!.stop();
        _isPlaying = false;
        _isPaused = false;
        _position = Duration.zero;

        // 🔥 修復：檢查 StreamController 是否已關閉
        if (!_playingController.isClosed) {
          _playingController.add(false);
        }
        if (!_positionController.isClosed) {
          _positionController.add(Duration.zero);
        }
      }
      final audioSession = AudioSessionService();
      await audioSession.deactivate();
    } catch (e) {}
  }

  /// 跳轉到指定位置
  Future<void> seekTo(Duration position) async {
    try {
      if (_player != null) {
        await _player!.seek(position);
        _position = position;

        // 🔥 修復：檢查 StreamController 是否已關閉
        if (!_positionController.isClosed) {
          _positionController.add(position);
        }
      }
    } catch (e) {}
  }

  // 🔥 新增：背景緩存方法
  void _startBackgroundCaching(String messageId, String audioUrl) {
    // 使用 Future.microtask 確保不阻塞播放
    Future.microtask(() async {
      try {
        final cachedPath = await _downloadAndCacheAudio(messageId, audioUrl);
        if (cachedPath != null) {
          // 可選：通知緩存完成
          _notifyCacheCompleted(messageId, cachedPath);
        } else {}
      } catch (e) {}
    });
  }

  // 🔥 新增：緩存完成通知（可選）
  void _notifyCacheCompleted(String messageId, String cachedPath) {
    // 未來可以添加緩存完成的回調或通知
  }

  // 🔥 改進：下載並快取音頻文件（加強錯誤處理）
  Future<String?> _downloadAndCacheAudio(
      String messageId, String audioUrl) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${directory.path}/voice_cache');

      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      // 生成快取文件名
      final fileName = '${messageId}_${audioUrl.hashCode}.m4a'; // 🔥 改為 .m4a
      final cachedFile = File('${cacheDir.path}/$fileName');

      // 如果文件已存在，直接返回
      if (await cachedFile.exists()) {
        final fileSize = await cachedFile.length();
        return cachedFile.path;
      }

      // 🔥 改進：使用更好的下載配置
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 60);

      final response = await dio.download(
        audioUrl,
        cachedFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total * 100).toStringAsFixed(1);
          }
        },
      );

      if (response.statusCode == 200 && await cachedFile.exists()) {
        final fileSize = await cachedFile.length();
        return cachedFile.path;
      } else {
        // 清理可能的不完整文件
        if (await cachedFile.exists()) {
          await cachedFile.delete();
        }
        return null;
      }
    } catch (e) {
      // 清理可能的不完整文件
      try {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = '${messageId}_${audioUrl.hashCode}.m4a';
        final cachedFile = File('${directory.path}/voice_cache/$fileName');
        if (await cachedFile.exists()) {
          await cachedFile.delete();
        }
      } catch (cleanupError) {}

      return null;
    }
  }

  // 🔥 改進：檢查緩存文件是否存在（加強驗證）
  Future<String?> _getCachedFileIfExists(
      String messageId, String audioUrl) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${directory.path}/voice_cache');

      if (!await cacheDir.exists()) {
        return null;
      }

      // 生成快取文件名（支持舊格式和新格式）
      final fileNameNew = '${messageId}_${audioUrl.hashCode}.m4a';
      final fileNameOld = '${messageId}_${audioUrl.hashCode}.aac';

      final cachedFileNew = File('${cacheDir.path}/$fileNameNew');
      final cachedFileOld = File('${cacheDir.path}/$fileNameOld');

      // 優先檢查新格式
      if (await cachedFileNew.exists()) {
        final fileSize = await cachedFileNew.length();
        if (fileSize > 0) {
          return cachedFileNew.path;
        } else {
          await cachedFileNew.delete();
        }
      }

      // 檢查舊格式
      if (await cachedFileOld.exists()) {
        final fileSize = await cachedFileOld.length();
        if (fileSize > 0) {
          return cachedFileOld.path;
        } else {
          await cachedFileOld.delete();
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // 🔥 新增：獲取緩存統計信息
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${directory.path}/voice_cache');

      if (!await cacheDir.exists()) {
        return {'fileCount': 0, 'totalSize': 0, 'cachePath': cacheDir.path};
      }

      final files = await cacheDir.list().toList();
      int totalSize = 0;
      int fileCount = 0;

      for (final file in files) {
        if (file is File) {
          try {
            final size = await file.length();
            totalSize += size;
            fileCount++;
          } catch (e) {}
        }
      }

      return {
        'fileCount': fileCount,
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / 1024 / 1024).toStringAsFixed(2),
        'cachePath': cacheDir.path,
      };
    } catch (e) {
      return {'fileCount': 0, 'totalSize': 0, 'error': e.toString()};
    }
  }

  // 🔥 新增：清理緩存
  Future<void> clearCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${directory.path}/voice_cache');

      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {}
  }

  /// 清理資源
  void dispose() {
    _player?.dispose();
    _player = null;
    _playingController.close();
    _positionController.close();
    _durationController.close();
  }
}
