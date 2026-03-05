import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/pdf_preview_screen.dart';
import 'package:app/features/chat/ui/photo_screen.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:app/features/chat/ui/audio_message_bubble.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:app/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
// 加入 emoji_picker_flutter 匯入
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;

class MessageBubble extends ConsumerStatefulWidget {
  final Message msg;
  final bool isMe;
  final ChatRoomState state;
  final ChatRoomParams params;
  final bool isRoom;
  final String currentUserId;
  final String title;
  final Future<void> Function(String messageId) onScrollToMessage;

  const MessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    required this.state,
    required this.params,
    required this.isRoom,
    required this.currentUserId,
    required this.title,
    required this.onScrollToMessage,
  });

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  bool _isDeleting = false;
  bool _isCollapsing = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final isMe = widget.isMe;
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: Theme.of(context).brightness,
    );

    // 👇 根據是否為自己發送的，決定文字顏色
    final textColor = isMe ? tokens.bubbleOutgoingText : tokens.bubbleText;
    final subtleTextColor = isMe
        ? tokens.bubbleOutgoingSubtleText
        : tokens.subtleText;

    Widget content;
    if (msg.type == MessageType.image) {
      final imageUrl = resolveFullUrl(msg.content);
      final heroTag = msg.id.isNotEmpty ? msg.id : imageUrl;
      content = GestureDetector(
        onTap: imageUrl.isEmpty
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PhotoScreen(imageUrl: imageUrl, heroTag: heroTag),
                  ),
                );
              },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Hero(
            tag: heroTag,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.6,
                maxHeight: 250,
              ),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
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
                      child: Icon(
                        Icons.broken_image,
                        color: colorScheme.outline,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    } else if (msg.type == MessageType.voice) {
      content = AudioMessageBubble(audioUrl: msg.content);
    } else if (msg.type == MessageType.file) {
      final fileUrl = resolveFullUrl(msg.content);
      final parsed = Uri.tryParse(fileUrl);
      final fileName = (parsed != null && parsed.pathSegments.isNotEmpty)
          ? parsed.pathSegments.last
          : 'Document';
      final lowerName = fileName.toLowerCase();
      final isPdf = lowerName.endsWith('.pdf');
      content = GestureDetector(
        onTap: () async {
          if (isPdf) {
            try {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PdfPreviewScreen(
                    pdfUrl: fileUrl,
                    fileName: fileName,
                  ),
                ),
              );
            } catch (_) {
              final uri = Uri.tryParse(fileUrl);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
            return;
          }
          final uri = Uri.tryParse(fileUrl);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
          ),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isMe
                  ? tokens.bubbleOutgoingBackground
                  : tokens.bubbleIncomingBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                  color: isPdf ? Colors.redAccent : subtleTextColor,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPdf ? 'PDF 文件' : '檔案',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subtleTextColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      content = Text(msg.content, style: const TextStyle(fontSize: 15));
    }

    final replyMessage = msg.isUnsent ? null : msg.replyToMessage;
    Widget? replyContent;
    if (replyMessage != null) {
      final isReplyImage = replyMessage.type == MessageType.image;
      final replyText = isReplyImage ? '[圖片]' : replyMessage.content;
      replyContent = InkWell(
        onTap: () => widget.onScrollToMessage(replyMessage.id),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: tokens.replyBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: tokens.accent,
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.accent,
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
                              resolveFullUrl(replyMessage.content),
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 28,
                                  height: 28,
                                  color: tokens.imageFallbackBackground,
                                  child: Icon(
                                    Icons.broken_image,
                                    size: 14,
                                    color: tokens.subtleText,
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
                              color: tokens.subtleText,
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
        ? tokens.accent
        : subtleTextColor;

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
    final double paddingBottom = reactions.isNotEmpty ? 22.0 : 4.0;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 60 : 44,
          right: isMe ? 12 : 60,
          bottom: paddingBottom,
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _isCollapsing
              ? const SizedBox.shrink()
              : AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _isDeleting ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: _isDeleting,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (!isMe)
                          Positioned(
                            left: -32,
                            top: 0,
                            child: _buildGroupSenderAvatar(msg),
                          ),
                        Builder(
                          builder: (bubbleContext) {
                            return GestureDetector(
                              onLongPress: msg.isUnsent
                                  ? null
                                  : () {
                                      HapticFeedback.mediumImpact();
                                      _showMessageActions(
                                        msg,
                                        bubbleContext,
                                        isMe,
                                      );
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? tokens.bubbleOutgoingBackground
                                      : tokens.bubbleIncomingBackground,
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
                                              color: subtleTextColor,
                                            ),
                                          )
                                        : DefaultTextStyle.merge(
                                            style: TextStyle(color: textColor),
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
                                            color: subtleTextColor,
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
                            bottom: -16,
                            right: isMe ? 4 : null,
                            left: isMe ? null : 4,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
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
                ),
        ),
      ),
    );
  }

  Widget _buildGroupSenderAvatar(Message msg) {
    final avatarUrl = widget.isRoom
        ? widget.state.userAvatarUrls[msg.senderId]
        : (widget.state.roomAvatarUrl.isNotEmpty
              ? widget.state.roomAvatarUrl
              : null);
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

  // --- 新增：顯示完整 Emoji Picker 的 BottomSheet ---
  void _showFullEmojiPicker(BuildContext context, Message msg) {
    final tokens = resolveChatSurfaceTokens(
      colorScheme: Theme.of(context).colorScheme,
      brightness: Theme.of(context).brightness,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: tokens.menuBackground,
      isScrollControlled: true, // 讓 BottomSheet 可以調整高度
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.45, // 佔據螢幕下方 45%
          child: Column(
            children: [
              // 頂部小拉桿裝飾
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    Navigator.of(context).pop(); // 選完後關閉 BottomSheet
                    ref
                        .read(chatRoomProvider(widget.params).notifier)
                        .toggleReaction(msg.id, emoji.emoji);
                  },
                  config: Config(
                    height: 256,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: tokens.menuBackground,
                      columns: 7,
                      emojiSizeMax:
                          28 *
                          (foundation.defaultTargetPlatform ==
                                  TargetPlatform.iOS
                              ? 1.30
                              : 1.0),
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: tokens.menuBackground,
                      indicatorColor: tokens.accent,
                      iconColorSelected: tokens.accent,
                      iconColor: tokens.subtleText,
                      dividerColor: Colors.transparent,
                    ),
                    bottomActionBarConfig: BottomActionBarConfig(
                      backgroundColor: tokens.menuBackground,
                      buttonColor: tokens.menuBackground,
                      buttonIconColor: tokens.subtleText,
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: tokens.menuBackground,
                      buttonIconColor: tokens.subtleText,
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

  void _showMessageActions(Message msg, BuildContext bubbleContext, bool isMe) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢'];
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: Theme.of(context).brightness,
    );
    final RenderBox renderBox = bubbleContext.findRenderObject() as RenderBox;
    final bubbleSize = renderBox.size;
    final bubbleOffset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    const menuWidth = 240.0;
    double menuHeight = 155.0;
    if (msg.senderId == widget.currentUserId && !msg.isUnsent) {
      menuHeight = 199.0;
    }
    bool showAbove = true;
    double top = bubbleOffset.dy - menuHeight - 8.0;
    final topSafeArea = MediaQuery.of(context).padding.top + kToolbarHeight;
    if (top < topSafeArea) {
      showAbove = false;
      top = bubbleOffset.dy + bubbleSize.height + 8.0;
    }
    if (!showAbove && top + menuHeight > screenSize.height - 30) {
      top = screenSize.height - menuHeight - 30;
    }
    double left;
    if (isMe) {
      left = (bubbleOffset.dx + bubbleSize.width) - menuWidth;
    } else {
      left = bubbleOffset.dx;
    }
    if (left < 16) left = 16;
    if (left + menuWidth > screenSize.width - 16) {
      left = screenSize.width - menuWidth - 16;
    }
    final animationAlignment = showAbove
        ? (isMe ? Alignment.bottomRight : Alignment.bottomLeft)
        : (isMe ? Alignment.topRight : Alignment.topLeft);

    showGeneralDialog(
      context: context,
      barrierColor: Colors.black12,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      alignment: animationAlignment,
                      child: Opacity(
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
                        color: tokens.menuBackground,
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
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ...emojis.map((emoji) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.of(context).pop();
                                          ref
                                              .read(
                                                chatRoomProvider(
                                                  widget.params,
                                                ).notifier,
                                              )
                                              .toggleReaction(msg.id, emoji);
                                        },
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: tokens.menuEmojiBackground,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            emoji,
                                            style: const TextStyle(
                                              fontSize: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        _showFullEmojiPicker(context, msg);
                                      },
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: tokens.menuEmojiBackground,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.add,
                                          color: tokens.subtleText,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          _buildMenuAction(
                            icon: Icons.reply,
                            label: '回覆',
                            onTap: () {
                              Navigator.of(context).pop();
                              ref
                                  .read(
                                    chatRoomProvider(widget.params).notifier,
                                  )
                                  .setReplyingTo(msg);
                            },
                          ),
                          _buildMenuAction(
                            icon: Icons.delete_outline,
                            label: '刪除 (Delete for me)',
                            onTap: () {
                              Navigator.of(context).pop();
                              _confirmDeleteMessage(msg);
                            },
                          ),
                          if (msg.senderId == widget.currentUserId &&
                              !msg.isUnsent)
                            _buildMenuAction(
                              icon: Icons.undo,
                              label: '收回 (Unsend)',
                              onTap: () {
                                Navigator.of(context).pop();
                                ref
                                    .read(
                                      chatRoomProvider(widget.params).notifier,
                                    )
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
    if (confirmed != true || _isDeleting) return;
    setState(() => _isDeleting = true);
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => _isCollapsing = true);
    await Future.delayed(const Duration(milliseconds: 180));
    try {
      await ref
          .read(chatRoomProvider(widget.params).notifier)
          .deleteMessage(msg.id);
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _isCollapsing = false;
        });
      }
    }
  }

  Widget _buildMenuAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: iconColor, fontSize: 15),
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
    final colorScheme = Theme.of(context).colorScheme;
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
              .read(chatRoomProvider(widget.params).notifier)
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
                          : colorScheme.onSurfaceVariant,
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

  String _resolveReplySenderName(Message replyMessage) {
    if (replyMessage.senderId == widget.currentUserId) {
      return '你';
    }
    if (!widget.isRoom && widget.title.isNotEmpty) {
      return widget.title;
    }
    return '回覆訊息';
  }
}
