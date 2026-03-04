import 'dart:async';
import 'dart:io';

import 'package:app/core/media/media_service.dart';
import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:app/models/message.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class ChatInputBar extends ConsumerStatefulWidget {
  final ChatRoomParams params;
  final bool isRoom;
  final String title;
  final String currentUserId;

  const ChatInputBar({
    super.key,
    required this.params,
    required this.isRoom,
    required this.title,
    required this.currentUserId,
  });

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  late final AnimationController _recordingBlinkController;
  late final Animation<double> _recordingOpacity;
  String? _lastReplyMessageId;

  @override
  void initState() {
    super.initState();
    _recordingBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _recordingOpacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _recordingBlinkController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _recordingBlinkController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatRoomProvider(widget.params));
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: Theme.of(context).brightness,
    );
    final replying = state.replyingToMessage;
    if (replying != null && replying.id != _lastReplyMessageId) {
      _lastReplyMessageId = replying.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
    if (replying == null) {
      _lastReplyMessageId = null;
    }

    return SafeArea(
      child: Column(
        children: [
          if (replying != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tokens.replyBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _resolveReplySenderName(replying),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.bubbleText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          replying.type == MessageType.image
                              ? '[圖片]'
                              : replying.content,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.subtleText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => ref
                        .read(chatRoomProvider(widget.params).notifier)
                        .setReplyingTo(null),
                  ),
                ],
              ),
            ),
          Container(
            color: tokens.panelBackground,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add),
                  color: tokens.subtleText,
                  onPressed: _showAttachmentMenu,
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.composerBackground,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: state.isRecording
                        ? Row(
                            children: [
                              FadeTransition(
                                opacity: _recordingOpacity,
                                child: Text(
                                  '🔴 正在錄音... 鬆開以送出',
                                  style: TextStyle(
                                    color: tokens.bubbleText,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatRecordingTime(_recordingSeconds),
                                style: TextStyle(
                                  color: tokens.subtleText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            style: TextStyle(color: tokens.bubbleText),
                            decoration: InputDecoration(
                              hintText: '輸入訊息',
                              hintStyle: TextStyle(color: tokens.subtleText),
                              border: InputBorder.none,
                              isDense: true,
                              suffixIcon: Icon(
                                Icons.emoji_emotions_outlined,
                                color: tokens.subtleText,
                              ),
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 24,
                              ),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                            onChanged: (_) {
                              ref
                                  .read(
                                    chatRoomProvider(widget.params).notifier,
                                  )
                                  .startTyping();
                            },
                          ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, value, child) {
                    final isComposing = value.text.trim().isNotEmpty;
                    if (isComposing) {
                      return IconButton(
                        icon: const Icon(Icons.send),
                        color: tokens.accent,
                        onPressed: _sendMessage,
                      );
                    }
                    return GestureDetector(
                      onLongPressStart: (_) {
                        HapticFeedback.mediumImpact();
                        _recordingTimer?.cancel();
                        setState(() => _recordingSeconds = 0);
                        _recordingTimer = Timer.periodic(
                          const Duration(seconds: 1),
                          (_) {
                            if (!mounted) return;
                            setState(() => _recordingSeconds += 1);
                          },
                        );
                        ref
                            .read(chatRoomProvider(widget.params).notifier)
                            .startRecording();
                      },
                      onLongPressEnd: (_) {
                        HapticFeedback.lightImpact();
                        _recordingTimer?.cancel();
                        setState(() => _recordingSeconds = 0);
                        ref
                            .read(chatRoomProvider(widget.params).notifier)
                            .stopRecordingAndSend();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          Icons.mic,
                          color: state.isRecording
                              ? tokens.accent
                              : tokens.subtleText,
                          size: 26,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      ref.read(chatRoomProvider(widget.params).notifier).sendMessage(text);
      _textController.clear();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final mediaService = ref.read(mediaServiceProvider);
    final file = await mediaService.pickImage(source);
    if (file != null) {
      ref
          .read(chatRoomProvider(widget.params).notifier)
          .sendMedia(file, MessageType.image);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    ref.read(chatRoomProvider(widget.params).notifier).sendDocument(File(path));
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final menuTokens = resolveChatSurfaceTokens(
          colorScheme: Theme.of(context).colorScheme,
          brightness: Theme.of(context).brightness,
        );
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: menuTokens.menuBackground,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAttachmentOption(
                icon: Icons.camera_alt,
                color: const Color(0xFFD3396D),
                label: '相機',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              _buildAttachmentOption(
                icon: Icons.photo,
                color: const Color(0xFFAC44CF),
                label: '圖庫',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              _buildAttachmentOption(
                icon: Icons.insert_drive_file,
                color: const Color(0xFF5157AE),
                label: '文件',
                onTap: () {
                  Navigator.pop(context);
                  _pickDocument();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  String _resolveReplySenderName(Message replyMessage) {
    if (replyMessage.senderId == widget.currentUserId) {
      return '你';
    }
    if (!widget.isRoom && widget.title.isNotEmpty) {
      return widget.title;
    }
    return '回覆訊息';
  }

  String _formatRecordingTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remain = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remain';
  }
}
