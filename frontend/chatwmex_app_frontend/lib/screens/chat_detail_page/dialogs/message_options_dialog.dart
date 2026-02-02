// lib/screens/chat_detail_page/dialogs/message_options_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/message.dart' as chat_msg;

Future<void> showMessageOptionsDialog(
  BuildContext context, {
  required chat_msg.Message message,
  required bool isMe,
  required Function(chat_msg.Message) onDelete,
  Function(chat_msg.Message)? onReply,
  Function(chat_msg.Message)? onForward,
  VoidCallback? onAddReaction,
}) async {
  // 🔥 參考 WhatsApp 的設計：使用更現代的 bottom sheet
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🔥 頂部拖動指示器
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 🔥 消息預覽（參考 WhatsApp）
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 🔥 操作選項（參考 WhatsApp 順序）
            
            // 1. 回覆
            if (onReply != null)
              _buildOptionTile(
                context: context,
                icon: Icons.reply,
                title: '回覆',
                onTap: () {
                  Navigator.pop(context);
                  onReply(message);
                },
              ),

            // 2. 複製（最常用功能）
            _buildOptionTile(
              context: context,
              icon: Icons.copy,
              title: '複製',
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: message.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text('已複製到剪貼板'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              },
            ),

            // 3. 轉發
            if (onForward != null)
              _buildOptionTile(
                context: context,
                icon: Icons.forward,
                title: '轉發',
                onTap: () {
                  Navigator.pop(context);
                  onForward(message);
                },
              ),

            // 4. 標上星號
            _buildOptionTile(
              context: context,
              icon: Icons.star_outline,
              title: '標上星號',
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('標記功能開發中')),
                );
              },
            ),

            // 5. 添加 Reaction
            if (onAddReaction != null)
              _buildOptionTile(
                context: context,
                icon: Icons.emoji_emotions_outlined,
                title: '添加表情回應',
                onTap: () {
                  Navigator.pop(context);
                  onAddReaction();
                },
              ),

            const Divider(height: 1),

            // 6. 刪除（危險操作，放在最後）
            if (isMe)
              _buildOptionTile(
                context: context,
                icon: Icons.delete_outline,
                iconColor: Colors.red,
                title: '刪除',
                titleColor: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(context, message, onDelete);
                },
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

// 🔥 統一的選項樣式
Widget _buildOptionTile({
  required BuildContext context,
  required IconData icon,
  required String title,
  required VoidCallback onTap,
  Color? iconColor,
  Color? titleColor,
}) {
  final effectiveIconColor = iconColor ?? Theme.of(context).colorScheme.onSurface;
  final effectiveTitleColor = titleColor ?? Theme.of(context).colorScheme.onSurface;

  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(
            icon,
            color: effectiveIconColor,
            size: 24,
          ),
          const SizedBox(width: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: effectiveTitleColor,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    ),
  );
}

// 🔥 刪除確認對話框（參考 WhatsApp）
void _showDeleteConfirmation(
  BuildContext context,
  chat_msg.Message message,
  Function(chat_msg.Message) onDelete,
) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('刪除消息？'),
      content: const Text('此消息將被永久刪除。'),
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
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onDelete(message);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 12),
                    Text('消息已刪除'),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          },
          child: const Text(
            '刪除',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}