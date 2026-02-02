import 'package:flutter/material.dart';
import '../../../models/chat_room.dart';
import '../utils/avatar_helper.dart';

Future<void> showGroupInfoDialog(BuildContext context, ChatRoom chatRoom) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  chatRoom.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${chatRoom.participants.length} 位成員',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const Divider(height: 32),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: chatRoom.participants.length,
                    itemBuilder: (context, index) {
                      // 🔥 修正：participants 是 List<String>，不是對象
                      final participantId = chatRoom.participants[index];
                      // 從 ID 提取顯示名稱（或者從其他地方獲取用戶信息）
                      final displayName = participantId; // 暫時使用 ID 作為名稱
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: getAvatarColor(displayName),
                          child: Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(displayName),
                        subtitle: Text('ID: $participantId'),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
