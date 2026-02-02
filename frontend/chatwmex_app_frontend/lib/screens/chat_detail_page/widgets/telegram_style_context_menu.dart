// lib/screens/chat_detail_page/widgets/telegram_style_context_menu.dart
import 'package:flutter/material.dart';
import 'dart:ui';
import '../../../models/message.dart' as chat_msg;
import '../utils/message_formatter.dart';

class TelegramStyleContextMenu extends StatefulWidget {
  final chat_msg.Message message;
  final Offset position;
  final bool isMe;
  final VoidCallback onDismiss;
  final Function(String emoji) onReactionAdded;
  final VoidCallback onShowMoreEmojis;
  final VoidCallback onReply;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onForward;
  final VoidCallback onDelete;
  final VoidCallback? onSelectMessage; // 🔥 新增：進入多選模式

  const TelegramStyleContextMenu({
    super.key,
    required this.message,
    required this.position,
    required this.isMe,
    required this.onDismiss,
    required this.onReactionAdded,
    required this.onShowMoreEmojis,
    required this.onReply,
    required this.onCopy,
    required this.onPin,
    required this.onForward,
    required this.onDelete,
    this.onSelectMessage, // 🔥 新增
  });

  @override
  State<TelegramStyleContextMenu> createState() =>
      _TelegramStyleContextMenuState();
}

class _TelegramStyleContextMenuState extends State<TelegramStyleContextMenu>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  final List<AnimationController> _emojiControllers = [];
  final List<Animation<double>> _emojiAnimations = [];

  static const List<String> quickEmojis = [
    '👏',
    '❤️',
    '👍',
    '👎',
    '🔥',
    '🥰',
    '😂',
  ];

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    for (int i = 0; i < quickEmojis.length; i++) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 1200),
        vsync: this,
      );

      final animation = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: -6)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 25,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: -6, end: 0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 25,
        ),
        TweenSequenceItem(
          tween: ConstantTween<double>(0),
          weight: 50,
        ),
      ]).animate(controller);

      _emojiControllers.add(controller);
      _emojiAnimations.add(animation);

      Future.delayed(Duration(milliseconds: i * 40), () {
        if (mounted) controller.repeat();
      });
    }

    _scaleController.forward();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    for (final controller in _emojiControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              _scaleController.reverse().then((_) => widget.onDismiss());
            },
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                color: Colors.black.withOpacity(0.5),
              ),
            ),
          ),
        ),
        Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: _scaleController,
              curve: Curves.easeOutBack,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildEmojiBar(),
                const SizedBox(height: 12),
                _buildMenuWithPreview(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmojiBar() {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...List.generate(
              quickEmojis.length,
              (index) => _buildAnimatedEmoji(quickEmojis[index], index),
            ),
            _buildMoreButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedEmoji(String emoji, int index) {
    return AnimatedBuilder(
      animation: _emojiAnimations[index],
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _emojiAnimations[index].value),
          child: child,
        );
      },
      child: _TappableEmoji(
        emoji: emoji,
        size: 26,
        onTap: () {
          _scaleController.reverse().then((_) {
            widget.onReactionAdded(emoji);
          });
        },
      ),
    );
  }

  Widget _buildMoreButton() {
    return GestureDetector(
      onTap: () {
        _scaleController.reverse().then((_) {
          widget.onShowMoreEmojis();
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.expand_more,
            color: Colors.white70,
            size: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuWithPreview() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 消息預覽區域
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withOpacity(0.1),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.message.content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMessageTime(widget.message.timestamp),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              // 操作列表
              _buildMenuItem(Icons.reply, 'Reply', widget.onReply),
              _buildMenuItem(Icons.content_copy, 'Copy', widget.onCopy),
              _buildMenuItem(Icons.push_pin_outlined, 'Pin', widget.onPin),
              _buildMenuItem(Icons.forward, 'Forward', widget.onForward),

              if (widget.isMe)
                _buildMenuItem(
                  Icons.delete_outline,
                  'Delete',
                  widget.onDelete,
                  isDestructive: true,
                ),

              // 🔥 Select 按鈕 - 進入多選模式
              _buildMenuItem(
                Icons.check_circle_outline,
                'Select',
                () {
                  _scaleController.reverse().then((_) {
                    widget.onDismiss();
                    // 🔥 觸發進入多選模式
                    if (widget.onSelectMessage != null) {
                      widget.onSelectMessage!();
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap,
      {bool isDestructive = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: isDestructive ? Colors.red : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w400,
              ),
            ),
            const Spacer(),
            Icon(
              icon,
              color: isDestructive ? Colors.red : Colors.white70,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _TappableEmoji extends StatefulWidget {
  final String emoji;
  final double size;
  final VoidCallback onTap;

  const _TappableEmoji({
    required this.emoji,
    this.size = 28,
    required this.onTap,
  });

  @override
  State<_TappableEmoji> createState() => _TappableEmojiState();
}

class _TappableEmojiState extends State<_TappableEmoji>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _tapController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _tapController.forward(),
      onTapUp: (_) {
        _tapController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _tapController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Text(
            widget.emoji,
            style: TextStyle(fontSize: widget.size),
          ),
        ),
      ),
    );
  }
}