import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:app/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// 訊息已讀資訊底部彈窗
/// - 群組聊天：顯示誰已讀
/// - 一對一聊天：顯示送達時間和已讀時間
class MessageReadInfoSheet extends ConsumerStatefulWidget {
  final Message msg;
  final bool isRoom;
  final String roomId;
  final Map<String, String> userAvatarUrls;

  const MessageReadInfoSheet({
    super.key,
    required this.msg,
    required this.isRoom,
    required this.roomId,
    required this.userAvatarUrls,
  });

  @override
  ConsumerState<MessageReadInfoSheet> createState() =>
      _MessageReadInfoSheetState();
}

class _MessageReadInfoSheetState extends ConsumerState<MessageReadInfoSheet> {
  Map<String, String> _memberNames = {};
  Map<String, String> _memberAvatars = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.isRoom) {
      _loadMemberProfiles();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMemberProfiles() async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final members = await chatRepo.getRoomMemberProfiles(widget.roomId);
      final names = <String, String>{};
      final avatars = <String, String>{};
      for (final member in members) {
        names[member.id] = member.username.isNotEmpty
            ? member.username
            : (member.firstName ?? member.id);
        if (member.avatarUrl != null && member.avatarUrl!.isNotEmpty) {
          avatars[member.id] = member.avatarUrl!;
        }
      }
      if (mounted) {
        setState(() {
          _memberNames = names;
          _memberAvatars = {...widget.userAvatarUrls, ...avatars};
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: Theme.of(context).brightness,
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖曳指示條
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 標題
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              widget.isRoom ? '訊息資訊' : '訊息資訊',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          const Divider(height: 1),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (widget.isRoom)
            _buildGroupReadInfo(context, isDark, tokens)
          else
            _buildDmReadInfo(context, isDark, tokens),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  /// 群組聊天：顯示已讀成員列表
  Widget _buildGroupReadInfo(
    BuildContext context,
    bool isDark,
    ChatSurfaceTokens tokens,
  ) {
    final readBy = widget.msg.readBy;
    // 過濾掉發送者自己
    final readers = readBy.where((id) => id != widget.msg.senderId).toList();

    if (readers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.done_all,
              size: 32,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              '尚未有人已讀',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.done_all, size: 16, color: tokens.accent),
                const SizedBox(width: 6),
                Text(
                  '已讀 ${readers.length} 人',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.accent,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: readers.length,
              itemBuilder: (context, index) {
                final userId = readers[index];
                final name = _memberNames[userId] ?? userId.substring(0, 8);
                final avatarUrl = _memberAvatars[userId];
                return ListTile(
                  dense: true,
                  leading: ChatAvatar(
                    radius: 18,
                    avatarUrl: avatarUrl,
                    fallbackText: name.isNotEmpty
                        ? name[0].toUpperCase()
                        : '?',
                    logTag: 'read_info',
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 一對一聊天：顯示送達和已讀時間
  Widget _buildDmReadInfo(
    BuildContext context,
    bool isDark,
    ChatSurfaceTokens tokens,
  ) {
    final msg = widget.msg;
    final timeFormat = DateFormat('yyyy/MM/dd HH:mm:ss');
    final sentTime = timeFormat.format(msg.createdAt);

    final isDelivered = msg.status == MessageStatus.delivered ||
        msg.status == MessageStatus.read;
    final isRead = msg.status == MessageStatus.read;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // 已送出
          _buildStatusRow(
            icon: Icons.check,
            label: '已送出',
            time: sentTime,
            color: isDark ? Colors.white70 : Colors.black54,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          // 已送達
          _buildStatusRow(
            icon: Icons.done_all,
            label: '已送達',
            time: isDelivered ? '已送達' : '等待中...',
            color: isDelivered
                ? (isDark ? Colors.white70 : Colors.black54)
                : Colors.grey,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          // 已讀
          _buildStatusRow(
            icon: Icons.done_all,
            label: '已讀',
            time: isRead && msg.readAt != null
                ? timeFormat.format(msg.readAt!)
                : (isRead ? '已讀' : '尚未已讀'),
            color: isRead ? tokens.accent : Colors.grey,
            isDark: isDark,
            isAccent: isRead,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required String time,
    required Color color,
    required bool isDark,
    bool isAccent = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: TextStyle(
                  fontSize: 13,
                  color: isAccent
                      ? color
                      : (isDark ? Colors.white54 : Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
