// lib/screens/chat_detail_page/dialogs/group_management_dialogs.dart
import 'package:flutter/material.dart';
import '../../../models/user.dart';
import '../../../services/chat_api_service.dart' as api_service;

/// 顯示邀請成員對話框
Future<void> showInviteMembersDialog(
  BuildContext context, {
  required String chatRoomId,
  required List<String> currentParticipants,
  required String? currentUserId,
}) async {
  List<User> searchResults = [];
  final searchController = TextEditingController();
  bool isSearching = false;

  await showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('邀請成員'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  hintText: '搜尋用戶邀請加入群組',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (query) async {
                  if (query.length >= 2) {
                    setDialogState(() => isSearching = true);
                    try {
                      final users = await api_service.ChatApiService.searchUsers(query);
                      setDialogState(() {
                        searchResults = users
                            .where((user) =>
                                user.id != currentUserId &&
                                !currentParticipants.contains(user.id))
                            .toList();
                        isSearching = false;
                      });
                    } catch (e) {
                      setDialogState(() => isSearching = false);
                    }
                  } else {
                    setDialogState(() => searchResults.clear());
                  }
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : searchResults.isEmpty
                        ? const Center(child: Text('輸入用戶名搜尋用戶'))
                        : ListView.builder(
                            itemCount: searchResults.length,
                            itemBuilder: (context, index) {
                              final user = searchResults[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(user.initials),
                                ),
                                title: Text(user.username),
                                subtitle: Text(user.email),
                                trailing: const Icon(Icons.add),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _inviteUser(context, chatRoomId, user);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    ),
  );
}

/// 顯示編輯群組名稱對話框
Future<void> showEditGroupNameDialog(
  BuildContext context, {
  required String chatRoomId,
  required String currentName,
}) async {
  final nameController = TextEditingController(text: currentName);

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('修改群組名稱'),
      content: TextField(
        controller: nameController,
        decoration: const InputDecoration(
          labelText: '群組名稱',
          hintText: '輸入新的群組名稱',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            final newName = nameController.text.trim();
            if (newName.isNotEmpty && newName != currentName) {
              Navigator.pop(context);
              await _updateGroupName(context, chatRoomId, newName);
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

/// 顯示離開群組確認對話框
Future<void> showLeaveGroupDialog(
  BuildContext context, {
  required String chatRoomId,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('離開群組'),
      content: const Text('您確定要離開這個群組嗎？離開後將無法接收群組消息。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('離開群組'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await _leaveGroup(context, chatRoomId);
  }
}

// 私有輔助方法
Future<void> _inviteUser(BuildContext context, String chatRoomId, User user) async {
  try {
    await api_service.ChatApiService.inviteUserToRoom(chatRoomId, user.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已邀請 ${user.username} 加入群組'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('邀請失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> _updateGroupName(BuildContext context, String chatRoomId, String newName) async {
  try {
    // TODO: 調用後端 API 更新群組名稱
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('群組名稱已更新為「$newName」'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新群組名稱失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<void> _leaveGroup(BuildContext context, String chatRoomId) async {
  try {
    await api_service.ChatApiService.leaveRoom(chatRoomId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已離開群組'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('離開群組失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}