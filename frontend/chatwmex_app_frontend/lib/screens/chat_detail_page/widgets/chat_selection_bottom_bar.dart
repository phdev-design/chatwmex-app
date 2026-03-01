// lib/screens/chat_detail_page/widgets/chat_selection_bottom_bar.dart
import 'package:flutter/material.dart';

/// Telegram 風格的多選模式底部操作欄
class ChatSelectionBottomBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onForward;
  final VoidCallback? onCopy; // 可選：複製功能

  const ChatSelectionBottomBar({
    super.key,
    required this.selectedCount,
    required this.onDelete,
    required this.onShare,
    required this.onForward,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 🔥 刪除按鈕
              _buildActionButton(
                context: context,
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: selectedCount > 0 ? onDelete : null,
                color: Colors.red,
              ),
              
              // 🔥 分享按鈕
              _buildActionButton(
                context: context,
                icon: Icons.share,
                label: 'Share',
                onTap: selectedCount > 0 ? onShare : null,
              ),
              
              // 🔥 轉發按鈕
              _buildActionButton(
                context: context,
                icon: Icons.forward,
                label: 'Forward',
                onTap: selectedCount > 0 ? onForward : null,
              ),
              
              // 🔥 可選：複製按鈕
              if (onCopy != null)
                _buildActionButton(
                  context: context,
                  icon: Icons.content_copy,
                  label: 'Copy',
                  onTap: selectedCount > 0 ? onCopy : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    final isEnabled = onTap != null;
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isEnabled ? effectiveColor : Colors.grey,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled ? effectiveColor : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
