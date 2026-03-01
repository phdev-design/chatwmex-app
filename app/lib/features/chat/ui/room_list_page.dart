import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/chat/providers/room_list_provider.dart';
import 'package:app/core/storage/storage_service.dart';

class RoomListPage extends ConsumerStatefulWidget {
  const RoomListPage({super.key});

  @override
  ConsumerState<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends ConsumerState<RoomListPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    // Debounce logic could be added here
    ref.read(roomListViewModelProvider.notifier).searchUsers(query);
  }

  void _logout() async {
    await ref.read(storageServiceProvider).deleteAll();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomListViewModelProvider);
    // TODO: Get real user ID from provider
    final userId = "user1"; 

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search users...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _searchController.text.isNotEmpty
                ? _buildSearchResults(state, userId)
                : _buildRoomList(state, userId),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(RoomListState state, String userId) {
    if (state.searchResults.isEmpty) {
      return const Center(child: Text('No users found'));
    }
    return ListView.builder(
      itemCount: state.searchResults.length,
      itemBuilder: (context, index) {
        final user = state.searchResults[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user.username),
          subtitle: Text(user.email),
          onTap: () => _openChat(context, user.id, user.username, false, userId),
        );
      },
    );
  }

  Widget _buildRoomList(RoomListState state, String userId) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.rooms.isEmpty) {
      return const Center(child: Text('No chats yet'));
    }
    return ListView.builder(
      itemCount: state.rooms.length,
      itemBuilder: (context, index) {
        final room = state.rooms[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.group)),
          title: Text(room.name),
          subtitle: const Text('Last message...'), // Could show last message preview
          onTap: () => _openChat(context, room.id, room.name, true, userId),
        );
      },
    );
  }

  void _openChat(BuildContext context, String roomId, String title, bool isRoom, String userId) async {
    final token = await ref.read(storageServiceProvider).read('jwt_token');
    if (mounted && token != null) {
      context.push(
        '/chat',
        extra: {
          'roomId': roomId,
          'title': title,
          'isRoom': isRoom,
          'currentUserId': userId,
          'token': token,
        },
      );
    }
  }
}
