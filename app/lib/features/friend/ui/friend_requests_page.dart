import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/friend/providers/friend_provider.dart';

class FriendRequestsPage extends ConsumerWidget {
  const FriendRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendViewModelProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 完美對標 iOS / 參考圖片的背景與卡片配色
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          '交友邀請',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: textColor,
          ),
        ),
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: state.requests.isEmpty
            ? _buildEmptyState(isDark, textColor, subTextColor)
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 8),
                    child: Text(
                      '待處理邀請 (${state.requests.length})'.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white54 : Colors.grey[600],
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Column(
                        children: List.generate(state.requests.length, (index) {
                          final req = state.requests[index];
                          final isLast = index == state.requests.length - 1;
                          final displayName = req.senderUsername.isNotEmpty
                              ? req.senderUsername
                              : req.senderId;
                          final dateStr =
                              req.createdAt.toString().split(' ')[0]; // 簡易日期擷取

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    // ─── 大頭貼 ───
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.grey.shade200,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.grey.shade500,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // ─── 名稱與日期 ───
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            displayName,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: textColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '發送於 $dateStr',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: subTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // ─── 操作按鈕 (拒絕 / 接受) ───
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildActionButton(
                                          icon: Icons.close_rounded,
                                          bgColor: isDark
                                              ? Colors.white12
                                              : Colors.grey.shade200,
                                          iconColor: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                          onTap: () {
                                            ref
                                                .read(friendViewModelProvider
                                                    .notifier)
                                                .rejectRequest(req.id);
                                          },
                                        ),
                                        const SizedBox(width: 10),
                                        _buildActionButton(
                                          icon: Icons.check_rounded,
                                          bgColor: const Color(0xFF007AFF), // 藍色
                                          iconColor: Colors.white,
                                          onTap: () {
                                            ref
                                                .read(friendViewModelProvider
                                                    .notifier)
                                                .acceptRequest(req.id);
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (!isLast)
                                Divider(
                                  height: 1,
                                  indent: 76, // 46 (頭貼) + 16 (左邊距) + 14 (間距)
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.1)
                                      : Colors.black.withValues(alpha: 0.05),
                                ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ─── 按鈕建構器 ───
  Widget _buildActionButton({
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }

  // ─── 空狀態畫面 (Empty State) ───
  Widget _buildEmptyState(bool isDark, Color textColor, Color subTextColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_add_disabled_rounded,
                size: 64,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '目前沒有交友邀請',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '當有用戶發送交友邀請給您時，將會顯示於此處。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: subTextColor,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}