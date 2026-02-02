// lib/screens/chat_detail_page/widgets/chat_selection_app_bar.dart
import 'package:flutter/material.dart';

/// Telegram 風格的多選模式 AppBar
class ChatSelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onForward;

  const ChatSelectionAppBar({
    super.key,
    required this.selectedCount,
    required this.onCancel,
    required this.onSelectAll,
    required this.onDelete,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: onCancel,
      ),
      title: Text(
        selectedCount > 0 ? '$selectedCount Selected' : 'Select Messages',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      actions: [
        // 🔥 移除這裡的操作按鈕，改為在底部顯示
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}