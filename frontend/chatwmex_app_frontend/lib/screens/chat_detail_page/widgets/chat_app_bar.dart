// lib/screens/chat_detail_page/widgets/chat_app_bar.dart
import 'package:flutter/material.dart';
import '../../../models/chat_room.dart';
import '../dialogs/group_management_dialogs.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String chatDisplayName;
  final bool isConnected;
  final ChatRoom chatRoom;
  final String? currentUserId; // 🔥 添加這個參數
  final String? typingStatus; // 🔥 新增：Typing 狀態
  final bool isBlocked; // 🔥 新增：封鎖狀態
  final VoidCallback? onToggleBlock; // 🔥 新增：封鎖切換回調
  final VoidCallback onShowDebugInfo;
  final VoidCallback onShowGroupInfo;

  const ChatAppBar({
    super.key,
    required this.chatDisplayName,
    required this.isConnected,
    required this.chatRoom,
    this.currentUserId, // 🔥 添加這個參數
    this.typingStatus, // 🔥 新增：Typing 狀態
    this.isBlocked = false,
    this.onToggleBlock,
    required this.onShowDebugInfo,
    required this.onShowGroupInfo,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chatDisplayName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (!isConnected)
            Text(
              '連線中斷',
              style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            )
          else if (typingStatus != null && typingStatus!.isNotEmpty)
            Text(
              typingStatus!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (chatRoom.isGroup && chatRoom.participants.isNotEmpty)
            Text(
              '${chatRoom.participants.length} 位成員',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.bug_report),
          onPressed: onShowDebugInfo,
          tooltip: '調試信息',
        ),
        if (!chatRoom.isGroup && onToggleBlock != null)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'toggle_block') {
                onToggleBlock!();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_block',
                child: ListTile(
                  leading: Icon(
                    isBlocked ? Icons.lock_open : Icons.block,
                    color:
                        isBlocked ? null : Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    isBlocked ? '解除封鎖' : '封鎖用戶',
                    style: TextStyle(
                      color: isBlocked
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        if (chatRoom.isGroup)
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'group_info':
                  onShowGroupInfo();
                  break;
                case 'invite_members':
                  showInviteMembersDialog(
                    context,
                    chatRoomId: chatRoom.id,
                    currentParticipants: chatRoom.participants,
                    currentUserId: currentUserId,
                  );
                  break;
                case 'edit_name':
                  showEditGroupNameDialog(
                    context,
                    chatRoomId: chatRoom.id,
                    currentName: chatRoom.name,
                  );
                  break;
                case 'leave_group':
                  showLeaveGroupDialog(context, chatRoomId: chatRoom.id);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'group_info',
                child: ListTile(
                  leading: Icon(Icons.info),
                  title: Text('群組資訊'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'invite_members',
                child: ListTile(
                  leading: Icon(Icons.person_add),
                  title: Text('邀請成員'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'edit_name',
                child: ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('修改群組名稱'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'leave_group',
                child: ListTile(
                  leading: Icon(Icons.exit_to_app, color: Colors.red),
                  title: Text('離開群組', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          )
        else
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: onShowGroupInfo,
            tooltip: '用戶資訊',
          ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
