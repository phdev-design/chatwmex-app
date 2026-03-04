import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:flutter/material.dart';

class ChatAppBarTitleBlock extends StatelessWidget {
  final String roomId;
  final String title;
  final String? avatarUrl;
  final VoidCallback onTap;

  const ChatAppBarTitleBlock({
    super.key,
    required this.roomId,
    required this.title,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Hero(
            tag: 'avatar_$roomId',
            child: ChatAvatar(
              radius: 18,
              avatarUrl: avatarUrl,
              fallbackText: title.isNotEmpty ? title[0].toUpperCase() : '',
              logTag: 'chat_appbar',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '點按以查看聯絡人資料',
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
