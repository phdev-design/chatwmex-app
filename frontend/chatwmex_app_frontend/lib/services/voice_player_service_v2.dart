import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
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
  Future<bool> playVoice(String messageId, String audioUrl, {int? fileSize}) async {
    _messageId = messageId;
    try {
      print('VoicePlayerServiceV2 ($messageId): 開始播放流程, URL: $audioUrl');

      // 驗證檔案大小邏輯保持不變...
      if (fileSize != null && fileSize == 0) {
        print('VoicePlayerServiceV2 ($messageId): 警告 - 檔案大小為 0，但仍嘗試播放');
      } else if (fileSize == null) {
        print('VoicePlayerServiceV2 ($messageId): 警告 - 檔案大小未知，但仍嘗試播放');
      }
      
      // 檢查是否需要創建新播放器
      bool needNewPlayer = _player == null;

      if (_player != null) {
        await _player!.stop();
        print('VoicePlayerServiceV2: 停止當前播放器');
      }

      // 激活音頻會話
      final audioSession = AudioSessionService();
      final sessionActivated = await audioSession.activate();
      if (!sessionActivated) {
        print('VoicePlayerServiceV2: 音頻會話激活失敗');
        return false;
      }

      // 創建播放器
      if (needNewPlayer) {
        _player = AudioPlayer();
        _setupPlayerListeners();
        print('VoicePlayerServiceV2: 創建新播放器');
      }

      // 🔥 智能預緩存策略 (已修改為在所有平台和模式下均啟用)
      final cachedPath = await _getCachedFileIfExists(messageId, audioUrl);
      if (cachedPath != null) {
        print('VoicePlayerServiceV2: ✅ 命中快取，使用本地檔案播放: $cachedPath');
        await _player!.setFilePath(cachedPath);
      } else {
        print('VoicePlayerServiceV2: ⚠️ 未命中快取，直接播放 URL 並開始背景緩存');
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

      print('VoicePlayerServiceV2 ($messageId): 🎵 播放開始');
      return true;
    } catch (e) {
      print('VoicePlayerServiceV2 ($messageId): ❌ 播放失敗: $e');
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
      print('VoicePlayerServiceV2: 播放已經完成，跳過重複處理');
      return;
    }
    try {
      print('VoicePlayerServiceV2: 處理播放完成');
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
      print('VoicePlayerServiceV2: 播放完成處理完畢，播放器已停止並重置');
    } catch (e) {
      print('VoicePlayerServiceV2: 處理播放完成時出錯: $e');
    }
  }

  /// 設置播放器監聽器
  void _setupPlayerListeners() {
    if (_player == null) return;

    _player!.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _isPaused = !state.playing && state.processingState == ProcessingState.ready;
      
      // 🔥 修復：檢查 StreamController 是否已關閉
      if (!_playingController.isClosed) {
        _playingController.add(_isPlaying);
      }
      
      print('VoicePlayerServiceV2: 播放狀態 - playing: ${state.playing}, processing: ${state.processingState}');
      if (!state.playing) {
        if (state.processingState == ProcessingState.completed) {
          print('VoicePlayerServiceV2: 播放完成（ProcessingState.completed），自動停止');
          _handlePlaybackCompleted();
        } else if (state.processingState == ProcessingState.idle && _position >= _duration && _duration != Duration.zero) {
          print('VoicePlayerServiceV2: 播放完成（位置達到結尾），自動停止');
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
        print('VoicePlayerServiceV2: 基於位置檢測到播放完成 - position: ${position.inSeconds}s, duration: ${_duration.inSeconds}s');
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
      print('VoicePlayerServiceV2: 播放錯誤: $error');
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
        print('VoicePlayerServiceV2 ($_messageId): 暫停播放');
      }
    } catch (e) {
      print('VoicePlayerServiceV2 ($_messageId): 暫停失敗: $e');
    }
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
        print('VoicePlayerServiceV2 ($_messageId): 繼續播放');
      }
    } catch (e) {
      print('VoicePlayerServiceV2 ($_messageId): 繼續播放失敗: $e');
    }
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
        print('VoicePlayerServiceV2 ($_messageId): 停止播放');
      }
      final audioSession = AudioSessionService();
      await audioSession.deactivate();
      print('VoicePlayerServiceV2: 音頻會話已停用');
    } catch (e) {
      print('VoicePlayerServiceV2 ($_messageId): 停止失敗: $e');
    }
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
        print('VoicePlayerServiceV2 ($_messageId): 跳轉到位置: ${position.inSeconds}s');
      }
    } catch (e) {
      print('VoicePlayerServiceV2 ($_messageId): 跳轉失敗: $e');
    }
  }

  // 🔥 新增：背景緩存方法
  void _startBackgroundCaching(String messageId, String audioUrl) {
    // 使用 Future.microtask 確保不阻塞播放
    Future.microtask(() async {
      try {
        print('VoicePlayerServiceV2: 🔄 開始背景緩存: $messageId');
        final cachedPath = await _downloadAndCacheAudio(messageId, audioUrl);
        if (cachedPath != null) {
          print('VoicePlayerServiceV2: ✅ 背景緩存完成: $cachedPath');
          // 可選：通知緩存完成
          _notifyCacheCompleted(messageId, cachedPath);
        } else {
          print('VoicePlayerServiceV2: ❌ 背景緩存失敗');
        }
      } catch (e) {
        print('VoicePlayerServiceV2: ❌ 背景緩存異常: $e');
      }
    });
  }

  // 🔥 新增：緩存完成通知（可選）
  void _notifyCacheCompleted(String messageId, String cachedPath) {
    print('VoicePlayerServiceV2: 📁 語音訊息 $messageId 已緩存到本地');
    // 未來可以添加緩存完成的回調或通知
  }

  // 🔥 改進：下載並快取音頻文件（加強錯誤處理）
  Future<String?> _downloadAndCacheAudio(String messageId, String audioUrl) async {
    try {
      print('VoicePlayerServiceV2: 📥 開始下載音頻文件: $audioUrl');

      final directory = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${directory.path}/voice_cache');

      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
        print('VoicePlayerServiceV2: 📁 創建緩存目錄: ${cacheDir.path}');
      }

      // 生成快取文件名
      final fileName = '${messageId}_${audioUrl.hashCode}.m4a'; // 🔥 改為 .m4a
      final cachedFile = File('${cacheDir.path}/$fileName');

      // 如果文件已存在，直接返回
      if (await cachedFile.exists()) {
        final fileSize = await cachedFile.length();
        print('VoicePlayerServiceV2: ✅ 快取文件已存在: ${cachedFile.path} (${fileSize} bytes)');
        return cachedFile.path;
      }

      // 🔥 改進：使用更好的下載配置
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 60);
      
      print('VoicePlayerServiceV2: 🌐 開始下載: $audioUrl -> ${cachedFile.path}');
      
      final response = await dio.download(
        audioUrl, 
        cachedFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total * 100).toStringAsFixed(1);
            print('VoicePlayerServiceV2: 📊 下載進度: $progress% ($received/$total bytes)');
          }
        },
      );

      if (response.statusCode == 200 && await cachedFile.exists()) {
        final fileSize = await cachedFile.length();
        print('VoicePlayerServiceV2: ✅ 音頻文件下載完成: ${cachedFile.path} (${fileSize} bytes)');
        return cachedFile.path;
      } else {
        print('VoicePlayerServiceV2: ❌ 下載失敗，狀態碼: ${response.statusCode}');
        // 清理可能的不完整文件
        if (await cachedFile.exists()) {
          await cachedFile.delete();
        }
        return null;
      }
    } catch (e) {
      print('VoicePlayerServiceV2: ❌ 下載音頻文件失敗: $e');
      
      // 清理可能的不完整文件
      try {
        final directory = await getApplicationDocumentsDirectory();
        final fileName = '${messageId}_${audioUrl.hashCode}.m4a';
        final cachedFile = File('${directory.path}/voice_cache/$fileName');
        if (await cachedFile.exists()) {
          await cachedFile.delete();
          print('VoicePlayerServiceV2: 🗑️ 清理不完整的緩存文件');
        }
      } catch (cleanupError) {
        print('VoicePlayerServiceV2: ⚠️ 清理文件失敗: $cleanupError');
      }
      
      return null;
    }
  }

  // 🔥 改進：檢查緩存文件是否存在（加強驗證）
  Future<String?> _getCachedFileIfExists(String messageId, String audioUrl) async {
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
          print('VoicePlayerServiceV2: ✅ 找到快取文件 (新): ${cachedFileNew.path} (${fileSize} bytes)');
          return cachedFileNew.path;
        } else {
          print('VoicePlayerServiceV2: ⚠️ 快取文件為空，刪除: ${cachedFileNew.path}');
          await cachedFileNew.delete();
        }
      }

      // 檢查舊格式
      if (await cachedFileOld.exists()) {
        final fileSize = await cachedFileOld.length();
        if (fileSize > 0) {
          print('VoicePlayerServiceV2: ✅ 找到快取文件 (舊): ${cachedFileOld.path} (${fileSize} bytes)');
          return cachedFileOld.path;
        } else {
          print('VoicePlayerServiceV2: ⚠️ 快取文件為空，刪除: ${cachedFileOld.path}');
          await cachedFileOld.delete();
        }
      }

      return null;
    } catch (e) {
      print('VoicePlayerServiceV2: ❌ 檢查快取文件失敗: $e');
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
          } catch (e) {
            print('VoicePlayerServiceV2: 無法讀取文件大小: ${file.path}');
          }
        }
      }

      print('VoicePlayerServiceV2: 📊 緩存統計 - 文件數: $fileCount, 總大小: ${(totalSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      return {
        'fileCount': fileCount,
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / 1024 / 1024).toStringAsFixed(2),
        'cachePath': cacheDir.path,
      };
    } catch (e) {
      print('VoicePlayerServiceV2: ❌ 獲取緩存統計失敗: $e');
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
        print('VoicePlayerServiceV2: 🗑️ 緩存已清理');
      }
    } catch (e) {
      print('VoicePlayerServiceV2: ❌ 清理緩存失敗: $e');
    }
  }

  /// 清理資源
  void dispose() {
    print('VoicePlayerServiceV2: 正在清理資源...');
    _player?.dispose();
    _player = null;
    _playingController.close();
    _positionController.close();
    _durationController.close();
    print('VoicePlayerServiceV2: 資源清理完畢');
  }
}
