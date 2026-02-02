import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/user.dart';
import '../../../models/chat_room.dart';
import '../../../services/chat_api_service.dart' as api_service;
import '../utils/avatar_helper.dart';

/// 顯示建立聊天的選項（私人或群組）
void showCreateChatDialog(BuildContext context, String? currentUserId, ValueChanged<ChatRoom> onChatCreated) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _CreateChatOptionsSheet(
        onStartPrivateChat: () {
          Navigator.pop(context);
          _showStartPrivateChat(context, currentUserId, onChatCreated);
        },
        onStartGroupChat: () {
          Navigator.pop(context);
          _showCreateGroup(context, currentUserId, onChatCreated);
        },
      );
    },
  );
}

// --- 內部 Widgets 和 Functions ---

class _CreateChatOptionsSheet extends StatelessWidget {
  final VoidCallback onStartPrivateChat;
  final VoidCallback onStartGroupChat;

  const _CreateChatOptionsSheet({
    required this.onStartPrivateChat,
    required this.onStartGroupChat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('新增聊天', style: Theme.of(context).textTheme.headlineMedium),
          ),
          ListTile(
            leading: Icon(Icons.person_add, color: Theme.of(context).colorScheme.primary),
            title: Text('開始私人聊天', style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text('與單一用戶聊天', style: Theme.of(context).textTheme.bodySmall),
            onTap: onStartPrivateChat,
          ),
          ListTile(
            leading: Icon(Icons.group_add, color: Theme.of(context).colorScheme.secondary),
            title: Text('建立群組', style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text('建立多人聊天群組', style: Theme.of(context).textTheme.bodySmall),
            onTap: onStartGroupChat,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

void _showStartPrivateChat(BuildContext context, String? currentUserId, ValueChanged<ChatRoom> onChatCreated) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _PrivateChatCreationSheet(currentUserId: currentUserId, onChatCreated: onChatCreated),
  );
}

class _PrivateChatCreationSheet extends StatefulWidget {
  final String? currentUserId;
  final ValueChanged<ChatRoom> onChatCreated;

  const _PrivateChatCreationSheet({this.currentUserId, required this.onChatCreated});

  @override
  State<_PrivateChatCreationSheet> createState() => _PrivateChatCreationSheetState();
}

class _PrivateChatCreationSheetState extends State<_PrivateChatCreationSheet> {
  final searchController = TextEditingController();
  List<User> searchResults = [];
  bool isSearching = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20), 
          topRight: Radius.circular(20)
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('開始私人聊天', style: Theme.of(context).textTheme.headlineMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: '搜尋用戶名或 Email', 
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _searchUsers,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: isSearching
                ? const Center(child: CircularProgressIndicator())
                : searchResults.isEmpty
                    ? const Center(child: Text('輸入用戶名搜索用戶'))
                    : ListView.builder(
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final user = searchResults[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: getAvatarColor(user.username),
                              child: Text(
                                getAvatarText(user.username), 
                                style: const TextStyle(color: Colors.white)
                              ),
                            ),
                            title: Text(user.username),
                            subtitle: Text(user.email),
                            onTap: () => _createPrivateChat(user),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _searchUsers(String query) async {
    if (query.length < 2) {
      setState(() => searchResults.clear());
      return;
    }
    setState(() => isSearching = true);
    try {
      final users = await api_service.ChatApiService.searchUsers(query);
      if (mounted) {
        setState(() {
          searchResults = users.where((user) => user.id != widget.currentUserId).toList();
        });
      }
    } catch (e) {
      print('搜索用戶失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索用戶失敗: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isSearching = false);
    }
  }

  Future<void> _createPrivateChat(User user) async {
    Navigator.pop(context);
    try {
      final room = await api_service.ChatApiService.createChatRoom(
        name: user.username,
        participants: [user.id],
        isGroup: false,
      );
      widget.onChatCreated(room);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('建立聊天失敗: $e')),
        );
      }
    }
  }
}

void _showCreateGroup(BuildContext context, String? currentUserId, ValueChanged<ChatRoom> onChatCreated) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _GroupCreationSheet(currentUserId: currentUserId, onChatCreated: onChatCreated),
  );
}

class _GroupCreationSheet extends StatefulWidget {
  final String? currentUserId;
  final ValueChanged<ChatRoom> onChatCreated;
  
  const _GroupCreationSheet({this.currentUserId, required this.onChatCreated});

  @override
  State<_GroupCreationSheet> createState() => _GroupCreationSheetState();
}

class _GroupCreationSheetState extends State<_GroupCreationSheet> {
  final nameController = TextEditingController();
  final searchController = TextEditingController();
  List<User> selectedMembers = [];
  List<User> searchResults = [];
  bool isSearching = false;
  Timer? _debounce;

  @override
  void dispose() {
    nameController.dispose();
    searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20), 
          topRight: Radius.circular(20)
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('建立群組', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController, 
                  decoration: const InputDecoration(
                    labelText: '群組名稱',
                    prefixIcon: Icon(Icons.group),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: searchController, 
                  decoration: const InputDecoration(
                    hintText: '搜尋用戶以邀請',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ), 
                  onChanged: _onSearchChanged,
                ),
              ],
            ),
          ),
          if (selectedMembers.isNotEmpty) _buildSelectedMembers(),
          Expanded(
            child: isSearching
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: searchResults.length,
                    itemBuilder: (context, index) {
                      final user = searchResults[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: getAvatarColor(user.username),
                          child: Text(
                            getAvatarText(user.username), 
                            style: const TextStyle(color: Colors.white)
                          ),
                        ),
                        title: Text(user.username),
                        subtitle: Text(user.email),
                        onTap: () {
                          setState(() {
                            selectedMembers.add(user);
                            searchResults.removeAt(index);
                          });
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _createGroup, 
                child: const Text('建立群組'),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSelectedMembers() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: selectedMembers.length,
          itemBuilder: (context, index) {
            final member = selectedMembers[index];
            return Container(
              margin: const EdgeInsets.only(right: 8),
              child: Chip(
                label: Text(member.username),
                avatar: CircleAvatar(
                  backgroundColor: getAvatarColor(member.username),
                  child: Text(
                    getAvatarText(member.username), 
                    style: const TextStyle(color: Colors.white, fontSize: 12)
                  ),
                ),
                onDeleted: () {
                  setState(() {
                    selectedMembers.removeAt(index);
                  });
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.length < 2) {
        setState(() => searchResults.clear());
        return;
      }
      setState(() => isSearching = true);
      try {
        final users = await api_service.ChatApiService.searchUsers(query);
        if (mounted) {
          setState(() {
            searchResults = users.where((user) => 
              user.id != widget.currentUserId && 
              !selectedMembers.any((m) => m.id == user.id)
            ).toList();
          });
        }
      } catch (e) {
        print('搜索用戶失敗: $e');
      } finally {
        if (mounted) setState(() => isSearching = false);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = nameController.text.trim();
    if (name.isEmpty || selectedMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入群組名稱並至少選擇一位成員')),
      );
      return;
    }
    Navigator.pop(context);
    try {
      final room = await api_service.ChatApiService.createChatRoom(
        name: name,
        participants: selectedMembers.map((e) => e.id).toList(),
        isGroup: true,
      );
      widget.onChatCreated(room);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('群組「$name」建立成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('建立群組失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}