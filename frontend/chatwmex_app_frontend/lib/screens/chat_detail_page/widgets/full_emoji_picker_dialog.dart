// lib/screens/chat_detail_page/widgets/full_emoji_picker_dialog.dart
import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart' as foundation;

/// 完整的 Emoji Picker 對話框
class FullEmojiPickerDialog extends StatelessWidget {
  final Function(String emoji) onEmojiSelected;

  const FullEmojiPickerDialog({
    super.key,
    required this.onEmojiSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 100),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[900]?.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 標題欄
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '選擇表情符號',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                
                // Emoji Picker
                SizedBox(
                  height: 400,
                  child: EmojiPicker(
                    onEmojiSelected: (category, emoji) {
                      onEmojiSelected(emoji.emoji);
                      Navigator.pop(context);
                    },
                    config: Config(
                      checkPlatformCompatibility: true,
                      emojiViewConfig: EmojiViewConfig(
                        emojiSizeMax: 28 * (foundation.defaultTargetPlatform == TargetPlatform.iOS ? 1.30 : 1.0),
                        columns: 7,
                        verticalSpacing: 0,
                        horizontalSpacing: 0,
                        gridPadding: EdgeInsets.zero,
                        backgroundColor: Colors.transparent,
                        buttonMode: ButtonMode.MATERIAL,
                        recentsLimit: 28,
                        replaceEmojiOnLimitExceed: false,
                      ),
                      skinToneConfig: const SkinToneConfig(
                        enabled: true,
                        dialogBackgroundColor: Color(0xFF2C2C2E),
                      ),
                      categoryViewConfig: CategoryViewConfig(
                        backgroundColor: Colors.transparent,
                        indicatorColor: Theme.of(context).colorScheme.primary,
                        iconColorSelected: Theme.of(context).colorScheme.primary,
                        iconColor: Colors.grey,
                        tabBarHeight: 46,
                      ),
                      bottomActionBarConfig: const BottomActionBarConfig(
                        enabled: false,
                      ),
                      searchViewConfig: SearchViewConfig(
                        backgroundColor: Colors.transparent,
                        buttonIconColor: Theme.of(context).colorScheme.primary,
                        hintText: '搜尋表情符號...',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 顯示完整 Emoji Picker
  static Future<void> show({
    required BuildContext context,
    required Function(String emoji) onEmojiSelected,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => FullEmojiPickerDialog(
        onEmojiSelected: onEmojiSelected,
      ),
    );
  }
}