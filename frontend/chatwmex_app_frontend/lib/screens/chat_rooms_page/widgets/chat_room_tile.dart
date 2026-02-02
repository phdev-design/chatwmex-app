import 'package:flutter/material.dart';
import '../../../models/chat_room.dart';
import '../utils/avatar_helper.dart';
import '../utils/time_formatter.dart';

class ChatRoomTile extends StatelessWidget {
  final ChatRoom room;
  final Animation<double> animation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ChatRoomTile({
    super.key,
    required this.room,
    required this.animation,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: room.unreadCount > 0
                ? Theme.of(context).colorScheme.primary.withOpacity(0.05)
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    _buildAvatar(context),
                    const SizedBox(width: 12),
                    _buildRoomInfo(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: getAvatarColor(room.name),
            // 添加陰影效果
            boxShadow: [
              BoxShadow(
                color: getAvatarColor(room.name).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              getAvatarText(room.name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (room.isGroup)
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.group, 
                color: Colors.white, 
                size: 12,
              ),
            ),
          ),
        // 在線狀態指示器（可選）
        if (!room.isGroup)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRoomInfo(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasUnread = room.unreadCount > 0;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        room.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                          color: hasUnread 
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // 群組圖標（可選的額外指示）
                    if (room.isGroup) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.people,
                        size: 14,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatTime(room.lastMessageTime),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hasUnread
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  room.lastMessage.isEmpty ? '暫無訊息' : room.lastMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: hasUnread
                        ? theme.colorScheme.onSurface.withOpacity(0.9)
                        : theme.colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                    fontStyle: room.lastMessage.isEmpty ? FontStyle.italic : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasUnread) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    room.unreadCount > 99 ? '99+' : room.unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}