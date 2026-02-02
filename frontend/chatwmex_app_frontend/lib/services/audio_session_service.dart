import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';

/// 音頻會話配置服務
class AudioSessionService {
  static final AudioSessionService _instance = AudioSessionService._internal();
  factory AudioSessionService() => _instance;
  AudioSessionService._internal();

  bool _isInitialized = false;
  AudioSession? _session;

  /// 初始化音頻會話
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      print('AudioSessionService: 開始初始化音頻會話');

      _session = await AudioSession.instance;

      // 配置音頻會話為錄音和播放模式
      await _configureAudioSession();

      // 設置中斷處理
      _setupInterruptionHandling();

      _isInitialized = true;
      print('AudioSessionService: 音頻會話初始化完成');
      return true;
    } catch (e) {
      print('AudioSessionService: 音頻會話初始化失敗: $e');
      return false;
    }
  }

  /// 配置音頻會話
  Future<void> _configureAudioSession() async {
    try {
      if (_session == null) return;

      print('AudioSessionService: 配置音頻會話');

      if (Platform.isIOS) {
        // iOS 配置：錄音和播放模式
        await _session!.configure(AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
                  AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        ));
        print('AudioSessionService: iOS 音頻會話配置完成');
      } else if (Platform.isAndroid) {
        // Android 配置：語音通信
        await _session!.configure(AudioSessionConfiguration(
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ));
        print('AudioSessionService: Android 音頻會話配置完成');
      }
    } catch (e) {
      print('AudioSessionService: 配置音頻會話失敗: $e');
    }
  }

  /// 設置中斷處理
  void _setupInterruptionHandling() {
    if (_session == null) return;

    try {
      // 監聽音頻中斷事件
      _session!.interruptionEventStream.listen((event) {
        print('AudioSessionService: 音頻中斷事件: ${event.type}');

        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              print('AudioSessionService: 其他應用開始播放音頻，應該降低音量');
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              print('AudioSessionService: 其他應用開始播放音頻，應該暫停');
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              print('AudioSessionService: 中斷結束，恢復音量');
              break;
            case AudioInterruptionType.pause:
              print('AudioSessionService: 中斷結束，恢復播放');
              break;
            case AudioInterruptionType.unknown:
              print('AudioSessionService: 中斷結束，但不恢復');
              break;
          }
        }
      });

      // 監聽耳機拔除事件
      _session!.becomingNoisyEventStream.listen((_) {
        print('AudioSessionService: 耳機被拔除，應該暫停或降低音量');
      });

      // 監聽設備變化事件
      _session!.devicesChangedEventStream.listen((event) {
        print('AudioSessionService: 音頻設備變化');
        print('  新增設備: ${event.devicesAdded}');
        print('  移除設備: ${event.devicesRemoved}');
      });

      print('AudioSessionService: 中斷處理設置完成');
    } catch (e) {
      print('AudioSessionService: 設置中斷處理失敗: $e');
    }
  }

  /// 激活音頻會話
  Future<bool> activate() async {
    try {
      if (_session == null) {
        print('AudioSessionService: 音頻會話未初始化');
        return false;
      }

      print('AudioSessionService: 激活音頻會話');
      final success = await _session!.setActive(true);

      if (success) {
        print('AudioSessionService: 音頻會話激活成功');
      } else {
        print('AudioSessionService: 音頻會話激活失敗');
      }

      return success;
    } catch (e) {
      print('AudioSessionService: 激活音頻會話失敗: $e');
      return false;
    }
  }

  /// 停用音頻會話
  Future<bool> deactivate() async {
    try {
      if (_session == null) {
        print('AudioSessionService: 音頻會話未初始化');
        return false;
      }

      print('AudioSessionService: 停用音頻會話');
      final success = await _session!.setActive(false);

      if (success) {
        print('AudioSessionService: 音頻會話停用成功');
      } else {
        print('AudioSessionService: 音頻會話停用失敗');
      }

      return success;
    } catch (e) {
      print('AudioSessionService: 停用音頻會話失敗: $e');
      return false;
    }
  }

  /// 檢查音頻會話狀態
  Future<bool> isActive() async {
    try {
      if (_session == null) return false;
      // 注意：audio_session 插件可能沒有 isActive 方法，這裡返回 true 表示已初始化
      return _isInitialized;
    } catch (e) {
      print('AudioSessionService: 檢查音頻會話狀態失敗: $e');
      return false;
    }
  }

  /// 獲取當前配置
  AudioSessionConfiguration? getCurrentConfiguration() {
    return _session?.configuration;
  }

  /// 重新配置音頻會話
  Future<void> reconfigure() async {
    try {
      print('AudioSessionService: 重新配置音頻會話');
      await _configureAudioSession();
    } catch (e) {
      print('AudioSessionService: 重新配置音頻會話失敗: $e');
    }
  }

  /// 檢查麥克風權限
  Future<bool> checkMicrophonePermission() async {
    try {
      // 使用 permission_handler 檢查麥克風權限
      final status = await Permission.microphone.status;
      print('AudioSessionService: 麥克風權限狀態: $status');
      return status.isGranted;
    } catch (e) {
      print('AudioSessionService: 檢查麥克風權限失敗: $e');
      return false;
    }
  }

  /// 請求麥克風權限
  Future<bool> requestMicrophonePermission() async {
    try {
      // 使用 permission_handler 請求麥克風權限
      final status = await Permission.microphone.request();
      print('AudioSessionService: 麥克風權限請求結果: $status');
      return status.isGranted;
    } catch (e) {
      print('AudioSessionService: 請求麥克風權限失敗: $e');
      return false;
    }
  }

  /// 清理資源
  void dispose() {
    _session = null;
    _isInitialized = false;
  }
}
