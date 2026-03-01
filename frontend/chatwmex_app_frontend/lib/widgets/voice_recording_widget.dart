import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/voice_recording_service.dart';

class VoiceRecordingWidget extends StatefulWidget {
  final Function(String filePath, int durationSeconds) onRecordingComplete;
  final VoidCallback? onRecordingCancelled;
  final Function(bool isRecording)? onRecordingStateChanged;
  final Widget inputWidget;
  final bool showMicButton; // 🔥 新增：是否显示麦克风按钮

  const VoiceRecordingWidget({
    super.key,
    required this.onRecordingComplete,
    this.onRecordingCancelled,
    this.onRecordingStateChanged,
    required this.inputWidget,
    this.showMicButton = true, // 🔥 默认显示
  });

  @override
  State<VoiceRecordingWidget> createState() => _VoiceRecordingWidgetState();
}

class _VoiceRecordingWidgetState extends State<VoiceRecordingWidget>
    with TickerProviderStateMixin {
  final VoiceRecordingService _recordingService = VoiceRecordingService();
  bool _isRecording = false;
  bool _isInitializingRecording = false;
  Duration _recordingDuration = Duration.zero;
  StreamSubscription<Duration>? _durationSubscription;
  bool _keyboardWasVisible = false;
  
  // 動畫控制器
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late AnimationController _cancelArrowController;
  late Animation<Offset> _cancelArrowAnimation;

  // 手勢相關
  double _dragOffset = 0.0;
  bool _shouldCancelOnRelease = false;
  static const double _cancelThreshold = 80.0;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _cancelArrowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _cancelArrowAnimation =
        Tween<Offset>(begin: const Offset(-0.2, 0), end: const Offset(0.2, 0))
            .animate(CurvedAnimation(
                parent: _cancelArrowController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    _cancelArrowController.dispose();
    _durationSubscription?.cancel();
    if (_isRecording) {
      _recordingService.cancelRecording();
    }
    super.dispose();
  }

  bool _isKeyboardVisible() {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return viewInsets.bottom > 0;
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isInitializingRecording) return;
    if (!mounted) return;

    _keyboardWasVisible = _isKeyboardVisible();
    
    if (_keyboardWasVisible) {
    } else {
      FocusScope.of(context).unfocus();
    }

    setState(() {
      _isInitializingRecording = true;
    });
    HapticFeedback.mediumImpact();

    try {
      await _recordingService.startRecording();
      if (!mounted) return;

      setState(() {
        _isRecording = true;
        _isInitializingRecording = false;
        _recordingDuration = Duration.zero;
        _dragOffset = 0.0;
        _shouldCancelOnRelease = false;
      });

      widget.onRecordingStateChanged?.call(true);

      _pulseController.repeat(reverse: true);
      _slideController.forward();
      _cancelArrowController.repeat(reverse: true);

      _durationSubscription =
          _recordingService.recordingDuration?.listen((duration) {
        if (mounted) {
          setState(() {
            _recordingDuration = duration;
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializingRecording = false;
      });
      _showPermissionError(e.toString());
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;

    final result = await _recordingService.stopRecording();
    _resetStateAfterRecording();

    if (result != null && result.duration.inSeconds >= 1) {
      HapticFeedback.lightImpact();
      widget.onRecordingComplete(
        result.filePath,
        result.duration.inSeconds,
      );
    } else {
      _handleRecordingCancel(showSnackbar: true);
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    HapticFeedback.lightImpact();
    await _recordingService.cancelRecording();
    _resetStateAfterRecording();
    _handleRecordingCancel(showSnackbar: false);
  }

  void _resetStateAfterRecording() {
    _pulseController.stop();
    _slideController.reverse();
    _cancelArrowController.stop();
    _durationSubscription?.cancel();

    setState(() {
      _isRecording = false;
      _recordingDuration = Duration.zero;
      _dragOffset = 0.0;
      _shouldCancelOnRelease = false;
    });

    widget.onRecordingStateChanged?.call(false);

    if (_keyboardWasVisible) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    } else {
    }
  }

  void _handleRecordingCancel({bool showSnackbar = false}) {
    widget.onRecordingCancelled?.call();
    if (showSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('錄音已取消'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isRecording) return;

    final newOffset = _dragOffset + event.delta.dx;

    setState(() {
      _dragOffset = newOffset.clamp(-double.infinity, 0.0);
    });

    final wasInCancelZone = _shouldCancelOnRelease;
    _shouldCancelOnRelease = _dragOffset.abs() > _cancelThreshold;

    if (_shouldCancelOnRelease != wasInCancelZone) {
      HapticFeedback.mediumImpact();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_isRecording) return;
    if (_shouldCancelOnRelease) {
      _cancelRecording();
    } else {
      _stopAndSendRecording();
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildMicrophoneButton() {
    return GestureDetector(
      onTap: !_isRecording
          ? () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('長按即可錄音'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary,
        ),
        child: _isInitializingRecording
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(
                Icons.mic,
                color: Colors.white,
                size: 24,
              ),
      ),
    );
  }

  Widget _buildRecordingOverlay() {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
      child: SlideTransition(
        position: _slideAnimation,
        child: Transform.translate(
          offset: Offset(_dragOffset, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    FadeTransition(
                      opacity: _pulseController,
                      child: const Icon(Icons.mic, color: Colors.red, size: 28),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(_recordingDuration),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                SlideTransition(
                  position: _cancelArrowAnimation,
                  child: Row(
                    children: [
                      const Icon(Icons.chevron_left, color: Colors.grey, size: 20),
                      Text('滑動以取消', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCancelIcon() {
    final isVisible = _shouldCancelOnRelease;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isVisible ? 1.0 : 0.0,
      child: const Icon(Icons.delete_outline, color: Colors.red, size: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: (_) => _cancelRecording(),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 底層：正常的輸入框和按鈕
          Row(
            children: [
              Expanded(
                child: AbsorbPointer(
                  absorbing: _isRecording,
                  child: widget.inputWidget,
                ),
              ),
              const SizedBox(width: 8),
              // 🔥 修改：只在 showMicButton 为 true 时显示麦克风按钮
              if (widget.showMicButton)
                Listener(
                  onPointerDown: (_) => _startRecording(),
                  child: _buildMicrophoneButton(),
                ),
            ],
          ),

          // 疊加層：錄音中的 UI
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 16,
                      child: _buildCancelIcon(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: _isRecording ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !_isRecording,
                          child: _buildRecordingOverlay(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showPermissionError(String error) {
    if (error.contains('永久拒絕')) {
      _showOpenSettingsDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('無法開始錄音，請檢查麥克風權限'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要麥克風權限'),
        content: const Text('您已永久拒絕麥克風權限。為了錄製語音，請前往您手機的「設定」頁面，找到本應用程式並手動開啟麥克風權限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
