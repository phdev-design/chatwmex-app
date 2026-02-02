import 'package:flutter/material.dart';
import '../../../models/chat_room.dart';

void showRoomOptionsDialog(BuildContext context, ChatRoom room, VoidCallback onMarkAsRead, VoidCallback onLeaveRoom) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示器
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          ListTile(
            leading: const Icon(Icons.mark_chat_read),
            title: const Text('標記為已讀'),
            subtitle: room.unreadCount > 0 
                ? Text('${room.unreadCount} 條未讀訊息')
                : const Text('已全部讀取'),
            onTap: () {
              Navigator.pop(context);
              onMarkAsRead();
            },
          ),
          
          ListTile(
            leading: const Icon(Icons.notifications_off),
            title: const Text('靜音通知'),
            subtitle: const Text('暫時關閉此聊天室的通知'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('靜音功能開發中...'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          
          if (room.isGroup) ...[
            const Divider(),
            ListTile(
              leading: Icon(Icons.exit_to_app, color: Colors.red[600]),
              title: Text(
                '離開群組',
                style: TextStyle(color: Colors.red[600]),
              ),
              subtitle: Text(
                '離開後將無法接收群組訊息',
                style: TextStyle(color: Colors.red[400]),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmLeaveRoomDialog(context, room, onLeaveRoom);
              },
            ),
          ],
          
          // 底部安全間距
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _confirmLeaveRoomDialog(BuildContext context, ChatRoom room, VoidCallback onConfirm) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange[600],
            size: 24,
          ),
          const SizedBox(width: 8),
          const Text('離開聊天室'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('您確定要離開「${room.name}」嗎？'),
          const SizedBox(height: 8),
          Text(
            '離開後您將：\n• 無法接收群組訊息\n• 需要重新邀請才能加入',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '取消',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('離開'),
        ),
      ],
    ),
  );
}