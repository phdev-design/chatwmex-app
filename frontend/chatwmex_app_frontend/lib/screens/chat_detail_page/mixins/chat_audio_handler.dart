import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../models/message.dart' as chat_msg;

/// 處理音頻播放和通知音效的 Mixin
mixin ChatAudioHandler<T extends StatefulWidget> on State<T> {
  late final AudioPlayer _notificationPlayer;
  bool _isNotificationSoundEnabled = true;
  DateTime? _lastNotificationTime;
  static const Duration _notificationCooldown = Duration(seconds: 2);

  // 需要在使用此 Mixin 的 State 中實現此 getter
  String? get currentUserId;

  /// 初始化音頻處理器
  void initializeAudioHandler() {
    _notificationPlayer = AudioPlayer();
    _notificationPlayer.setReleaseMode(ReleaseMode.stop);
    print("AudioHandler: Initialized.");
  }

  /// 釋放音頻資源
  void disposeAudioHandler() {
    _notificationPlayer.dispose();
    print("AudioHandler: Disposed.");
  }

  /// 播放新消息通知音效
  Future<void> playNotificationSound(chat_msg.Message lastReceivedMessage) async {
    if (!_isNotificationSoundEnabled) return;

    // 防抖：避免短時間內重複播放
    final now = DateTime.now();
    if (_lastNotificationTime != null && now.difference(_lastNotificationTime!) < _notificationCooldown) {
      return;
    }

    try {
      // 只為別人的消息播放聲音
      if (lastReceivedMessage.senderId != currentUserId) {
        await _notificationPlayer.play(
          AssetSource('audio/mixkit-long-pop-2358.wav'),
        );
        _lastNotificationTime = now;
        print('AudioHandler: Played notification sound.');
      }
    } catch (e) {
      print('AudioHandler: Failed to play notification sound: $e');
    }
  }

  /// 切換通知音效開關
  void toggleNotificationSound() {
    if (!mounted) return;
    setState(() {
      _isNotificationSoundEnabled = !_isNotificationSoundEnabled;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isNotificationSoundEnabled ? '通知聲音已開啟' : '通知聲音已關閉'),
        backgroundColor: _isNotificationSoundEnabled ? Colors.green : Colors.orange,
      ),
    );
  }
}
