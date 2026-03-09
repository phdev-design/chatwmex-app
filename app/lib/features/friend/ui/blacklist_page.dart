import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/friend/providers/friend_provider.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';

class BlacklistPage extends ConsumerStatefulWidget {
  const BlacklistPage({super.key});

  @override
  ConsumerState<BlacklistPage> createState() => _BlacklistPageState();
}

class _BlacklistPageState extends ConsumerState<BlacklistPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(blacklistProvider.notifier).loadBlockedUsers(),
    );
  }

  Future<void> _confirmUnblock(String userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('解除封鎖'),
        content: Text('確定要解除封鎖 $username 嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '解除封鎖',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ref.read(blacklistProvider.notifier).unblock(userId);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已解除封鎖 $username')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('解除封鎖失敗：$e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(blacklistProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('黑名單'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(blacklistProvider.notifier).loadBlockedUsers(),
          ),
        ],
      ),
      body: () {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: colorScheme.error.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 12),
                Text(state.error!, style: TextStyle(color: colorScheme.error)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () =>
                      ref.read(blacklistProvider.notifier).loadBlockedUsers(),
                  child: const Text('重試'),
                ),
              ],
            ),
          );
        }
        if (state.blockedUsers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.block,
                  size: 64,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  '目前沒有黑名單',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: state.blockedUsers.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          itemBuilder: (context, index) {
            final user = state.blockedUsers[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: ChatAvatar(
                avatarUrl: null,
                radius: 22,
                fallbackText: user.username.isNotEmpty
                    ? user.username[0].toUpperCase()
                    : '?',
                fallbackIcon: Icons.person_off,
                logTag: 'blacklist',
              ),
              title: Text(
                user.username,
                style: TextStyle(color: colorScheme.onSurface),
              ),
              subtitle: Text(
                user.email,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.lock_open, color: Colors.redAccent),
                tooltip: '解除封鎖',
                onPressed: () => _confirmUnblock(user.id, user.username),
              ),
            );
          },
        );
      }(),
    );
  }
}
