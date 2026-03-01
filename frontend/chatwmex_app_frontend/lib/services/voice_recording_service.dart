// lib/services/voice_recording_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'audio_session_service.dart'; // 🔥 新增：音頻會話服務

class VoiceRecordingService {
  static final VoiceRecordingService _instance =
      VoiceRecordingService._internal();
  factory VoiceRecordingService() => _instance;
  VoiceRecordingService._internal();

  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  bool _isInitialized = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  StreamController<Duration>? _durationController;

  bool get isRecording => _isRecording;
  Stream<Duration>? get recordingDuration => _durationController?.stream;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
      _isInitialized = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  // 🔥 關鍵修改：使用 audio_session 檢查並請求麥克風權限
  Future<PermissionStatus> checkAndRequestPermissions() async {
    try {
      // 使用 audio_session 檢查麥克風權限
      final audioSession = AudioSessionService();
      final hasPermission = await audioSession.checkMicrophonePermission();

      if (hasPermission) {
        return PermissionStatus.granted;
      }

      // 如果沒有權限，則請求權限
      final granted = await audioSession.requestMicrophonePermission();

      if (granted) {
        return PermissionStatus.granted;
      } else {
        return PermissionStatus.denied;
      }
    } catch (e) {
      return PermissionStatus.denied;
    }
  }

  Future<void> startRecording() async {
    // 🔥 新增：開始新錄音前先清理舊狀態
    if (_isRecording) {
      await cancelRecording();
    }
   
    // 🔥 新增：確保完全清理
    _cleanup();

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) throw Exception('錄音服務初始化失敗');
    }

    final permissionStatus = await checkAndRequestPermissions();
    if (permissionStatus != PermissionStatus.granted) {
      throw Exception('麥克風權限未授予');
    }

    try {
      // 🔥 新增：激活音頻會話
      final audioSession = AudioSessionService();
      final sessionActivated = await audioSession.activate();
      if (!sessionActivated) {
        throw Exception('音頻會話激活失敗');
      }

      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final filePath = path.join(directory.path, fileName);
      _currentRecordingPath = filePath;

      await _recorder!.startRecorder(
        toFile: filePath,
        codec: Codec.aacMP4,
      );

      _isRecording = true;
      _recordingStartTime = DateTime.now(); // 🔥 重要：重新設置開始時間

      // 🔥 新增：確保創建新的計時器
      _durationController?.close(); // 先關閉舊的
      _recordingTimer?.cancel(); // 取消舊的計時器
      
      _durationController = StreamController<Duration>.broadcast();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_recordingStartTime != null && _isRecording) {
          final duration = DateTime.now().difference(_recordingStartTime!);
          _durationController?.add(duration);
        }
      });
    } catch (e) {
      _cleanup(); // 🔥 新增：發生錯誤時清理
      rethrow;
    }
  }

  Future<RecordingResult?> stopRecording() async {
    if (!_isRecording || _recorder == null) return null;

    try {
      await _recorder!.stopRecorder();
      final recordPath = _currentRecordingPath;
      if (recordPath == null) throw Exception('錄音文件路徑無效');

      final file = File(recordPath);
      if (!await file.exists()) throw Exception('錄音文件不存在');

      final fileSize = await file.length();
      if (fileSize == 0) {
        await file.delete();
        _cleanup(); // 🔥 新增：清理狀態
        return null;
      }

      final duration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!)
          : Duration.zero;
      
      final result = RecordingResult(
          filePath: recordPath, duration: duration, fileSize: fileSize);
      
      // 🔥 關鍵修復：成功完成錄音後也要清理狀態
      _cleanup();
      
      return result;
    } catch (e) {
      _cleanup();
      return null;
    }
  }

  Future<void> cancelRecording() async {
    if (!_isRecording || _recorder == null) return;

    try {
      await _recorder!.stopRecorder();

      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
    } finally {
      _cleanup();
    }
  }

  void _cleanup() {
    _isRecording = false;
    _recordingStartTime = null;
    _currentRecordingPath = null;
    
    // 🔥 改進：更安全的計時器清理
    if (_recordingTimer != null) {
      _recordingTimer!.cancel();
      _recordingTimer = null;
    }
    
    // 🔥 改進：更安全的 StreamController 清理
    if (_durationController != null) {
      _durationController!.close();
      _durationController = null;
    }
  }

  Future<void> dispose() async {
    try {
      if (_recorder != null) {
        await _recorder!.closeRecorder();
        _recorder = null;
      }
      _isInitialized = false;
      _cleanup();
    } catch (e) {
    }
  }
}

class RecordingResult {
  final String filePath;
  final Duration duration;
  final int fileSize;

  RecordingResult({
    required this.filePath,
    required this.duration,
    required this.fileSize,
  });

  @override
  String toString() {
    return 'RecordingResult(filePath: $filePath, duration: ${duration.inSeconds}s, fileSize: ${fileSize}bytes)';
  }
}
