// lib/pages/chat/widgets/chat_input_area.dart
import 'dart:async'; // 🔥 Add import for Timer
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../../../widgets/voice_recording_widget.dart';

/// 聊天輸入區域組件
class ChatInputArea extends StatefulWidget {
  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final bool isConnected;
  final bool isRecordingVoice;
  final VoidCallback onSendMessage;
  final ValueChanged<String> onTextChanged;
  final Future<void> Function(String, int) onVoiceRecordingComplete;
  final VoidCallback onVoiceRecordingCancelled;
  final ValueChanged<bool> onVoiceRecordingStateChanged;
  final Function(File, String) onMediaSelected; // 🔥 修改：支持文件和類型 (image/video)
  final VoidCallback? onTypingStart; // 🔥 新增：Typing 回調
  final VoidCallback? onTypingEnd; // 🔥 新增：Typing 回調

  const ChatInputArea({
    super.key,
    required this.messageController,
    required this.messageFocusNode,
    required this.isConnected,
    required this.isRecordingVoice,
    required this.onSendMessage,
    required this.onTextChanged,
    required this.onVoiceRecordingComplete,
    required this.onVoiceRecordingCancelled,
    required this.onVoiceRecordingStateChanged,
    required this.onMediaSelected,
    this.onTypingStart,
    this.onTypingEnd,
  });

  @override
  State<ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<ChatInputArea> {
  bool _hasText = false;
  final ImagePicker _picker = ImagePicker();

  // 🔥 預覽相關狀態
  File? _selectedMedia;
  String? _mediaType; // 'image' or 'video'
  VideoPlayerController? _videoController;

  // 🔥 Typing logic
  Timer? _typingDebounceTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    widget.messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.messageController.removeListener(_onTextChanged);
    _videoController?.dispose();
    _typingDebounceTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.messageController.text;
    final hasText = text.trim().isNotEmpty;

    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }

    // Typing logic
    if (text.isNotEmpty) {
      if (!_isTyping) {
        _isTyping = true;
        widget.onTypingStart?.call();
      }

      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
        if (_isTyping) {
          _isTyping = false;
          widget.onTypingEnd?.call();
        }
      });
    } else if (_isTyping) {
      _isTyping = false;
      _typingDebounceTimer?.cancel();
      widget.onTypingEnd?.call();
    }

    widget.onTextChanged(text);
  }

  Future<void> _pickMedia() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image =
                    await _picker.pickImage(source: ImageSource.camera);
                if (image != null) {
                  _setMedia(File(image.path), 'image');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('選擇圖片'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image =
                    await _picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  _setMedia(File(image.path), 'image');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('拍攝視頻'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? video = await _picker.pickVideo(
                  source: ImageSource.camera,
                  maxDuration: const Duration(minutes: 1),
                );
                if (video != null) {
                  _setMedia(File(video.path), 'video');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('選擇視頻'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? video =
                    await _picker.pickVideo(source: ImageSource.gallery);
                if (video != null) {
                  _setMedia(File(video.path), 'video');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _setMedia(File file, String type) {
    setState(() {
      _selectedMedia = file;
      _mediaType = type;
    });

    if (type == 'video') {
      _videoController?.dispose();
      _videoController = VideoPlayerController.file(file)
        ..initialize().then((_) {
          setState(() {}); // 刷新 UI 以顯示第一幀
        });
    }
  }

  void _clearMedia() {
    setState(() {
      _selectedMedia = null;
      _mediaType = null;
      _videoController?.dispose();
      _videoController = null;
    });
  }

  void _handleSend() {
    if (!widget.isConnected) return;

    // 發送文本
    if (_hasText) {
      widget.onSendMessage();
    }

    // 發送媒體
    if (_selectedMedia != null && _mediaType != null) {
      widget.onMediaSelected(_selectedMedia!, _mediaType!);
      _clearMedia();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedMedia != null) _buildMediaPreview(),
            VoiceRecordingWidget(
              onRecordingComplete: widget.onVoiceRecordingComplete,
              onRecordingCancelled: widget.onVoiceRecordingCancelled,
              onRecordingStateChanged: widget.onVoiceRecordingStateChanged,
              showMicButton:
                  !_hasText && _selectedMedia == null, // 如果有媒體選中，顯示發送按鈕而不是麥克風
              inputWidget: _buildInputRow(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 60,
              height: 60,
              child: _mediaType == 'video'
                  ? (_videoController != null &&
                          _videoController!.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        )
                      : const Center(child: CircularProgressIndicator()))
                  : Image.file(_selectedMedia!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _mediaType == 'video' ? '已選擇視頻' : '已選擇圖片',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  '${(_selectedMedia!.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _clearMedia,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    final canSend = widget.isConnected && (_hasText || _selectedMedia != null);

    return Row(
      children: [
        // 附件按鈕
        if (!widget.isRecordingVoice)
          IconButton(
            onPressed: _pickMedia,
            icon: Icon(
              Icons.add_photo_alternate,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),

        // 文本輸入框
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: widget.messageController,
              focusNode: widget.messageFocusNode,
              decoration: const InputDecoration(
                hintText: 'Message...',
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              enabled: true,
              onTap: () {
                if (!widget.messageFocusNode.hasFocus) {
                  widget.messageFocusNode.requestFocus();
                }
              },
              onSubmitted: (_) {
                if (!widget.isRecordingVoice) {
                  _handleSend();
                }
              },
            ),
          ),
        ),

        const SizedBox(width: 8),

        // 🔥 发送按钮
        if ((_hasText || _selectedMedia != null) && !widget.isRecordingVoice)
          Container(
            decoration: BoxDecoration(
              color: canSend
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: canSend ? _handleSend : null,
              icon: const Icon(Icons.send, color: Colors.white),
            ),
          ),
      ],
    );
  }
}
