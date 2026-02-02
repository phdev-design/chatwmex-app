import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dio/dio.dart'; // 🔥 新增：用於網路請求

import '../services/voice_player_service_v2.dart'; // 🔥 更新：使用新的 just_audio 服務
import '../models/voice_message.dart';
import '../config/api_config.dart'; // 🔥 修正：導入獨立的 ApiConfig 檔案

class VoiceMessageWidget extends StatefulWidget {
  final VoiceMessage voiceMessage;
  final bool isFromCurrentUser;
  final String? senderAvatarUrl; // 🔥 新增：發送者頭像URL
  final String? currentUserAvatarUrl; // 🔥 新增：當前用戶頭像URL

  const VoiceMessageWidget({
    super.key,
    required this.voiceMessage,
    required this.isFromCurrentUser,
    this.senderAvatarUrl, // 🔥 新增：可選的頭像URL
    this.currentUserAvatarUrl, // 🔥 新增：可選的當前用戶頭像URL
  });

  @override
  State<VoiceMessageWidget> createState() => _VoiceMessageWidgetState();
}

class _VoiceMessageWidgetState extends State<VoiceMessageWidget>
    with TickerProviderStateMixin {
  late final VoicePlayerServiceV2 _playerService;

  bool _isPlaying = false;
  bool _isPaused = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;

  // 添加一個標記來追蹤是否已經 disposed
  bool _isDisposed = false;

  late AnimationController _waveController;
  late List<AnimationController> _waveBarControllers;

  String? _playableAudioUrl; // 若為本地路徑，仍存放於此
  String? _localFilePath; // 本地臨時檔路徑（上傳期間）
  bool _isLoadingUrl = true;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _playerService = VoicePlayerServiceV2();
    _totalDuration = Duration(seconds: widget.voiceMessage.duration);

    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _waveBarControllers = List.generate(
        5,
        (index) => AnimationController(
              duration: Duration(milliseconds: 300 + (index * 100)),
              vsync: this,
            ));

    _setupPlayerListeners();
    _prepareAudioUrl();
  }

  @override
  void dispose() {
    // 設置標記，表示此 widget 正在被銷毀
    _isDisposed = true;

    // 依序取消訂閱
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();

    // 清理播放器服務
    _playerService.dispose();

    // 清理動畫控制器
    _waveController.dispose();
    for (final controller in _waveBarControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  // lib/widgets/voice_message_widget.dart - _prepareAudioUrl 方法的修正版本
  Future<void> _prepareAudioUrl() async {
    if (_isDisposed || !mounted) return;

    setState(() {
      _isLoadingUrl = true;
      _urlError = null;
    });

    try {
      print('VoiceMessageWidget (${widget.voiceMessage.id}): 準備音訊 URL');
      print('VoiceMessageWidget: 原始 fileUrl - ${widget.voiceMessage.fileUrl}');

      // 如果 fileUrl 是本地檔路徑（例如以 /data/ 開頭），直接使用本地播放
      if (widget.voiceMessage.fileUrl.startsWith('/')) {
        _localFilePath = widget.voiceMessage.fileUrl;
        _playableAudioUrl = null; // 本地播放不需 URL
        if (!_isDisposed && mounted) {
          setState(() {
            _isLoadingUrl = false;
          });
        }
        return;
      }

      // 🔥 关键修正：使用 ApiConfig 来构造正确的 URL
      String audioUrl;

      if (widget.voiceMessage.fileUrl.startsWith('http')) {
        // 如果已经是完整 URL，直接使用
        audioUrl = widget.voiceMessage.fileUrl;
        print('VoiceMessageWidget: 使用完整 HTTP URL: $audioUrl');
      } else {
        // 🔥 使用 ApiConfig 构造完整 URL
        audioUrl = ApiConfig.getAudioFileUrl(widget.voiceMessage.fileUrl);
        print('VoiceMessageWidget: 构造完整 URL: $audioUrl');
      }

      // 🔥 新增：URL 有效性验证
      if (!_isValidAudioUrl(audioUrl)) {
        throw Exception('音频 URL 格式无效: $audioUrl');
      }

      _playableAudioUrl = audioUrl;

      if (!_isDisposed && mounted) {
        setState(() {
          _isLoadingUrl = false;
        });
      }

      // 🔥 新增：預抓快取（背景），並嘗試 HEAD 驗證
      // 預取語音文件（just_audio 會自動處理）
      print('VoiceMessageWidget: 預取語音文件: $audioUrl');
      await _validateAudioAccess(audioUrl);
    } catch (e) {
      print('VoiceMessageWidget (${widget.voiceMessage.id}): 準備 URL 失敗: $e');
      if (!_isDisposed && mounted) {
        setState(() {
          _isLoadingUrl = false;
          _urlError = '無法載入音訊: ${e.toString()}';
        });
      }
    }
  }

  // 🔥 新增：URL 有效性检查
  bool _isValidAudioUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }

  // 🔥 新增：预检查音频文件访问性
  Future<void> _validateAudioAccess(String url) async {
    try {
      final dio = Dio();
      final response = await dio.head(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('音频文件不可访问，状态码: ${response.statusCode}');
      }

      print('VoiceMessageWidget: 音频文件可访问，状态码: ${response.statusCode}');
    } catch (e) {
      print('VoiceMessageWidget: 音频文件访问检查失败: $e');
      // 注意：这里不抛出异常，因为某些服务器可能不支持 HEAD 请求
      // 让实际播放时再处理错误
    }
  }

  void _setupPlayerListeners() {
    // 監聽播放位置
    _positionSubscription = _playerService.positionStream.listen((position) {
      // 🔥 修正：添加 disposed 檢查，避免在銷毀後更新狀態
      if (!_isDisposed && mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });

    // 監聽播放狀態
    _playingSubscription = _playerService.playingStream.listen((isPlaying) {
      // 🔥 修正：添加 disposed 檢查
      if (!_isDisposed && mounted) {
        setState(() {
          _isPlaying = isPlaying;
          _isPaused = !isPlaying && _playerService.isPaused;
        });

        // 控制動畫
        if (isPlaying) {
          _waveController.repeat();
          for (final controller in _waveBarControllers) {
            controller.repeat(reverse: true);
          }
        } else {
          _waveController.stop();
          for (final controller in _waveBarControllers) {
            controller.stop();
          }
        }
      }
    });
  }

  Future<void> _togglePlayPause() async {
    if (_isDisposed || !mounted) return; // 添加檢查

    if (_isLoadingUrl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('正在準備音訊...'), duration: Duration(seconds: 1)),
      );
      return;
    }

    if (_urlError != null || _playableAudioUrl == null) {
      if (mounted) {
        // mounted 檢查
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_urlError ?? '音訊 URL 無效'),
              backgroundColor: Colors.red),
        );
      }
      await _prepareAudioUrl();
      return;
    }

    try {
      if (_isPlaying) {
        await _playerService.pauseVoice();
      } else if (_isPaused) {
        await _playerService.resumeVoice();
      } else {
        // 如果播放器已停止，直接播放（播放服務會處理重置）
        print('VoiceMessageWidget (${widget.voiceMessage.id}): 開始新的播放');
        if (_localFilePath != null) {
          print(
              'VoiceMessageWidget (${widget.voiceMessage.id}): 開始播放本地音訊: $_localFilePath');
          final success = await _playerService.playVoice(
            widget.voiceMessage.id,
            _localFilePath!,
            fileSize: widget.voiceMessage.fileSize,
          );
          if (!success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('播放失敗，請重試'), backgroundColor: Colors.red),
            );
          }
          return;
        }

        print(
            'VoiceMessageWidget (${widget.voiceMessage.id}): 開始播放音訊: $_playableAudioUrl');
        final success = await _playerService.playVoice(
          widget.voiceMessage.id,
          _playableAudioUrl!,
          fileSize: widget.voiceMessage.fileSize,
        );

        if (!success && mounted) {
          // mounted 檢查
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('播放失敗，請重試'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      print('VoiceMessageWidget (${widget.voiceMessage.id}): 播放操作失敗: $e');
      if (mounted) {
        // mounted 檢查
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0KB';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return '昨天 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildWaveform() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return AnimatedBuilder(
          animation: _waveBarControllers[index],
          builder: (context, child) {
            final isPlaying = _isPlaying;
            final height = isPlaying
                ? 16.0 + (8.0 * _waveBarControllers[index].value)
                : 4.0 + (index * 2.0);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 3,
              height: height,
              decoration: BoxDecoration(
                color: widget.isFromCurrentUser
                    ? Colors.white.withOpacity(0.8)
                    : Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          },
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_totalDuration.inMilliseconds > 0 &&
            _currentPosition.inMilliseconds <= _totalDuration.inMilliseconds)
        ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds
        : 0.0;

    // 🔥 新增：頭像顯示邏輯
    final avatarUrl = widget.isFromCurrentUser
        ? widget.currentUserAvatarUrl
        : widget.senderAvatarUrl;

    final senderName =
        widget.isFromCurrentUser ? '我' : widget.voiceMessage.senderName;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280, minWidth: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.isFromCurrentUser
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(widget.isFromCurrentUser ? 16 : 4),
          bottomRight: Radius.circular(widget.isFromCurrentUser ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 🔥 新增：用戶頭像（放在左側）
              _buildAvatar(avatarUrl, senderName),

              const SizedBox(width: 8),

              // 播放/暫停按鈕
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isFromCurrentUser
                      ? Colors.white.withOpacity(0.2)
                      : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _togglePlayPause,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _isLoadingUrl
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  widget.isFromCurrentUser
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            )
                          : Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: widget.isFromCurrentUser
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 波形和進度條
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_urlError == null && !_isLoadingUrl) {
                      _togglePlayPause();
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 32,
                        alignment: Alignment.center,
                        child: _urlError != null
                            ? Text(
                                '音訊載入失敗',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.red),
                              )
                            : _buildWaveform(),
                      ),

                      const SizedBox(height: 4),

                      // 進度條
                      LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        backgroundColor: widget.isFromCurrentUser
                            ? Colors.white.withOpacity(0.3)
                            : Theme.of(context)
                                .colorScheme
                                .outline
                                .withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.isFromCurrentUser
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                        ),
                        minHeight: 2,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 時長顯示
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    !_isPlaying && !_isPaused
                        ? _formatDuration(_totalDuration)
                        : _formatDuration(_currentPosition),
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.isFromCurrentUser
                          ? Colors.white.withOpacity(0.9)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                    ),
                  ),
                  Text(
                    _formatFileSize(widget.voiceMessage.fileSize),
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isFromCurrentUser
                          ? Colors.white.withOpacity(0.7)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 時間戳
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                _formatMessageTime(widget.voiceMessage.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: widget.isFromCurrentUser
                      ? Colors.white.withOpacity(0.7)
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🔥 新增：構建頭像組件
  Widget _buildAvatar(String? avatarUrl, String senderName) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.isFromCurrentUser
            ? Colors.white.withOpacity(0.2)
            : _getAvatarColor(senderName),
        border: Border.all(
          color: widget.isFromCurrentUser
              ? Colors.white.withOpacity(0.3)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? ClipOval(
              child: Image.network(
                avatarUrl,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      _getUserInitials(senderName),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            )
          : Center(
              child: Text(
                _getUserInitials(senderName),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }

  // 🔥 新增：獲取用戶名首字母
  String _getUserInitials(String name) {
    if (name.isEmpty) return '?';
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }

  // 🔥 新增：根據用戶名生成頭像顏色
  Color _getAvatarColor(String name) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];
    final hash = name.hashCode.abs();
    return colors[hash % colors.length];
  }
}
