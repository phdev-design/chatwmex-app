import 'package:flutter/material.dart';

class ChatAvatarPalette {
  final Color backgroundColor;
  final Color foregroundColor;

  const ChatAvatarPalette({
    required this.backgroundColor,
    required this.foregroundColor,
  });
}

ChatAvatarPalette resolveChatAvatarPalette({
  required Brightness brightness,
  required String seed,
}) {
  if (brightness == Brightness.dark) {
    return const ChatAvatarPalette(
      backgroundColor: Color(0xFF2A3942),
      foregroundColor: Colors.white,
    );
  }
  const backgrounds = <Color>[
    Color(0xFFE8F3FF),
    Color(0xFFEAF7EC),
    Color(0xFFFFF4E5),
    Color(0xFFF2ECFF),
    Color(0xFFFFEDEF),
    Color(0xFFE9F7F8),
  ];
  const foregrounds = <Color>[
    Color(0xFF225F9E),
    Color(0xFF2E7D32),
    Color(0xFFA05A00),
    Color(0xFF6A4BB1),
    Color(0xFFA33A54),
    Color(0xFF146C72),
  ];
  final index = stableChatSeedHash(seed) % backgrounds.length;
  return ChatAvatarPalette(
    backgroundColor: backgrounds[index],
    foregroundColor: foregrounds[index],
  );
}

int stableChatSeedHash(String value) {
  if (value.isEmpty) return 0;
  var hash = 2166136261;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0x7fffffff;
  }
  return hash;
}

class ChatSurfaceTokens {
  final Color panelBackground;
  final Color composerBackground;
  final Color replyBackground;
  final Color bubbleIncomingBackground;
  final Color bubbleOutgoingBackground;
  final Color bubbleText;
  final Color bubbleOutgoingText; // 新增：發出泡泡的專屬文字色
  final Color subtleText;
  final Color bubbleOutgoingSubtleText; // 新增：發出泡泡的專屬輔助色 (時間/狀態)
  final Color dateDividerBackground;
  final Color dateDividerText;
  final Color menuBackground;
  final Color menuEmojiBackground;
  final Color imageFallbackBackground;
  final Color accent;
  final Color unreadBannerBackground;
  final Color unreadBannerForeground;
  final Color unreadBadgeBackground;
  final Color unreadBadgeForeground;
  final Color roomListTimeText;
  final Color roomListSubtitleRead;
  final Color roomListSubtitleUnread;

  const ChatSurfaceTokens({
    required this.panelBackground,
    required this.composerBackground,
    required this.replyBackground,
    required this.bubbleIncomingBackground,
    required this.bubbleOutgoingBackground,
    required this.bubbleText,
    required this.bubbleOutgoingText,
    required this.subtleText,
    required this.bubbleOutgoingSubtleText,
    required this.dateDividerBackground,
    required this.dateDividerText,
    required this.menuBackground,
    required this.menuEmojiBackground,
    required this.imageFallbackBackground,
    required this.accent,
    required this.unreadBannerBackground,
    required this.unreadBannerForeground,
    required this.unreadBadgeBackground,
    required this.unreadBadgeForeground,
    required this.roomListTimeText,
    required this.roomListSubtitleRead,
    required this.roomListSubtitleUnread,
  });
}

ChatSurfaceTokens resolveChatSurfaceTokens({
  required ColorScheme colorScheme,
  required Brightness brightness,
}) {
  final isDark = brightness == Brightness.dark;
  return ChatSurfaceTokens(
    panelBackground: isDark
        ? const Color(0xFF111B21)
        : colorScheme.surfaceContainerLow,
    composerBackground: isDark ? const Color(0xFF2A3942) : colorScheme.surface,
    replyBackground: isDark
        ? const Color(0xFF1E2A30)
        : colorScheme.surfaceContainerHigh,
    bubbleIncomingBackground: isDark
        ? const Color(0xFF202C33)
        : colorScheme.surfaceContainerHighest,
    bubbleOutgoingBackground: isDark
        ? const Color(0xFF005C4B)
        : colorScheme.primaryContainer,
    bubbleText: isDark ? Colors.white : colorScheme.onSurface,
    bubbleOutgoingText: Colors.white, // 不論深淺色，藍色/綠色發送泡泡上一律白字
    subtleText: isDark ? Colors.grey.shade400 : colorScheme.onSurfaceVariant,
    bubbleOutgoingSubtleText: isDark
        ? Colors.grey.shade400
        : Colors.white70, // 發送泡泡上的時間顏色
    dateDividerBackground: isDark
        ? const Color(0xFF2A3942)
        : colorScheme.surfaceContainerHighest,
    dateDividerText: isDark
        ? Colors.grey.shade400
        : colorScheme.onSurfaceVariant,
    menuBackground: isDark ? const Color(0xFF1E2A30) : colorScheme.surface,
    menuEmojiBackground: isDark
        ? const Color(0xFF2A3942)
        : colorScheme.surfaceContainerHighest,
    imageFallbackBackground: isDark
        ? const Color(0xFF2A3942)
        : colorScheme.surfaceContainerHighest,
    accent: const Color(0xFF53BDEB),
    unreadBannerBackground: isDark
        ? const Color(0xFF005C4B)
        : colorScheme.primaryContainer,
    unreadBannerForeground: isDark
        ? Colors.white
        : colorScheme.onPrimaryContainer,
    unreadBadgeBackground: isDark ? Colors.redAccent : colorScheme.error,
    unreadBadgeForeground: isDark ? Colors.white : colorScheme.onError,
    roomListTimeText: colorScheme.onSurfaceVariant,
    roomListSubtitleRead: colorScheme.onSurfaceVariant,
    roomListSubtitleUnread: colorScheme.onSurface,
  );
}
