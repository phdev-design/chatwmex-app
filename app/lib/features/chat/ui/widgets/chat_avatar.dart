import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:flutter/material.dart';

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
    final palette = resolveChatAvatarPalette(
      brightness: Theme.of(context).brightness,
      seed: fallbackText,
    );
    
    // 預設的無圖片替換圖（內建的 CircleAvatar 已經保證是正圓形）
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: palette.backgroundColor,
      child: fallbackIcon != null
          ? Icon(fallbackIcon, color: palette.foregroundColor, size: radius)
          : Text(
              fallbackText,
              style: TextStyle(
                color: palette.foregroundColor,
                fontSize: radius * 0.8,
              ),
            ),
    );

    if (avatarUrl == null || avatarUrl!.isEmpty) {
      debugPrint(
        '$logTag avatar fallback reason=empty_or_null raw_avatar_url=$avatarUrl fallback_text=$fallbackText',
      );
      return fallback;
    }

    final resolvedUrl = Uri.encodeFull(resolveFullUrl(avatarUrl!));

    // 💡 關鍵修改：使用 Container + BoxShape.circle 強制規範正圓形
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle, // 強制外框為正圓形
      ),
      clipBehavior: Clip.antiAlias, // 將裡面的圖片裁切成圓形邊緣
      child: Image.network(
        resolvedUrl,
        fit: BoxFit.cover, // 確保圖片填滿圓形且不變形
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