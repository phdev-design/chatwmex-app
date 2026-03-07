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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('解除好友'),
        content: Text('確定要與 $friendUsername 解除好友關係嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '解除好友',
              style: TextStyle(color: Colors.red),
            ),
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
      context.push('/chat', extra: {
        'roomId': friendId,
        'title': friendUsername,
        'isRoom': false,
        'currentUserId': myId,
        'token': token,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(friendViewModelProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('朋友列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(friendViewModelProvider.notifier).loadAll(),
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
                Icon(Icons.error_outline,
                    size: 48,
                    color: colorScheme.error.withValues(alpha: 0.7)),
                const SizedBox(height: 12),
                Text(state.error!,
                    style: TextStyle(color: colorScheme.error)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () =>
                      ref.read(friendViewModelProvider.notifier).loadAll(),
                  child: const Text('重試'),
                ),
              ],
            ),
          );
        }
        if (state.friends.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline,
                    size: 64,
                    color:
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  '目前沒有好友',
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
          itemCount: state.friends.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          itemBuilder: (context, index) {
            final friend = state.friends[index];
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                friend.email,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              trailing: IconButton(
                icon: Icon(Icons.person_remove_outlined,
                    color: colorScheme.onSurfaceVariant),
                onPressed: () =>
                    _confirmUnfriend(friend.id, friend.username),
              ),
              onTap: () => _openChat(friend.id, friend.username),
              onLongPress: () =>
                  _confirmUnfriend(friend.id, friend.username),
            );
          },
        );
      }(),
    );
  }
}
