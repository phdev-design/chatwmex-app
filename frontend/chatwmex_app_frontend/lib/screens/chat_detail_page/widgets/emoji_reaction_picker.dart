// lib/screens/chat_detail_page/widgets/emoji_reaction_picker.dart
import 'package:flutter/material.dart';

class EmojiReactionPicker extends StatelessWidget {
  final Function(String emoji) onEmojiSelected;
  final Offset position;

  // 常用的 emoji reactions
  static const List<String> defaultEmojis = [
    '👍', // 讚
    '❤️', // 愛心
    '😂', // 笑哭
    '😮', // 驚訝
    '😢', // 哭泣
    '🙏', // 祈禱
    '👏', // 鼓掌
    '➕', // 更多
  ];

  const EmojiReactionPicker({
    super.key,
    required this.onEmojiSelected,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy - 60, // 显示在消息上方
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: defaultEmojis.map((emoji) {
              return InkWell(
                onTap: () => onEmojiSelected(emoji),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// 顯示 Emoji Picker 的靜態方法
  static void show({
    required BuildContext context,
    required Offset position,
    required Function(String emoji) onEmojiSelected,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 點擊背景關閉
          Positioned.fill(
            child: GestureDetector(
              onTap: () => overlayEntry.remove(),
              child: Container(color: Colors.transparent),
            ),
          ),
          // Emoji Picker
          EmojiReactionPicker(
            position: position,
            onEmojiSelected: (emoji) {
              onEmojiSelected(emoji);
              overlayEntry.remove();
            },
          ),
        ],
      ),
    );

    overlay.insert(overlayEntry);
  }
}
