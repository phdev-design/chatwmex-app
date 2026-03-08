import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:app/features/chat/models/room.dart';

class GroupMembersPage extends ConsumerStatefulWidget {
  final String roomId;
  final String? ownerId;
  final String currentUserId;

  const GroupMembersPage({
    super.key,
    required this.roomId,
    this.ownerId,
    required this.currentUserId,
  });

  @override
  ConsumerState<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends ConsumerState<GroupMembersPage> {
  bool _isLoading = true;
  String? _error;
  List<User> _members = [];

  bool get _isAdmin =>
      widget.ownerId != null && widget.currentUserId == widget.ownerId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetchMembers());
  }

  Future<void> _fetchMembers() async {
    try {
      if (mounted) setState(() => _isLoading = true);

      final repository = ref.read(chatRepositoryProvider);
      final members = await repository.getRoomMemberProfiles(widget.roomId);

      if (mounted) {
        setState(() {
          _members = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
      debugPrint('Failed to load members: $e');
    }
  }

  Future<void> _removeMember(String memberId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111B21),
        title: const Text('移除成員', style: TextStyle(color: Colors.white)),
        content: Text(
          '確定要將 $username 移出群組嗎？',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repository = ref.read(chatRepositoryProvider);
      await repository.kickMember(widget.roomId, memberId);

      if (mounted) {
        setState(() {
          _members.removeWhere((m) => m.id == memberId);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已將 $username 移出群組')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('移除失敗：$e')));
      }
      debugPrint('Failed to kick member: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111B21),
        title: const Text('群組成員', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: '新增成員',
              onPressed: () {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('功能開發中')));
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00A884)),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              '載入失敗',
              style: const TextStyle(color: Colors.redAccent, fontSize: 16),
            ),
            TextButton(
              onPressed: _fetchMembers,
              child: const Text(
                '重試',
                style: TextStyle(color: Color(0xFF00A884)),
              ),
            ),
          ],
        ),
      );
    }

    if (_members.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off, color: Color(0xFFA0AAB0), size: 64),
            SizedBox(height: 16),
            Text(
              '尚無成員',
              style: TextStyle(color: Color(0xFFA0AAB0), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _members.length,
      itemBuilder: (context, index) {
        final member = _members[index];
        final memberId = member.id;
        final username = member.username.isNotEmpty
            ? member.username
            : 'Unknown';
        final avatarUrl = member.avatarUrl;
        final isOwner = memberId == widget.ownerId;
        final isMe = memberId == widget.currentUserId;

        return ListTile(
          tileColor: const Color(0xFF111B21),
          leading: ChatAvatar(
            avatarUrl: avatarUrl,
            radius: 20,
            fallbackText: username.isNotEmpty ? username[0].toUpperCase() : '?',
            logTag: 'member_$memberId',
          ),
          title: Text(
            isMe ? '$username (你)' : username,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          trailing: isOwner
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(color: const Color(0xFF00A884)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '管理員',
                    style: TextStyle(color: Color(0xFF00A884), fontSize: 12),
                  ),
                )
              : null,
          onLongPress: (_isAdmin && !isOwner)
              ? () => _removeMember(memberId, username)
              : null,
        );
      },
    );
  }
}
