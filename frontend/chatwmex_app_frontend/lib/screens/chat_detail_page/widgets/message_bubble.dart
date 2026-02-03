import 'package:cached_network_image/cached_network_image.dart';
import 'package:chat2mex_app_frontend/config/api_config.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../models/message.dart' as chat_msg;
import '../utils/avatar_helper.dart';
import '../utils/message_formatter.dart';
import 'message_reactions_widget.dart';
import 'full_emoji_picker_dialog.dart';
import 'telegram_style_context_menu.dart';
import 'video_message_bubble.dart'; // 🔥 新增：視頻消息氣泡
import 'package:flutter/services.dart';

class MessageBubble extends StatefulWidget {
  final chat_msg.Message message;
  final bool isMe;
  final bool isGroup;
  final String? currentUserName;
  final String? currentUserId;
  final Animation<double> fadeAnimation;
  final VoidCallback onLongPress;
  final Function(String emoji) onReactionAdded;
  final VoidCallback? onEnterSelectionMode; // 🔥 新增：進入多選模式回調

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isGroup,
    this.currentUserName,
    this.currentUserId,
    required this.fadeAnimation,
    required this.onLongPress,
    required this.onReactionAdded,
    this.onEnterSelectionMode, // 🔥 新增
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _isSelected = false;

  // Removed duplicate _buildMessageContent

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: widget.isMe
          ? Theme.of(context).colorScheme.primary
          : getAvatarColor(widget.message.senderName),
      child: Text(
        widget.isMe
            ? (widget.currentUserName?.isNotEmpty == true
                ? widget.currentUserName![0].toUpperCase()
                : '我')
            : (widget.message.senderName.isNotEmpty
                ? widget.message.senderName[0].toUpperCase()
                : '?'),
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );

    return FadeTransition(
      opacity: widget.fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment:
              widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!widget.isMe) ...[avatar, const SizedBox(width: 8)],
            Column(
              crossAxisAlignment: widget.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPressStart: (details) {
                    setState(() => _isSelected = true);
                    _showTelegramStyleMenu(context, details.globalPosition);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    transform: _isSelected
                        ? (Matrix4.identity()..scale(0.95))
                        : Matrix4.identity(),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: Radius.circular(widget.isMe ? 20 : 4),
                          bottomRight: Radius.circular(widget.isMe ? 4 : 20),
                        ),
                        boxShadow: _isSelected
                            ? [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.3),
                                  blurRadius: 15,
                                  spreadRadius: 1,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: _buildMessageContent(context),
                    ),
                  ),
                ),
                if (widget.message.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: MessageReactionsWidget(
                      reactions: widget.message.reactions,
                      currentUserId: widget.currentUserId,
                      onReactionTap: (emoji) {
                        widget.onReactionAdded(emoji);
                      },
                    ),
                  ),
              ],
            ),
            if (widget.isMe) ...[const SizedBox(width: 8), avatar],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    // 1. 获取消息内容组件 (图片或文本)
    Widget contentWidget;

    if (widget.message.isDecryptionError) {
      contentWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_person,
                size: 16,
                color: Colors.red[900],
              ),
              const SizedBox(width: 8),
              Text(
                'Unable to decrypt message',
                style: TextStyle(
                  color: Colors.red[900],
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              print('Retry decryption');
              _showDecryptionOptions(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh,
                    size: 14,
                    color: Colors.red[900],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[900],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    } else if (widget.message.type == chat_msg.MessageType.image &&
        widget.message.fileUrl != null) {
      final imageUrl = ApiConfig.getAudioFileUrl(widget.message.fileUrl!);

      contentWidget = GestureDetector(
        onTap: () {
          // 查看大圖
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(backgroundColor: Colors.black),
                backgroundColor: Colors.black,
                body: Center(
                  child: Hero(
                    tag: 'image_${widget.message.id}',
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      placeholder: (context, url) =>
                          const CircularProgressIndicator(),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: Hero(
          tag: 'image_${widget.message.id}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: 200,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 200,
                height: 200,
                color: Colors.grey[300],
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                width: 200,
                height: 200,
                color: Colors.grey[300],
                child: const Icon(Icons.error),
              ),
            ),
          ),
        ),
      );
    } else if (widget.message.type == chat_msg.MessageType.video &&
        widget.message.fileUrl != null) {
      // 🔥 新增：視頻消息渲染
      final videoUrl = ApiConfig.getAudioFileUrl(widget.message.fileUrl!);
      contentWidget = VideoMessageBubble(
        videoUrl: videoUrl,
        isMe: widget.isMe,
      );
    } else {
      contentWidget = Text(
        widget.message.content,
        style: TextStyle(
          color: widget.isMe
              ? Colors.white
              : Theme.of(context).colorScheme.onSurface,
          fontSize: 16,
        ),
      );
    }

    // 2. 包装在气泡样式中 (复用原有样式)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.message.isDecryptionError
            ? Colors.red.shade50
            : (widget.isMe
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surface),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(widget.isMe ? 20 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 20),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.isMe && widget.isGroup)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.message.senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: getAvatarColor(widget.message.senderName),
                ),
              ),
            ),
          // 使用动态内容
          contentWidget,
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                formatMessageTime(widget.message.timestamp),
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isMe
                      ? Colors.white.withOpacity(0.7)
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              if (widget.isMe) ...[
                const SizedBox(width: 4),
                Icon(
                  widget.message.readBy.isNotEmpty ? Icons.done_all : Icons.check,
                  size: 16,
                  color: widget.message.readBy.isNotEmpty
                      ? Colors.blue.shade100 // 在深色背景上蓝色可能看不清，调整一下
                      : Colors.white.withOpacity(0.7),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showTelegramStyleMenu(BuildContext context, Offset position) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (overlayContext) => TelegramStyleContextMenu(
        message: widget.message,
        position: position,
        isMe: widget.isMe,
        onDismiss: () {
          overlayEntry.remove();
          if (mounted) {
            setState(() => _isSelected = false);
          }
        },
        onReactionAdded: (emoji) {
          overlayEntry.remove();
          if (mounted) {
            setState(() => _isSelected = false);
          }
          widget.onReactionAdded(emoji);
        },
        onShowMoreEmojis: () {
          overlayEntry.remove();
          if (mounted) {
            setState(() => _isSelected = false);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              FullEmojiPickerDialog.show(
                context: context,
                onEmojiSelected: widget.onReactionAdded,
              );
            }
          });
        },
        onReply: () {
          overlayEntry.remove();
          if (mounted) setState(() => _isSelected = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('回覆功能開發中')),
          );
        },
        onCopy: () {
          overlayEntry.remove();
          if (mounted) setState(() => _isSelected = false);
          Clipboard.setData(ClipboardData(text: widget.message.content));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('已複製到剪貼板'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        },
        onPin: () {
          overlayEntry.remove();
          if (mounted) setState(() => _isSelected = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('標記功能開發中')),
          );
        },
        onForward: () {
          overlayEntry.remove();
          if (mounted) setState(() => _isSelected = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('轉發功能開發中')),
          );
        },
        onDelete: () {
          overlayEntry.remove();
          if (mounted) setState(() => _isSelected = false);
          widget.onLongPress();
        },
        // 🔥 新增：Select 按鈕觸發進入多選模式
        onSelectMessage: widget.onEnterSelectionMode,
      ),
    );

    overlay.insert(overlayEntry);
  }

  void _showDecryptionOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '解密選項',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重試解密'),
              subtitle: const Text('嘗試重新解密此訊息'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('正在重試解密...')),
                );
                // TODO: 觸發解密邏輯
              },
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key),
              title: const Text('恢復金鑰'),
              subtitle: const Text('檢查金鑰狀態並嘗試修復'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('正在檢查金鑰狀態...')),
                );
                // TODO: 觸發金鑰恢復邏輯
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
