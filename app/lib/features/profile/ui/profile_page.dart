import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:app/features/profile/ui/edit_profile_page.dart';
import 'package:app/features/profile/ui/settings_page.dart';
import 'package:app/features/profile/providers/profile_provider.dart';
import 'package:app/core/websocket/websocket_service.dart';
import 'package:app/features/chat/providers/room_list_provider.dart';
import 'package:app/features/friend/providers/friend_provider.dart';
import 'package:app/features/auth/providers/auth_provider.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/features/auth/repositories/auth_repository.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  void initState() {
    super.initState();
    // 進入頁面時，呼叫 ViewModel 載入使用者資料
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileViewModelProvider.notifier).loadProfile();
    });
  }

void _logout() async {
  // ✅ 清 WebSocket 連線
  ref.read(webSocketServiceProvider).disconnect();

  // ✅ 清記憶體中的 crypto 狀態
  await ref.read(cryptoServiceProvider).clearKeys();

  // ✅ 清 public key 快取
  await ref.read(publicKeyCacheServiceProvider).clearAllCache();

// 👇 關鍵修復：呼叫 AuthRepository 的登出，讓它處理 Google Drive 斷開與刪除 Storage 等完整流程
  await ref.read(authRepositoryProvider).logout();

  // ✅ 只刪認證相關資料，保留 E2EE 私鑰
  final storage = ref.read(storageServiceProvider);
  await storage.delete('jwt_token');
  await storage.delete('user_id');
  await storage.delete('username');
  await storage.delete('email');
  await storage.delete('phone_number');
  await storage.delete('avatar_url');

// ✅ 重置所有 providers 的 in-memory state
  ref.invalidate(roomListViewModelProvider);
  ref.invalidate(profileViewModelProvider);
  ref.invalidate(friendViewModelProvider);
  ref.invalidate(authViewModelProvider);

  if (mounted) context.go('/login');
}

  @override
  Widget build(BuildContext context) {
    ref.listen(profileViewModelProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!), backgroundColor: Colors.red),
        );
      }
    });
    final profileState = ref.watch(profileViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: () {
                ref
                    .read(profileViewModelProvider.notifier)
                    .pickAndUploadAvatar();
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ChatAvatar(
                    avatarUrl: profileState.avatarUrl,
                    radius: 50,
                    fallbackText: profileState.username.isNotEmpty
                        ? profileState.username[0].toUpperCase()
                        : 'U',
                    fallbackIcon: Icons.person,
                    logTag: 'profile_page',
                  ),
                  if (profileState.isLoading)
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 顯示 Username (如果正在載入中或沒有值，顯示預設文字)
            Text(
              profileState.username.isNotEmpty
                  ? profileState.username
                  : 'Loading...',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),

            // 順便把 Email 也顯示在名字下方，讓介面更好看
            if (profileState.email.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                profileState.email,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              ),
            ],

            const SizedBox(height: 32),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Edit Profile'),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfilePage()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Friend Requests'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/friend-requests'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }
}
