import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:app/features/chat/models/room.dart';
import 'package:app/features/chat/providers/room_list_provider.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';

class RoomListPage extends ConsumerStatefulWidget {
  const RoomListPage({super.key});

  @override
  ConsumerState<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends ConsumerState<RoomListPage> {
  final TextEditingController _searchController = TextEditingController();
  String? _currentUserId;
  String _currentUsername = '';
  String? _currentAvatarUrl;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final storage = ref.read(storageServiceProvider);
    final userId = await storage.read('user_id');
    final username = await storage.read('username');
    final avatarUrl = await storage.read('avatar_url');
    if (mounted) {
      if (userId == null) {
        // Should not happen if logged in, but safe to redirect
        context.go('/login');
        return;
      }
      setState(() {
        _currentUserId = userId;
        _currentUsername = username ?? '';
        _currentAvatarUrl = avatarUrl;
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
          icon: ChatAvatar(
            avatarUrl: _currentAvatarUrl,
            radius: 16,
            fallbackText: _currentUsername.isNotEmpty
                ? _currentUsername[0].toUpperCase()
                : 'U',
            fallbackIcon: Icons.person,
            logTag: 'room_list_profile',
          ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: Theme.of(context).brightness,
    );
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
        final subtitleColor = room.unreadCount > 0
            ? tokens.roomListSubtitleUnread
            : tokens.roomListSubtitleRead;
        final subtitleWeight = room.unreadCount > 0
            ? FontWeight.bold
            : FontWeight.normal;
        // 👉 重構判斷邏輯
        IconData? subtitleIcon;
        String displayText = room.lastMessage ?? 'No messages yet';

        // 👉 新增：使用正則檢查純文字中是否包含網址 (處理 API 撈取的歷史訊息)
        bool hasLink =
            room.lastMessage != null &&
            extractAllUrls(room.lastMessage!).isNotEmpty;
        if (room.lastMessageType == 'image') {
          subtitleIcon = Icons.photo;
          displayText = '[圖片]';
        } else if (room.lastMessageType == 'voice' ||
            room.lastMessageType == 'audio') {
          subtitleIcon = Icons.mic;
          displayText = '[語音訊息]';
        } else if (room.lastMessageType == 'file' ||
            room.lastMessageType == 'document') {
          subtitleIcon = Icons.insert_drive_file;
          displayText = '[檔案]';
        } else if (room.lastMessageType == 'link' || hasLink) {
          // 👉 新增這段：處理連結與 Link Preview
          subtitleIcon = Icons.link; // 顯示 🔗 Icon
          // 顯示格式：[連結] 加上原本的訊息內容或網站標題
          displayText = '[連結] ${room.lastMessage}';
        } else if (room.lastMessage == '此訊息已收回') {
          displayText = room.lastMessage!;
        }

        final isRoom = room.type == 'group';
        final hasUnread = room.unreadCount > 0;
        return ListTile(
          leading: Stack(
            children: [
              _buildRoomAvatar(room),
              Positioned(
                right: 0,
                top: 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: hasUnread
                      ? Container(
                          key: const ValueKey('unread'),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: tokens.unreadBadgeBackground,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '${room.unreadCount}',
                            style: TextStyle(
                              color: tokens.unreadBadgeForeground,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : const SizedBox(key: ValueKey('no_unread')),
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
                style: TextStyle(fontSize: 12, color: tokens.roomListTimeText),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              if (subtitleIcon != null) ...[
                Icon(subtitleIcon, size: 16, color: subtitleColor),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  displayText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: subtitleWeight,
                    color: subtitleColor,
                  ),
                ),
              ),
            ],
          ),
          onTap: () => _openChat(
            context,
            room.id,
            room.name,
            isRoom,
            userId,
            room.avatarUrl,
          ),
        );
      },
    );
  }

  Widget _buildRoomAvatar(Room room) {
    return ChatAvatar(
      avatarUrl: room.avatarUrl,
      radius: 20,
      fallbackText: room.name.isNotEmpty ? room.name[0].toUpperCase() : '?',
      fallbackIcon: room.type == 'group' ? Icons.group : null,
      logTag: 'room_list',
    );
  }

  void _openChat(
    BuildContext context,
    String roomId,
    String title,
    bool isRoom,
    String userId,
    String? avatarUrl,
  ) async {
    final token = await ref.read(storageServiceProvider).read('jwt_token');
    if (mounted && token != null) {
      ref.read(roomListViewModelProvider.notifier).markRoomRead(roomId);
      context.push(
        '/chat',
        extra: {
          'roomId': roomId,
          'title': title,
          'isRoom': isRoom,
          'currentUserId': userId,
          'token': token,
          'avatarUrl': avatarUrl,
        },
      );
    }
  }
}
