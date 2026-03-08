import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/friend/providers/friend_provider.dart';
import 'package:app/features/chat/repositories/room_repository.dart';
import 'package:app/core/storage/storage_service.dart';

class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final List<String> _selectedFriendIds = [];
  final TextEditingController _groupNameController = TextEditingController();
  bool _isLoading = false;

  void _createGroup() async {
    final name = _groupNameController.text.trim();
    if (_selectedFriendIds.length < 2 || name.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final myId = await ref.read(storageServiceProvider).read('user_id');
      final token = await ref.read(storageServiceProvider).read('jwt_token');

      if (myId == null || token == null) {
        throw Exception('User ID or Token not found');
      }

      final repo = ref.read(roomRepositoryProvider);

      // Sending the selected friends. (The backend adds the creator based on token usually, or at least that's typical)
      final room = await repo.createRoom(name, _selectedFriendIds);

      if (mounted) {
        context.pushReplacement(
          '/chat',
          extra: {
            'roomId': room.id,
            'title': room.name,
            'isRoom': true,
            'currentUserId': myId,
            'token': token,
            'avatarUrl': room.avatarUrl,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create group: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(friendViewModelProvider);
    final friends = state.friends;

    final canCreate =
        _selectedFriendIds.length >= 2 &&
        _groupNameController.text.trim().isNotEmpty &&
        !_isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('建立群組'),
            Text(
              '已選 ${_selectedFriendIds.length} 人（至少需要 2 人）',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: canCreate ? _createGroup : null,
                  child: const Text(
                    '建立',
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _groupNameController,
              decoration: const InputDecoration(
                hintText: '群組名稱',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: friends.isEmpty
                ? const Center(child: Text('目前沒有好友'))
                : ListView.builder(
                    itemCount: friends.length,
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      final isSelected = _selectedFriendIds.contains(friend.id);
                      return CheckboxListTile(
                        secondary: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        title: Text(friend.username),
                        subtitle: Text(friend.email),
                        value: isSelected,
                        activeColor: Colors.blueAccent,
                        onChanged: (bool? checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedFriendIds.add(friend.id);
                            } else {
                              _selectedFriendIds.remove(friend.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
