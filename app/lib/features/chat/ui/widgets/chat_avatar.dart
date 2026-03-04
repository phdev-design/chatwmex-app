import 'package:app/features/chat/utils/chat_url_utils.dart';
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
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF2A3942),
      child: fallbackIcon != null
          ? Icon(fallbackIcon, color: Colors.white, size: radius)
          : Text(
              fallbackText,
              style: TextStyle(color: Colors.white, fontSize: radius * 0.8),
            ),
    );
    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return fallback;
    }
    final resolvedUrl = Uri.encodeFull(resolveFullUrl(avatarUrl));
    return ClipOval(
      child: Image.network(
        resolvedUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('$logTag avatar load failed url=$resolvedUrl error=$error');
          return fallback;
        },
      ),
    );
  }
}
