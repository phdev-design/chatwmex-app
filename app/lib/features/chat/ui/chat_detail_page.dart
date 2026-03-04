import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/models/message.dart';
import 'package:app/core/media/media_service.dart';
import 'package:app/features/chat/ui/audio_message_bubble.dart';

class ChatDetailPage extends ConsumerStatefulWidget {
  final String roomId;
  final String title;
  final bool isRoom;
  final String currentUserId;
  final String token;
  final String? avatarUrl;

  const ChatDetailPage({
    super.key,
    required this.roomId,
    required this.title,
    this.isRoom = false,
    required this.currentUserId,
    required this.token,
    this.avatarUrl,
  });

  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class ChatAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final String fallbackText;
  final IconData? fallbackIcon;
  final String logTag;

  const ChatAvatar({
    super.key,
    required this.avatarUrl,
    required this.radius,
    required this.fallbackText,
    this.fallbackIcon,
    this.logTag = 'chat_avatar',
  });

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF2A3942),
      child: fallbackIcon != null
          ? Icon(fallbackIcon, color: Colors.white, size: radius)
          : Text(
              fallbackText,
              style: TextStyle(color: Colors.white, fontSize: radius * 0.8),
            ),
    );
    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return fallback;
    }
    final resolvedUrl = Uri.encodeFull(NetworkService.resolveUrl(avatarUrl!));
    return ClipOval(
      child: Image.network(
        resolvedUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint(
            '$logTag avatar load failed url=$resolvedUrl error=$error',
          );
          return fallback;
        },
      ),
    );
  }
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();

  // 控制鍵盤焦點
  final FocusNode _focusNode = FocusNode();

  late final AutoScrollController _scrollController;
  bool _showNewMessageBanner = false;
  int _unreadCount = 0;
  bool _isAtBottom = true;
  final Set<String> _deletingMessageIds = <String>{};
  final Set<String> _collapsingMessageIds = <String>{};
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  late final AnimationController _arrowController;
  late final Animation<Offset> _arrowOffset;
  late final AnimationController _recordingBlinkController;
  late final Animation<double> _recordingOpacity;

  ChatRoomParams get _params => ChatRoomParams(
    roomId: widget.roomId,
    isRoom: widget.isRoom,
    currentUserId: widget.currentUserId,
    token: widget.token,
  );

  @override
  void initState() {
    super.initState();
    _scrollController = AutoScrollController();
    _scrollController.addListener(_onScroll);
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _arrowOffset =
        Tween<Offset>(
          begin: const Offset(0, 0),
          end: const Offset(0, 0.2),
        ).animate(
          CurvedAnimation(parent: _arrowController, curve: Curves.easeInOut),
        );
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
    _scrollController.dispose();
    _arrowController.dispose();
    _recordingBlinkController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    final state = ref.read(chatRoomProvider(_params));
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;

    // 因為 reverse: true，0.0 才是最底部 (最新訊息)
    _isAtBottom = current <= 50;

    if (_isAtBottom && _showNewMessageBanner) {
      if (mounted) {
        setState(() {
          _showNewMessageBanner = false;
          _unreadCount = 0;
        });
      }
    }
    // 抵達最頂部 (最舊的訊息) 時，載入歷史紀錄
    if (current == max && !state.isLoading) {
      ref
          .read(chatRoomProvider(_params).notifier)
          .loadHistory(offset: state.messages.length);
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      ref.read(chatRoomProvider(_params).notifier).sendMessage(text);
      _textController.clear();
    }
  }

  void _pickImage(ImageSource source) async {
    final mediaService = ref.read(mediaServiceProvider);
    final file = await mediaService.pickImage(source);
    if (file != null) {
      ref
          .read(chatRoomProvider(_params).notifier)
          .sendMedia(file, MessageType.image);
    }
  }

  void _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    ref.read(chatRoomProvider(_params).notifier).sendDocument(File(path));
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2A30),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAttachmentOption(
                icon: Icons.camera_alt,
                color: const Color(0xFFD3396D), // WhatsApp 粉紅
                label: '相機',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              _buildAttachmentOption(
                icon: Icons.photo,
                color: const Color(0xFFAC44CF), // WhatsApp 紫色
                label: '圖庫',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              _buildAttachmentOption(
                icon: Icons.insert_drive_file,
                color: const Color(0xFF5157AE), // WhatsApp 藍色
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
            style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ==== 導航至聯絡人頁面 ====
  void _navigateToContactInfo() {
    final state = ref.read(chatRoomProvider(_params));
    final effectiveAvatarUrl = state.roomAvatarUrl.isNotEmpty
        ? state.roomAvatarUrl
        : widget.avatarUrl;
    context.push(
      '/contact-info',
      extra: {
        'roomId': widget.roomId,
        'title': widget.title,
        'isRoom': widget.isRoom,
        'avatarUrl': effectiveAvatarUrl,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatRoomProvider(_params));
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveAvatarUrl = state.roomAvatarUrl.isNotEmpty
        ? state.roomAvatarUrl
        : widget.avatarUrl;

    ref.listen(chatRoomProvider(_params), (previous, next) {
      if (previous == null ||
          previous.messages.isEmpty ||
          next.messages.isEmpty) {
        return;
      }

      if (next.messages.first.id != previous.messages.first.id) {
        final msg = next.messages.first;
        if (msg.senderId == widget.currentUserId) {
          // 自己發送的，自動滾動到底部
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          // 對方發送的
          if (_isAtBottom) {
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          } else {
            if (mounted) {
              setState(() {
                _unreadCount += 1;
                _showNewMessageBanner = true;
              });
            }
          }
        }
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111B21),
        titleSpacing: 0,
        // 加入 InkWell 來讓點擊標題區時，可以前往新的聯絡人資料頁
        title: InkWell(
          onTap: _navigateToContactInfo,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
            child: Row(
              children: [
                Hero(
                  tag: 'avatar_${widget.roomId}',
                  child: ChatAvatar(
                    radius: 18,
                    avatarUrl: effectiveAvatarUrl,
                    fallbackText: widget.title.isNotEmpty
                        ? widget.title[0].toUpperCase()
                        : '',
                    logTag: 'chat_appbar',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '點按此處查看聯絡人資料',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.videocam), onPressed: () {}),
          IconButton(icon: const Icon(Icons.call), onPressed: () {}),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(color: Color(0xFF0B141A)),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: state.messages.isEmpty && state.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification.metrics.pixels >=
                                  notification.metrics.maxScrollExtent - 200) {
                                ref
                                    .read(chatRoomProvider(_params).notifier)
                                    .loadMoreMessages();
                              }
                              return false;
                            },
                            child: ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              itemCount: state.messages.length + 1,
                              itemBuilder: (context, index) {
                                if (index == state.messages.length) {
                                  if (state.hasMore) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      '已經沒有更多訊息了',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: colorScheme.outline,
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                }
                                final msg = state.messages[index];
                                final isMe =
                                    msg.senderId == widget.currentUserId;
                                final isDeleting = _deletingMessageIds.contains(
                                  msg.id,
                                );
                                final isCollapsing = _collapsingMessageIds
                                    .contains(msg.id);

                                final nextMessage =
                                    (index + 1) < state.messages.length
                                    ? state.messages[index + 1]
                                    : null;

                                final showDivider =
                                    nextMessage == null ||
                                    !_isSameDay(
                                      msg.createdAt,
                                      nextMessage.createdAt,
                                    );

                                final isSameSender =
                                    nextMessage != null &&
                                    nextMessage.senderId == msg.senderId &&
                                    !showDivider;

                                return AutoScrollTag(
                                  key: ValueKey('msg_${msg.id}_$index'),
                                  controller: _scrollController,
                                  index: index,
                                  child: Column(
                                    children: [
                                      if (showDivider)
                                        _buildDateDivider(msg.createdAt),
                                      SizedBox(height: isSameSender ? 2 : 8),
                                      VisibilityDetector(
                                        key: ValueKey(
                                          'msg_${msg.id}_vis_$index',
                                        ),
                                        onVisibilityChanged: (info) {
                                          if (!isMe &&
                                              info.visibleFraction > 0.5 &&
                                              !msg.readBy.contains(
                                                widget.currentUserId,
                                              )) {
                                            ref
                                                .read(
                                                  chatRoomProvider(
                                                    _params,
                                                  ).notifier,
                                                )
                                                .markAsRead(msg.id);
                                          }
                                        },
                                        child: ClipRect(
                                          child: AnimatedSize(
                                            duration: const Duration(
                                              milliseconds: 180,
                                            ),
                                            curve: Curves.easeInOut,
                                            alignment: Alignment.topCenter,
                                            child: isCollapsing
                                                ? const SizedBox.shrink()
                                                : AnimatedOpacity(
                                                    duration: const Duration(
                                                      milliseconds: 220,
                                                    ),
                                                    opacity: isDeleting
                                                        ? 0.0
                                                        : 1.0,
                                                    child: IgnorePointer(
                                                      ignoring: isDeleting,
                                                      child:
                                                          _buildMessageBubble(
                                                            msg,
                                                            isMe,
                                                            state,
                                                          ),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                  if (_showNewMessageBanner)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 16,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            if (mounted) {
                              setState(() {
                                _showNewMessageBanner = false;
                                _unreadCount = 0;
                              });
                            }
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.animateTo(
                                  0.0,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOut,
                                );
                              }
                            });
                          },
                          child: AnimatedOpacity(
                            opacity: _showNewMessageBanner ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SlideTransition(
                                    position: _arrowOffset,
                                    child: Icon(
                                      Icons.arrow_downward,
                                      size: 14,
                                      color: colorScheme.onSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '新訊息 ${_unreadCount > 99 ? '99+' : _unreadCount}',
                                    style: TextStyle(
                                      color: colorScheme.onSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  if (state.typingUsers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 4.0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedOpacity(
                          opacity: state.typingUsers.isNotEmpty ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            '對方輸入中...',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (state.replyingToMessage != null)
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A3942),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF53BDEB),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _resolveReplySenderName(
                                    state.replyingToMessage!,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  state.replyingToMessage!.type ==
                                          MessageType.image
                                      ? '[圖片]'
                                      : state.replyingToMessage!.content,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400,
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
                                .read(chatRoomProvider(_params).notifier)
                                .setReplyingTo(null),
                          ),
                        ],
                      ),
                    ),

                  // ===== 底部的訊息輸入列 =====
                  Container(
                    color: const Color(0xFF111B21),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 6.0,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add),
                          color: Colors.grey.shade400,
                          onPressed: _showAttachmentMenu,
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A3942),
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
                                            color: Colors.grey.shade200,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatRecordingTime(_recordingSeconds),
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  )
                                : TextField(
                                    controller: _textController,
                                    focusNode: _focusNode,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: '輸入訊息',
                                      hintStyle: TextStyle(
                                        color: Colors.grey.shade400,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      suffixIcon: Icon(
                                        Icons.emoji_emotions_outlined,
                                        color: Colors.grey.shade400,
                                      ),
                                      suffixIconConstraints:
                                          const BoxConstraints(
                                            minWidth: 40,
                                            minHeight: 24,
                                          ),
                                    ),
                                    onSubmitted: (_) => _sendMessage(),
                                    onChanged: (_) {
                                      ref
                                          .read(
                                            chatRoomProvider(_params).notifier,
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
                                color: const Color(0xFF53BDEB), // 使用主色調藍色
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
                                    .read(chatRoomProvider(_params).notifier)
                                    .startRecording();
                              },
                              onLongPressEnd: (_) {
                                HapticFeedback.lightImpact();
                                _recordingTimer?.cancel();
                                setState(() => _recordingSeconds = 0);
                                ref
                                    .read(chatRoomProvider(_params).notifier)
                                    .stopRecordingAndSend();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Icon(
                                  Icons.mic,
                                  color: state.isRecording
                                      ? const Color(0xFF53BDEB)
                                      : Colors.grey.shade400,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message msg, bool isMe, ChatRoomState state) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget content;
    if (msg.type == MessageType.image) {
      final imageUrl = NetworkService.resolveUrl(msg.content);
      content = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.6,
          ),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return SizedBox(
                width: 120,
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return SizedBox(
                width: 120,
                height: 120,
                child: Center(
                  child: Icon(Icons.broken_image, color: colorScheme.outline),
                ),
              );
            },
          ),
        ),
      );
    } else if (msg.type == MessageType.voice) {
      content = AudioMessageBubble(audioUrl: msg.content);
    } else {
      content = Text(msg.content, style: const TextStyle(fontSize: 15));
    }

    final replyMessage = msg.isUnsent ? null : msg.replyToMessage;
    Widget? replyContent;
    if (replyMessage != null) {
      final isReplyImage = replyMessage.type == MessageType.image;
      final replyText = isReplyImage ? '[圖片]' : replyMessage.content;
      replyContent = InkWell(
        onTap: () => _scrollToMessage(replyMessage.id),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2A30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF53BDEB),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _resolveReplySenderName(replyMessage),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF53BDEB),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isReplyImage) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              NetworkService.resolveUrl(replyMessage.content),
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 28,
                                  height: 28,
                                  color: const Color(0xFF2A3942),
                                  child: Icon(
                                    Icons.broken_image,
                                    size: 14,
                                    color: Colors.grey.shade400,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            replyText,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final timeText = DateFormat('a h:mm').format(msg.createdAt);
    final statusColor = msg.status == MessageStatus.read
        ? const Color(0xFF53BDEB)
        : Colors.grey.shade400;
    IconData statusIcon;
    switch (msg.status) {
      case MessageStatus.sending:
        statusIcon = Icons.access_time;
        break;
      case MessageStatus.sent:
        statusIcon = Icons.check;
        break;
      case MessageStatus.delivered:
      case MessageStatus.read:
        statusIcon = Icons.done_all;
        break;
      case MessageStatus.failed:
        statusIcon = Icons.error_outline;
        break;
    }
    final statusWidget = isMe
        ? Icon(
            statusIcon,
            size: 14,
            color: msg.status == MessageStatus.failed
                ? Colors.redAccent
                : statusColor,
          )
        : const SizedBox();
    final reactions = msg.isUnsent
        ? <String, List<String>>{}
        : (msg.reactions ?? {});

    // 把 Margin 移到 Padding 上，讓內部的 Stack 與 Bubble 的大小完全一致
    // 這樣在使用 Builder 獲取 RenderBox 時，就能精準取得氣泡的座標與尺寸！
    final double paddingBottom = reactions.isNotEmpty ? 22.0 : 4.0;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 60 : 44, // <--- 修改：永遠給左側保留 44 的空間，不管是群組還是私聊
          right: isMe ? 12 : 60,
          bottom: paddingBottom,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (!isMe) // <--- 修改：拿掉 widget.isRoom 的限制條件
              Positioned(
                left: -32,
                top: 0,
                child: _buildGroupSenderAvatar(msg, state),
              ),
            // 利用 Builder 取得 GestureDetector (氣泡本身) 的 BuildContext
            Builder(
              builder: (bubbleContext) {
                return GestureDetector(
                  onLongPress: msg.isUnsent
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          _showMessageActions(msg, bubbleContext, isMe);
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? const Color(0xFF005C4B)
                          : const Color(0xFF202C33),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (replyContent != null) ...[
                          replyContent,
                          const SizedBox(height: 6),
                        ],
                        msg.isUnsent
                            ? Text(
                                '此訊息已收回',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey.shade400,
                                ),
                              )
                            : DefaultTextStyle.merge(
                                style: const TextStyle(color: Colors.white),
                                child: content,
                              ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeText,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              statusWidget,
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (reactions.isNotEmpty)
              Positioned(
                // 相對於實際 Bubble 的位置，掛在下方邊緣
                bottom: -16,
                right: isMe ? 4 : null,
                left: isMe ? null : 4,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: _buildReactionsBar(reactions, msg.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSenderAvatar(Message msg, ChatRoomState state) {
    final avatarUrl = widget.isRoom
        ? state.userAvatarUrls[msg.senderId]
        : (state.roomAvatarUrl.isNotEmpty
              ? state.roomAvatarUrl
              : widget.avatarUrl);
    final fallbackText = widget.isRoom
        ? (msg.senderId.isNotEmpty ? msg.senderId[0].toUpperCase() : '?')
        : (widget.title.isNotEmpty ? widget.title[0].toUpperCase() : '?');
    return ChatAvatar(
      radius: 14,
      avatarUrl: avatarUrl,
      fallbackText: fallbackText,
      logTag: 'chat_bubble',
    );
  }

  // --- 加入彈出動畫、精準座標定位的 Bubble Menu ---
  void _showMessageActions(Message msg, BuildContext bubbleContext, bool isMe) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢'];

    // 1. 取得訊息氣泡(Bubble)的準確位置和大小
    final RenderBox renderBox = bubbleContext.findRenderObject() as RenderBox;
    final bubbleSize = renderBox.size;
    // 取得氣泡在整個螢幕中的絕對座標 (X, Y)
    final bubbleOffset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // 2. 預估精確的選單尺寸，避免因為估算錯誤導致與氣泡重疊
    const menuWidth = 240.0;
    // 預設高度：Emojis(62) + 分隔線(1) + 2個按鈕(88) + 底部保留(4) = 155
    double menuHeight = 155.0;
    if (msg.senderId == widget.currentUserId && !msg.isUnsent) {
      // 若是自己傳送的，多一個「收回」按鈕(+44) = 199
      menuHeight = 199.0;
    }

    // 3. 計算 Y 座標 (判斷要在氣泡 上方 還是 下方)
    bool showAbove = true;
    double top = bubbleOffset.dy - menuHeight - 8.0;

    // 如果上方空間不足 (例如頂到螢幕最上方)，改為顯示在氣泡的下方
    final topSafeArea = MediaQuery.of(context).padding.top + kToolbarHeight;
    if (top < topSafeArea) {
      showAbove = false;
      // 位置設為氣泡的底端往下延伸 8px
      top = bubbleOffset.dy + bubbleSize.height + 8.0;
    }

    // 防呆：如果下方空間也不足，就確保它不要超出螢幕底端
    if (!showAbove && top + menuHeight > screenSize.height - 30) {
      top = screenSize.height - menuHeight - 30;
    }

    // 4. 計算 X 座標 (對齊氣泡左右側)
    double left;
    if (isMe) {
      // 自己的訊息：對齊氣泡右側
      left = (bubbleOffset.dx + bubbleSize.width) - menuWidth;
    } else {
      // 對方的訊息：對齊氣泡左側
      left = bubbleOffset.dx;
    }

    // 確保不會超出版面邊界 (左右保留 16px 的安全距離)
    if (left < 16) left = 16;
    if (left + menuWidth > screenSize.width - 16) {
      left = screenSize.width - menuWidth - 16;
    }

    // 5. 動畫展開的基準點 (Alignment)
    // 如果在氣泡上方展開，從底部邊角長出來；如果在氣泡下方展開，從頂部邊角長出來
    final animationAlignment = showAbove
        ? (isMe ? Alignment.bottomRight : Alignment.bottomLeft)
        : (isMe ? Alignment.topRight : Alignment.topLeft);

    // 這裡改用 showGeneralDialog 並搭配 Scaffold
    // 確保 (0, 0) 是真正螢幕的左上角，不受 Dialog 預設的 Padding 和 SafeArea 影響
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black12, // 透明的黑底，避免背景過暗
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          // 重要：設定為 false 確保鍵盤彈出等行為不會干擾我們絕對座標的 Stack 畫布
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              // 讓使用者點擊空白處時關閉選單
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),

              // 彈出框本體
              Positioned(
                left: left,
                top: top,
                // 加入 Q 彈動畫 (Scale + Fade)
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack, // 讓彈出有一點 Q 彈回縮的效果
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      alignment: animationAlignment, // 從氣泡的邊角為基準點長出來
                      child: Opacity(
                        // 透明度動畫，限制在 0.0 ~ 1.0 避免超出報錯
                        opacity: scale.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: menuWidth,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2A30),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 表情符號列
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: emojis.map((emoji) {
                                return InkWell(
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    ref
                                        .read(
                                          chatRoomProvider(_params).notifier,
                                        )
                                        .toggleReaction(msg.id, emoji);
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF2A3942),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 22),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const Divider(height: 1, color: Colors.black26),

                          // 回覆按鈕
                          _buildMenuAction(
                            icon: Icons.reply,
                            label: '回覆',
                            onTap: () {
                              Navigator.of(context).pop();
                              ref
                                  .read(chatRoomProvider(_params).notifier)
                                  .setReplyingTo(msg);
                              _focusNode.requestFocus();
                            },
                          ),
                          // 刪除按鈕
                          _buildMenuAction(
                            icon: Icons.delete_outline,
                            label: '刪除 (Delete for me)',
                            onTap: () {
                              Navigator.of(context).pop();
                              _confirmDeleteMessage(msg);
                            },
                          ),
                          // 收回按鈕 (僅限自己發送且尚未收回的訊息)
                          if (msg.senderId == widget.currentUserId &&
                              !msg.isUnsent)
                            _buildMenuAction(
                              icon: Icons.undo,
                              label: '收回 (Unsend)',
                              onTap: () {
                                Navigator.of(context).pop();
                                ref
                                    .read(chatRoomProvider(_params).notifier)
                                    .unsendMessage(msg);
                              },
                            ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMessage(Message msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('刪除訊息'),
          content: const Text('確定要刪除這則訊息嗎？此訊息僅會從您的設備中刪除，對方仍可看見。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('確定'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (_deletingMessageIds.contains(msg.id)) return;
    setState(() => _deletingMessageIds.add(msg.id));
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => _collapsingMessageIds.add(msg.id));
    await Future.delayed(const Duration(milliseconds: 180));
    try {
      await ref.read(chatRoomProvider(_params).notifier).deleteMessage(msg.id);
    } finally {
      if (mounted) {
        setState(() {
          _deletingMessageIds.remove(msg.id);
          _collapsingMessageIds.remove(msg.id);
        });
      }
    }
  }

  // 氣泡選單列表項目的共用小工具
  Widget _buildMenuAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionsBar(
    Map<String, List<String>> reactions,
    String messageId,
  ) {
    final entries = reactions.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries.map((entry) {
        final emoji = entry.key;
        final users = entry.value;
        final reacted = users.contains(widget.currentUserId);

        return InkWell(
          onTap: () => ref
              .read(chatRoomProvider(_params).notifier)
              .toggleReaction(messageId, emoji),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                if (users.length > 1) ...[
                  const SizedBox(width: 4),
                  Text(
                    '${users.length}',
                    style: TextStyle(
                      fontSize: 13,
                      color: reacted
                          ? const Color(0xFF53BDEB)
                          : Colors.grey.shade400,
                      fontWeight: reacted ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _scrollToMessage(String messageId) async {
    final state = ref.read(chatRoomProvider(_params));
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    await _scrollController.scrollToIndex(
      index,
      preferPosition: AutoScrollPosition.begin,
    );
    _scrollController.highlight(index);
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(color: Colors.black.withOpacity(0.8)),
                ),
              ),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return SizedBox(
                        width: 120,
                        height: 120,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                      progress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        padding: const EdgeInsets.all(24),
                        color: const Color(0xFF2A3942),
                        child: const Icon(
                          Icons.broken_image,
                          size: 48,
                          color: Colors.white54,
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _resolveReplySenderName(Message replyMessage) {
    if (replyMessage.senderId == widget.currentUserId) {
      return '你';
    }
    if (!widget.isRoom) {
      if (widget.title.isNotEmpty) {
        return widget.title;
      }
    }
    return '回覆訊息';
  }

  String _formatRecordingTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remain = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remain';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return DateUtils.isSameDay(a, b);
  }

  Widget _buildDateDivider(DateTime date) {
    final now = DateTime.now();
    final label = _isSameDay(date, now)
        ? '今天'
        : DateFormat('yyyy/MM/dd').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2A30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ),
      ),
    );
  }
}
