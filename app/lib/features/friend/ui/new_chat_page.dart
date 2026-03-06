import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/friend/providers/friend_provider.dart';
import 'package:app/core/storage/storage_service.dart';

class NewChatPage extends ConsumerWidget {
  const NewChatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: '建立群組',
            onPressed: () => context.push('/create-group'),
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => context.push('/add-friend'),
          ),
        ],
      ),
      body: state.friends.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No friends yet'),
                  TextButton(
                    onPressed: () => context.push('/add-friend'),
                    child: const Text('Add a friend'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: state.friends.length,
              itemBuilder: (context, index) {
                final friend = state.friends[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(friend.username),
                  subtitle: Text(friend.email),
                  onTap: () async {
                    // Navigate to Chat
                    final myId = await ref.read(storageServiceProvider).read('user_id');
                    final token = await ref.read(storageServiceProvider).read('jwt_token');
                    if (context.mounted && myId != null && token != null) {
                      context.push(
                        '/chat',
                        extra: {
                          'roomId': friend.id, // Using user ID as room ID for DM initially
                          'title': friend.username,
                          'isRoom': false,
                          'currentUserId': myId,
                          'token': token,
                        },
                      );
                    }
                  },
                );
              },
            ),
    );
  }
}
