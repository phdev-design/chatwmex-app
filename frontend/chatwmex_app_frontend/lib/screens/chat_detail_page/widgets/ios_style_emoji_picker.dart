// lib/screens/chat_detail_page/widgets/ios_style_emoji_picker.dart
import 'package:flutter/material.dart';
import 'dart:ui';

/// iOS 風格的 Emoji Reaction Picker
class IOSStyleEmojiPicker extends StatelessWidget {
  final Function(String emoji) onEmojiSelected;
  final VoidCallback onDismiss;

  // 常用的 emoji reactions
  static const List<String> defaultEmojis = [
    '❤️', // 愛心
    '👍', // 讚
    '😂', // 笑哭
    '😮', // 驚訝
    '😢', // 哭泣
    '🙏', // 祈禱
    '➕', // 更多
  ];

  const IOSStyleEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景模糊遮罩
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
        
        // Emoji 選擇器
        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[850]?.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: defaultEmojis.map((emoji) {
                  return _buildEmojiButton(emoji);
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmojiButton(String emoji) {
    return InkWell(
      onTap: () => onEmojiSelected(emoji),
      borderRadius: BorderRadius.circular(25),
      child: Container(
        padding: const EdgeInsets.all(10),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 32),
        ),
      ),
    );
  }

  /// 靜態方法：顯示 iOS 風格的 Emoji Picker
  static void show({
    required BuildContext context,
    required Function(String emoji) onEmojiSelected,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => IOSStyleEmojiPicker(
        onEmojiSelected: (emoji) {
          onEmojiSelected(emoji);
          overlayEntry.remove();
        },
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    overlay.insert(overlayEntry);
  }
}
