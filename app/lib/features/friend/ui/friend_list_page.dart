import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/features/friend/providers/friend_provider.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';

class FriendListPage extends ConsumerStatefulWidget {
  const FriendListPage({super.key});

  @override
  ConsumerState<FriendListPage> createState() => _FriendListPageState();
}

class _FriendListPageState extends ConsumerState<FriendListPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(friendViewModelProvider.notifier).loadAll(),
    );
  }

  Future<void> _confirmUnfriend(String friendId, String friendUsername) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBgColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('解除好友', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        content: Text(
          '確定要與 $friendUsername 解除好友關係嗎？',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('解除好友', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(friendViewModelProvider.notifier).unfriend(friendId);
    }
  }

  Future<void> _openChat(String friendId, String friendUsername) async {
    final storage = ref.read(storageServiceProvider);
    final myId = await storage.read('user_id');
    final token = await storage.read('jwt_token');
    if (mounted && myId != null && token != null) {
      context.push(
        '/chat',
        extra: {
          'roomId': friendId,
          'title': friendUsername,
          'isRoom': false,
          'currentUserId': myId,
          'token': token,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(friendViewModelProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 統一主題配色
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          '朋友列表',
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
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textColor),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: textColor),
            onPressed: () =>
                ref.read(friendViewModelProvider.notifier).loadAll(),
          ),
        ],
      ),
      body: SafeArea(
        child: () {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null) {
            return _buildErrorState(state.error!, isDark, textColor, subTextColor);
          }
          if (state.friends.isEmpty) {
            return _buildEmptyState(isDark, textColor, subTextColor);
          }

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  '我的好友 (${state.friends.length})'.toUpperCase(),
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
                    children: List.generate(state.friends.length, (index) {
                      final friend = state.friends[index];
                      final isLast = index == state.friends.length - 1;

                      return Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: ChatAvatar(
                              avatarUrl: null,
                              radius: 22,
                              fallbackText: friend.username.isNotEmpty
                                  ? friend.username[0].toUpperCase()
                                  : '?',
                              fallbackIcon: Icons.person,
                              logTag: 'friend_list',
                            ),
                            title: Text(
                              friend.username,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                friend.email,
                                style: TextStyle(
                                  color: subTextColor,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.person_remove_rounded,
                                color: isDark ? Colors.white38 : Colors.grey.shade400,
                              ),
                              onPressed: () => _confirmUnfriend(friend.id, friend.username),
                            ),
                            onTap: () => _openChat(friend.id, friend.username),
                            onLongPress: () => _confirmUnfriend(friend.id, friend.username),
                          ),
                          if (!isLast)
                            Divider(
                              height: 1,
                              indent: 76, // 對齊文字 (16 padding + 44 avatar + 16 space)
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
          );
        }(),
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
                Icons.people_outline_rounded,
                size: 64,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '目前沒有好友',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '您可以透過搜尋或掃描 QR Code 來新增好友，開始你們的對話。',
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

  // ─── 錯誤狀態畫面 (Error State) ───
  Widget _buildErrorState(String error, bool isDark, Color textColor, Color subTextColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '發生錯誤',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: subTextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.read(friendViewModelProvider.notifier).loadAll(),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('重試'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                foregroundColor: textColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}