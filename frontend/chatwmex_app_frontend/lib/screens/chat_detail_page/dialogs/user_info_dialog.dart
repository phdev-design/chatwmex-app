import 'package:flutter/material.dart';
import '../../../models/chat_room.dart';
import '../utils/avatar_helper.dart';

Future<void> showUserInfoDialog({
  required BuildContext context,
  required ChatRoom chatRoom,
  required String? currentUserId,
  required bool isBlocked,
  required VoidCallback onToggleBlock,
}) async {
  final otherUserId = chatRoom.participants
      .firstWhere((id) => id != currentUserId, orElse: () => 'Unknown User');
  
  // 這裡假設 chatRoom.name 就是對方的名字（在 1-on-1 聊天中通常如此）
  final displayName = chatRoom.name;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return Container(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 24),
            // Avatar
            CircleAvatar(
              radius: 50,
              backgroundColor: getAvatarColor(displayName),
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 40,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Name
            Text(
              displayName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            // ID
            Text(
              'ID: $otherUserId',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 32),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.notifications,
                  label: '通知',
                  onTap: () {
                    // TODO: Implement notification settings
                  },
                ),
                _buildActionButton(
                  context,
                  icon: Icons.search,
                  label: '搜尋',
                  onTap: () {
                    // TODO: Implement search
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            // Block Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Close dialog first
                  onToggleBlock();
                },
                icon: Icon(
                  isBlocked ? Icons.lock_open : Icons.block,
                  color: isBlocked ? null : Theme.of(context).colorScheme.error,
                ),
                label: Text(
                  isBlocked ? '解除封鎖' : '封鎖用戶',
                  style: TextStyle(
                    color: isBlocked ? null : Theme.of(context).colorScheme.error,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(
                    color: isBlocked
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

Widget _buildActionButton(BuildContext context,
    {required IconData icon,
    required String label,
    required VoidCallback onTap}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}
