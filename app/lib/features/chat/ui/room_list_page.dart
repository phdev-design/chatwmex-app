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
import 'package:app/features/chat/models/room_label.dart';
import 'package:app/features/chat/providers/room_label_provider.dart';
import 'dart:async';
import 'dart:convert';

class RoomListPage extends ConsumerStatefulWidget {
  const RoomListPage({super.key});

  @override
  ConsumerState<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends ConsumerState<RoomListPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String? _currentUserId;
  String _currentUsername = '';
  String? _currentAvatarUrl;
  String _selectedFilter = '全部';
  Set<String> _favoriteRoomIds = {};

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
    final favoriteIdsJson = await storage.read('favorite_room_ids');

    if (mounted) {
      if (userId == null) {
        context.go('/login');
        return;
      }
      setState(() {
        _currentUserId = userId;
        _currentUsername = username ?? '';
        _currentAvatarUrl = avatarUrl;
        if (favoriteIdsJson != null) {
          try {
            final List<dynamic> parsed = jsonDecode(favoriteIdsJson);
            _favoriteRoomIds = parsed.map((e) => e.toString()).toSet();
          } catch (_) {
            _favoriteRoomIds = {};
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<Room> _filterRooms(List<Room> rooms, List<RoomLabel> customLabels) {
    switch (_selectedFilter) {
      case '未讀':
        return rooms.where((r) => r.unreadCount > 0).toList();
      case '最愛':
        return rooms.where((r) => _favoriteRoomIds.contains(r.id)).toList();
      case '群組':
        return rooms.where((r) => r.type == 'group').toList();
      case '私訊':
        return rooms.where((r) => r.type == 'dm').toList();
      default:
        final matchedLabel =
            customLabels.where((l) => l.name == _selectedFilter).firstOrNull;
        if (matchedLabel != null) {
          return rooms
              .where((r) => matchedLabel.roomIds.contains(r.id))
              .toList();
        }
        return rooms;
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(roomListViewModelProvider.notifier).fetchRooms(query: query);
    });
  }

  Future<void> _openChat(
    BuildContext context,
    String roomId,
    String title,
    bool isRoom,
    String userId,
    String? avatarUrl,
  ) async {
    final token = await ref.read(storageServiceProvider).read('jwt_token');
    if (!context.mounted) return;
    if (mounted && token != null) {
      ref.read(roomListViewModelProvider.notifier).markRoomRead(roomId);
      context.push('/chat', extra: {
        'roomId': roomId,
        'title': title,
        'isRoom': isRoom,
        'currentUserId': userId,
        'token': token,
        'avatarUrl': avatarUrl,
      });
    }
  }

  void _showRoomOptions(BuildContext context, Room room) {
    final isFav = _favoriteRoomIds.contains(room.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(
                isFav ? Icons.star_border_rounded : Icons.star_rounded,
                color: isFav ? Colors.grey : const Color(0xFFFFC107),
              ),
              title: Text(isFav ? '移除最愛' : '加入最愛'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  if (isFav) {
                    _favoriteRoomIds.remove(room.id);
                  } else {
                    _favoriteRoomIds.add(room.id);
                  }
                });
                ref.read(storageServiceProvider).save(
                      'favorite_room_ids',
                      jsonEncode(_favoriteRoomIds.toList()),
                    );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomListViewModelProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F6F8);
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    if (_currentUserId == null) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final labelsAsync = ref.watch(roomLabelProvider);
    final customLabels =
        labelsAsync.valueOrNull?.where((l) => l.isEnabled).toList() ?? [];
    final allTabs = [
      '全部', '未讀', '最愛', '群組', '私訊',
      ...customLabels.map((l) => l.name),
    ];
    final filteredRooms = _filterRooms(state.rooms, customLabels);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: GestureDetector(
            onTap: () => context.push('/profile'),
            child: ChatAvatar(
              avatarUrl: _currentAvatarUrl,
              radius: 18,
              fallbackText: _currentUsername.isNotEmpty
                  ? _currentUsername[0].toUpperCase()
                  : 'U',
              fallbackIcon: Icons.person,
              logTag: 'room_list_profile',
            ),
          ),
        ),
        title: Text(
          'Chats',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFEFEFF0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.edit_rounded,
                size: 18,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            onPressed: () => context.push('/new-chat'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFEFEFF0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: '搜尋...',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white38 : Colors.grey[500],
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: isDark ? Colors.white38 : Colors.grey[500],
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          // ── Filter Chips ────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: allTabs.map((label) {
                final isSelected = _selectedFilter == label;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _selectedFilter = label),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark
                                ? Colors.white
                                : Colors.black87)
                            : (isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFEFEFF0)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? (isDark ? Colors.black : Colors.white)
                              : (isDark
                                  ? Colors.white70
                                  : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // ── Room List ────────────────────────────────────────────────────
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildRoomList(filteredRooms, _currentUserId!, isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomList(List<Room> rooms, String userId, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: Theme.of(context).brightness,
    );

    if (rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 56,
              color: isDark
                  ? Colors.white24
                  : Colors.black.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedFilter == '全部' ? '還沒有任何對話' : '沒有符合的對話',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white38 : Colors.grey[500],
              ),
            ),
            if (_selectedFilter == '全部') ...[
              const SizedBox(height: 8),
              Text(
                '點擊右上角的鉛筆圖示來開始新對話',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white24 : Colors.grey[400],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8),
      itemCount: rooms.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        indent: 76,
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.06),
      ),
      itemBuilder: (context, index) {
        final room = rooms[index];
        return _RoomListItem(
          room: room,
          tokens: tokens,
          isDark: isDark,
          isFavorite: _favoriteRoomIds.contains(room.id),
          onTap: () => _openChat(
            context,
            room.id,
            room.name,
            room.type == 'group',
            userId,
            room.avatarUrl,
          ),
          onLongPress: () => _showRoomOptions(context, room),
        );
      },
    );
  }
}

// ─── Room List Item ───────────────────────────────────────────────────────────

class _RoomListItem extends StatelessWidget {
  final Room room;
  final ChatSurfaceTokens tokens;
  final bool isDark;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _RoomListItem({
    required this.room,
    required this.tokens,
    required this.isDark,
    required this.isFavorite,
    required this.onTap,
    required this.onLongPress,
  });

  String get _timeStr {
    if (room.lastMessageTime == null) return '';
    final now = DateTime.now();
    final msg = room.lastMessageTime!;
    if (now.difference(msg).inDays == 0) {
      return DateFormat('HH:mm').format(msg);
    } else if (now.difference(msg).inDays < 7) {
      return DateFormat('E').format(msg);
    }
    return DateFormat('MM/dd').format(msg);
  }

  (IconData?, String) get _subtitleContent {
    final msg = room.lastMessage;
    if (room.lastMessageType == 'image') return (Icons.photo_rounded, '[圖片]');
    if (room.lastMessageType == 'voice' || room.lastMessageType == 'audio') {
      return (Icons.mic_rounded, '[語音訊息]');
    }
    if (room.lastMessageType == 'file' ||
        room.lastMessageType == 'document') {
      return (Icons.insert_drive_file_rounded, '[檔案]');
    }
    final hasLink =
        msg != null && extractAllUrls(msg).isNotEmpty;
    if (room.lastMessageType == 'link' || hasLink) {
      return (Icons.link_rounded, '[連結] ${msg ?? ''}');
    }
    return (null, msg ?? '尚無訊息');
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = room.unreadCount > 0;
    final (subtitleIcon, displayText) = _subtitleContent;
    final subtitleColor = hasUnread
        ? tokens.roomListSubtitleUnread
        : tokens.roomListSubtitleRead;
    final nameColor = isDark ? Colors.white : Colors.black87;
    final timeColor = tokens.roomListTimeText;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Avatar + unread dot ────────────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                ChatAvatar(
                  avatarUrl: room.avatarUrl,
                  radius: 26,
                  fallbackText: room.name.isNotEmpty
                      ? room.name[0].toUpperCase()
                      : '?',
                  fallbackIcon: room.type == 'group' ? Icons.group : null,
                  logTag: 'room_list',
                ),
                if (isFavorite)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C1E)
                            : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star_rounded,
                          size: 12, color: Color(0xFFFFC107)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // ── Text block ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: nameColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUnread
                              ? tokens.unreadBadgeBackground
                              : timeColor,
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (subtitleIcon != null) ...[
                        Icon(subtitleIcon, size: 14, color: subtitleColor),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          displayText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: subtitleColor,
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim,
                            child: FadeTransition(opacity: anim, child: child),
                          ),
                          child: Container(
                            key: ValueKey(room.unreadCount),
                            constraints: const BoxConstraints(
                                minWidth: 20, minHeight: 20),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: tokens.unreadBadgeBackground,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              room.unreadCount > 99
                                  ? '99+'
                                  : '${room.unreadCount}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: tokens.unreadBadgeForeground,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
