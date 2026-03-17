import 'dart:async';
import 'dart:io';

import 'package:app/core/media/media_service.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:app/models/message.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class LinkPreviewData {
  final String url;
  final String title;
  final String description;
  final String? imageUrl;

  const LinkPreviewData({
    required this.url,
    required this.title,
    required this.description,
    this.imageUrl,
  });
}

class ChatInputBar extends ConsumerStatefulWidget {
  final ChatRoomParams params;
  final bool isRoom;
  final String title;
  final String currentUserId;
  final bool isMember;

  const ChatInputBar({
    super.key,
    required this.params,
    required this.isRoom,
    required this.title,
    required this.currentUserId,
    this.isMember = true,
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
  Timer? _debounceTimer;
  String? _detectedUrl;
  bool _isLoadingPreview = false;
  LinkPreviewData? _previewData;
  bool _isUrlPreviewCancelled = false;
  
  // Gesture tracking state for slide-to-cancel
  Offset? _recordingStartPosition;
  Offset? _currentDragPosition;
  bool _isCancelThresholdReached = false;
  
  // Constants for gesture detection
  static const double _cancelThreshold = 100.0; // pixels
  static const Duration _minRecordingDuration = Duration(seconds: 1);

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
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatRoomProvider(widget.params));
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    if (widget.isRoom && !widget.isMember) {
      return SafeArea(
        child: Container(
          width: double.infinity,
          color: tokens.panelBackground,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Text(
            '您已無法在此群組傳送訊息，或此群組已解散。',
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.subtleText, fontSize: 14),
          ),
        ),
      );
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
          if (_detectedUrl != null && !_isUrlPreviewCancelled)
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
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: tokens.composerBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isLoadingPreview
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : ((_previewData?.imageUrl ?? '').isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _previewData!.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) => Icon(
                                          Icons.link,
                                          color: tokens.subtleText,
                                        ),
                                  ),
                                )
                              : Icon(Icons.link, color: tokens.subtleText)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _previewData?.title ?? _detectedUrl!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.bubbleText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _previewData?.description ?? _detectedUrl!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.subtleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _isUrlPreviewCancelled = true;
                        _isLoadingPreview = false;
                        _previewData = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment button
                GestureDetector(
                  onTap: _showAttachmentMenu,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8, right: 4),
                    child: Icon(
                      Icons.add_circle_outline_rounded,
                      size: 26,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                ),
                // Pill text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFF0F2F5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: state.isRecording
                        ? Row(
                            children: [
                              if (_isCancelThresholdReached)
                                Text(
                                  '🚫 鬆開取消',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              else
                                FadeTransition(
                                  opacity: _recordingOpacity,
                                  child: Text(
                                    '🔴 正在錄音... ← 滑動取消',
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
                        : Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _textController,
                                  focusNode: _focusNode,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 15,
                                  ),
                                  maxLines: 5,
                                  minLines: 1,
                                  decoration: InputDecoration(
                                    hintText: '輸入訊息...',
                                    hintStyle: TextStyle(
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.grey[500],
                                      fontSize: 15,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                  onChanged: _onTextChanged,
                                ),
                              ),
                              Icon(
                                Icons.emoji_emotions_outlined,
                                size: 20,
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey[500],
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // Send / Mic button
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, value, child) {
                    final isComposing = value.text.trim().isNotEmpty;
                    if (isComposing) {
                      return GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: tokens.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      );
                    }
                    return GestureDetector(
                      onLongPressStart: (details) async {
                        // Capture context before async operations
                        final messenger = ScaffoldMessenger.of(context);
                        
                        // Check permissions first (request if not yet granted)
                        final mediaService = ref.read(mediaServiceProvider);
                        final hasPermission = await mediaService.hasMicrophonePermission();
                        
                        if (!hasPermission) {
                          HapticFeedback.heavyImpact();
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text('需要麥克風權限才能錄音'),
                              action: SnackBarAction(
                                label: '設定',
                                onPressed: () => mediaService.openSettings(),
                              ),
                            ),
                          );
                          return;
                        }
                        
                        // Start recording
                        HapticFeedback.mediumImpact();
                        setState(() {
                          _recordingStartPosition = details.globalPosition;
                          _currentDragPosition = details.globalPosition;
                          _isCancelThresholdReached = false;
                          _recordingSeconds = 0;
                        });
                        
                        _recordingTimer?.cancel();
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
                      onLongPressMoveUpdate: (details) {
                        if (_recordingStartPosition == null) return;
                        
                        setState(() {
                          _currentDragPosition = details.globalPosition;
                        });
                        
                        // Calculate horizontal drag distance
                        final dragDistance = (_recordingStartPosition!.dx - details.globalPosition.dx).abs();
                        final wasThresholdReached = _isCancelThresholdReached;
                        _isCancelThresholdReached = dragDistance > _cancelThreshold;
                        
                        // Provide haptic feedback when threshold is reached
                        if (_isCancelThresholdReached && !wasThresholdReached) {
                          HapticFeedback.mediumImpact();
                        }
                      },
                      onLongPressEnd: (details) async {
                        final recordingDuration = Duration(seconds: _recordingSeconds);
                        
                        _recordingTimer?.cancel();
                        
                        // Check if cancelled by slide gesture
                        if (_isCancelThresholdReached) {
                          HapticFeedback.lightImpact();
                          await ref
                              .read(chatRoomProvider(widget.params).notifier)
                              .cancelRecording();
                          setState(() {
                            _recordingStartPosition = null;
                            _currentDragPosition = null;
                            _isCancelThresholdReached = false;
                            _recordingSeconds = 0;
                          });
                          return;
                        }
                        
                        // Check if recording is too short
                        if (recordingDuration < _minRecordingDuration) {
                          HapticFeedback.lightImpact();
                          await ref
                              .read(chatRoomProvider(widget.params).notifier)
                              .cancelRecording();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('錄音時間過短'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          setState(() {
                            _recordingStartPosition = null;
                            _currentDragPosition = null;
                            _recordingSeconds = 0;
                          });
                          return;
                        }
                        
                        // Send the recording
                        HapticFeedback.lightImpact();
                        await ref
                            .read(chatRoomProvider(widget.params).notifier)
                            .stopRecordingAndSend();
                        
                        setState(() {
                          _recordingStartPosition = null;
                          _currentDragPosition = null;
                          _isCancelThresholdReached = false;
                          _recordingSeconds = 0;
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: state.isRecording
                              ? tokens.accent
                              : (isDark
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFF0F2F5)),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mic_rounded,
                          color: state.isRecording
                              ? Colors.white
                              : (isDark ? Colors.white54 : Colors.grey[600]),
                          size: 22,
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
      // 🔥 修復：將 link preview 數據傳遞給 sendMessage
      LinkPreview? linkPreview;
      if (_previewData != null && !_isUrlPreviewCancelled) {
        linkPreview = LinkPreview(
          url: _previewData!.url,
          title: _previewData!.title,
          description: _previewData!.description,
          imageUrl: _previewData?.imageUrl,
        );
        print('📎 [ChatInput] 發送訊息附帶 Link Preview:');
        print('   URL: ${linkPreview.url}');
        print('   Title: "${linkPreview.title}"');
        print('   Description: "${linkPreview.description}"');
        print('   ImageURL: ${linkPreview.imageUrl}');
      }
      
      ref.read(chatRoomProvider(widget.params).notifier).sendMessage(
        text,
        linkPreview: linkPreview,
      );
      _textController.clear();
      _debounceTimer?.cancel();
      setState(() {
        _detectedUrl = null;
        _previewData = null;
        _isLoadingPreview = false;
        _isUrlPreviewCancelled = false;
      });
    }
  }

  void _onTextChanged(String text) {
    ref.read(chatRoomProvider(widget.params).notifier).startTyping();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final urls = extractAllUrls(text);
      if (text.trim().isEmpty || urls.isEmpty) {
        setState(() {
          _detectedUrl = null;
          _previewData = null;
          _isLoadingPreview = false;
          _isUrlPreviewCancelled = false;
        });
        return;
      }

      final url = urls.first;
      final isNewUrl = _detectedUrl != url;
      if (isNewUrl && _isUrlPreviewCancelled) {
        setState(() {
          _isUrlPreviewCancelled = false;
        });
      }
      if (_isUrlPreviewCancelled && !isNewUrl) {
        return;
      }
      setState(() {
        _detectedUrl = url;
        _isLoadingPreview = true;
        _previewData = null;
      });
      final apiPreview = await _fetchLinkPreview(url);
      if (!mounted) return;
      final latestUrls = extractAllUrls(_textController.text);
      if (latestUrls.isEmpty ||
          latestUrls.first != url ||
          _isUrlPreviewCancelled) {
        return;
      }
      final uri = Uri.tryParse(url);
      final title =
          apiPreview?.title ??
          (uri?.host.isNotEmpty == true ? uri!.host : '網站連結');
      final description =
          apiPreview?.description ??
          (uri?.path.isNotEmpty == true ? uri!.path : url);
      final imageUrl =
          apiPreview?.imageUrl ??
          (uri == null
              ? null
              : 'https://www.google.com/s2/favicons?sz=128&domain_url=${Uri.encodeComponent(url)}');
      setState(() {
        _detectedUrl = url;
        _isLoadingPreview = false;
        _previewData = LinkPreviewData(
          url: url,
          title: title,
          description: description,
          imageUrl: imageUrl,
        );
      });
    });
  }

  Future<LinkPreviewData?> _fetchLinkPreview(String text) async {
    try {
      final response = await ref
          .read(networkServiceProvider)
          .client
          .get('/messages/link-preview', queryParameters: {'content': text});
      final data = response.data;
      if (data is! Map) return null;
      final payload = data['data'];
      if (payload is! Map) return null;
      final map = Map<String, dynamic>.from(payload);
      final url = (map['url'] ?? '').toString();
      final title = (map['title'] ?? '').toString();
      final description = (map['description'] ?? '').toString();
      final imageUrlRaw = (map['image_url'] ?? '').toString();
      if (url.isEmpty && title.isEmpty && description.isEmpty) {
        return null;
      }
      return LinkPreviewData(
        url: url,
        title: title.isNotEmpty ? title : url,
        description: description.isNotEmpty ? description : url,
        imageUrl: imageUrlRaw.isNotEmpty ? imageUrlRaw : null,
      );
    } catch (_) {
      return null;
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
