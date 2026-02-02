import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../models/message.dart' as chat_msg;
import '../utils/avatar_helper.dart';
import '../utils/message_formatter.dart';
import 'message_reactions_widget.dart';
import 'full_emoji_picker_dialog.dart';
import 'telegram_style_context_menu.dart';
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isMe
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
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
          Text(
            widget.message.content,
            style: TextStyle(
              color: widget.isMe
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatMessageTime(widget.message.timestamp),
            style: TextStyle(
              fontSize: 12,
              color: widget.isMe
                  ? Colors.white.withOpacity(0.7)
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
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
}
