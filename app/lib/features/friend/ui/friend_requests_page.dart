import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/friend/providers/friend_provider.dart';

class FriendRequestsPage extends ConsumerWidget {
  const FriendRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendViewModelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Friend Requests')),
      body: state.requests.isEmpty
          ? const Center(child: Text('No pending requests'))
          : ListView.builder(
              itemCount: state.requests.length,
              itemBuilder: (context, index) {
                final req = state.requests[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(
                    'Request from ${req.senderUsername.isNotEmpty ? req.senderUsername : req.senderId}',
                  ),
                  subtitle: Text(
                    'Sent at ${req.createdAt.toString().split(' ')[0]}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () {
                          ref
                              .read(friendViewModelProvider.notifier)
                              .acceptRequest(req.id);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () {
                          ref
                              .read(friendViewModelProvider.notifier)
                              .rejectRequest(req.id);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
