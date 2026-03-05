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
    // debugPrint('$logTag avatar raw_avatar_url=$avatarUrl');
    final resolvedUrl = Uri.encodeFull(resolveFullUrl(avatarUrl));
    // debugPrint('$logTag avatar resolved_url=$resolvedUrl');
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
