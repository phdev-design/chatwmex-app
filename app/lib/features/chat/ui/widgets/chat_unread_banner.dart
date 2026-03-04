import 'package:flutter/material.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';

class ChatUnreadBanner extends StatelessWidget {
  final int unreadCount;
  final Animation<Offset> arrowOffset;
  final VoidCallback onTap;

  const ChatUnreadBanner({
    super.key,
    required this.unreadCount,
    required this.arrowOffset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = resolveChatSurfaceTokens(
      colorScheme: Theme.of(context).colorScheme,
      brightness: Theme.of(context).brightness,
    );
    return GestureDetector(
      onTap: onTap,
      child: SlideTransition(
        position: arrowOffset,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.unreadBannerBackground,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_arrow_down,
                color: tokens.unreadBannerForeground,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                unreadCount > 0 ? '$unreadCount 則新訊息' : '新訊息',
                style: TextStyle(
                  color: tokens.unreadBannerForeground,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
