import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:app/features/chat/models/room.dart';
import 'package:app/features/chat/providers/room_list_provider.dart';
import 'package:app/core/storage/storage_service.dart';

class RoomListPage extends ConsumerStatefulWidget {
  const RoomListPage({super.key});

  @override
  ConsumerState<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends ConsumerState<RoomListPage> {
  final TextEditingController _searchController = TextEditingController();
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final userId = await ref.read(storageServiceProvider).read('user_id');
    if (mounted) {
      if (userId == null) {
        // Should not happen if logged in, but safe to redirect
        context.go('/login');
        return;
      }
      setState(() {
        _currentUserId = userId;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomListViewModelProvider);

    if (_currentUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final filteredRooms = state.rooms.where((room) {
      return room.name.toLowerCase().contains(
        _searchController.text.toLowerCase(),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        leading: IconButton(
          icon: const CircleAvatar(child: Icon(Icons.person, size: 20)),
          onPressed: () => context.push('/profile'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/new-chat'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search chats...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(child: _buildRoomList(filteredRooms, _currentUserId!)),
        ],
      ),
    );
  }

  Widget _buildRoomList(List<Room> rooms, String userId) {
    if (rooms.isEmpty) {
      return const Center(child: Text('No chats found'));
    }

    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        final timeStr = room.lastMessageTime != null
            ? DateFormat('HH:mm').format(room.lastMessageTime!)
            : '';

        final isRoom = room.type == 'group';
        return ListTile(
          leading: Stack(
            children: [
              const CircleAvatar(child: Icon(Icons.group)),
              if (room.unreadCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${room.unreadCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                room.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                timeStr,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          subtitle: Text(
            room.lastMessage ?? 'No messages yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: room.unreadCount > 0
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: room.unreadCount > 0 ? Colors.black87 : Colors.grey,
            ),
          ),
          onTap: () => _openChat(context, room.id, room.name, isRoom, userId),
        );
      },
    );
  }

  void _openChat(
    BuildContext context,
    String roomId,
    String title,
    bool isRoom,
    String userId,
  ) async {
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
