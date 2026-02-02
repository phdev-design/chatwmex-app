// lib/screens/chat_detail_page/widgets/voice_message_bubble.dart
import 'package:flutter/material.dart';
import '../../../models/voice_message.dart' as voice_msg;
import '../../../widgets/voice_message_widget.dart';
import '../utils/avatar_helper.dart';

class VoiceMessageBubble extends StatelessWidget {
  final voice_msg.VoiceMessage voiceMessage;
  final bool isMe;
  final Animation<double> fadeAnimation;
  final VoidCallback onLongPress;
  final bool isCompact; // 🔥 新增：緊湊模式（用於多選）

  const VoiceMessageBubble({
    super.key,
    required this.voiceMessage,
    required this.isMe,
    required this.fadeAnimation,
    required this.onLongPress,
    this.isCompact = false, // 🔥 默認為 false
  });

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: isMe
          ? Theme.of(context).colorScheme.primary
          : getAvatarColor(voiceMessage.senderName),
      child: Text(
        isMe
            ? '我'
            : (voiceMessage.senderName.isNotEmpty 
                ? voiceMessage.senderName[0].toUpperCase() 
                : '?'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    // 🔥 緊湊模式：只返回語音組件（用於多選模式，由外層處理對齊）
    if (isCompact) {
      return FadeTransition(
        opacity: fadeAnimation,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[avatar, const SizedBox(width: 8)],
              Flexible(
                child: VoiceMessageWidget(
                  key: ValueKey(voiceMessage.id),
                  voiceMessage: voiceMessage,
                  isFromCurrentUser: isMe,
                  senderAvatarUrl: null,
                  currentUserAvatarUrl: null,
                ),
              ),
              if (isMe) ...[const SizedBox(width: 8), avatar],
            ],
          ),
        ),
      );
    }

    // 🔥 正常模式：完整的語音消息氣泡
    return FadeTransition(
      opacity: fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[avatar, const SizedBox(width: 8)],
              Flexible(
                child: VoiceMessageWidget(
                  key: ValueKey(voiceMessage.id),
                  voiceMessage: voiceMessage,
                  isFromCurrentUser: isMe,
                  senderAvatarUrl: null,
                  currentUserAvatarUrl: null,
                ),
              ),
              if (isMe) ...[const SizedBox(width: 8), avatar],
            ],
          ),
        ),
      ),
    );
  }
}