// lib/screens/chat_detail_page/widgets/telegram_style_emoji_picker.dart
import 'package:flutter/material.dart';
import 'dart:ui';

/// Telegram 風格的動態 Emoji Picker
class TelegramStyleEmojiPicker extends StatefulWidget {
  final Function(String emoji) onEmojiSelected;
  final VoidCallback onDismiss;

  // 常用的 emoji reactions
  static const List<String> defaultEmojis = [
    '❤️', '👍', '😂', '😮', '😢', '🙏', '➕',
  ];

  const TelegramStyleEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  /// 🔥 靜態方法：顯示 Telegram 風格的 Emoji Picker
  static void show({
    required BuildContext context,
    required Function(String emoji) onEmojiSelected,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => TelegramStyleEmojiPicker(
        onEmojiSelected: (emoji) {
          onEmojiSelected(emoji);
          overlayEntry.remove();
        },
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    overlay.insert(overlayEntry);
  }

  @override
  State<TelegramStyleEmojiPicker> createState() =>
      _TelegramStyleEmojiPickerState();
}

class _TelegramStyleEmojiPickerState extends State<TelegramStyleEmojiPicker>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  final List<AnimationController> _emojiControllers = [];
  final List<Animation<double>> _emojiAnimations = [];

  @override
  void initState() {
    super.initState();

    // 整體縮放動畫
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 為每個 emoji 創建彈跳動畫
    for (int i = 0; i < TelegramStyleEmojiPicker.defaultEmojis.length; i++) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 1500),
        vsync: this,
      );

      final animation = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: -8)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 30,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: -8, end: 0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 30,
        ),
        TweenSequenceItem(
          tween: ConstantTween<double>(0),
          weight: 40,
        ),
      ]).animate(controller);

      _emojiControllers.add(controller);
      _emojiAnimations.add(animation);

      // 錯開每個 emoji 的動畫時間
      Future.delayed(Duration(milliseconds: i * 50), () {
        if (mounted) {
          controller.repeat();
        }
      });
    }

    // 啟動整體縮放動畫
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
        // 背景模糊遮罩
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              _scaleController.reverse().then((_) => widget.onDismiss());
            },
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),
        ),

        // Emoji 選擇器
        Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: _scaleController,
              curve: Curves.easeOutBack,
            ),
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[850]?.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    TelegramStyleEmojiPicker.defaultEmojis.length,
                    (index) => _buildAnimatedEmojiButton(
                      TelegramStyleEmojiPicker.defaultEmojis[index],
                      index,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedEmojiButton(String emoji, int index) {
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
        onTap: () {
          _scaleController.reverse().then((_) {
            widget.onEmojiSelected(emoji);
          });
        },
      ),
    );
  }
}

/// 可點擊的 Emoji，帶有 hover 和點擊效果
class _TappableEmoji extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _TappableEmoji({
    required this.emoji,
    required this.onTap,
  });

  @override
  State<_TappableEmoji> createState() => _TappableEmojiState();
}

class _TappableEmojiState extends State<_TappableEmoji>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
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
      onTapDown: (_) {
        setState(() => _isPressed = true);
        _tapController.forward();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _tapController.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        _tapController.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _isPressed
                ? Colors.white.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 32),
          ),
        ),
      ),
    );
  }
}