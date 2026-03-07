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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileViewModelProvider.notifier).loadProfile();
    });
  }

  Future<void> _logout() async {
    // ✅ 清 WebSocket 連線
    ref.read(webSocketServiceProvider).disconnect();
    // ✅ 清記憶體中的 crypto 狀態
    await ref.read(cryptoServiceProvider).clearKeys();
    // ✅ 清 public key 快取
    await ref.read(publicKeyCacheServiceProvider).clearAllCache();
    // 關鍵修復：呼叫 AuthRepository 的登出，讓它處理 Google Drive 斷開與刪除 Storage 等完整流程
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F6F8);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          '個人檔案',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProfileHeader(
                profileState: profileState,
                onAvatarTap: () => ref
                    .read(profileViewModelProvider.notifier)
                    .pickAndUploadAvatar(),
                onEditTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfilePage()),
                ),
                isDark: isDark,
              ),
              const SizedBox(height: 24),
              _SettingsGroup(
                label: '社群',
                isDark: isDark,
                items: [
                  _SettingsItem(
                    icon: Icons.people_rounded,
                    iconColor: const Color(0xFF4F8EF7),
                    label: '朋友',
                    isExpansion: true,
                    isDark: isDark,
                    subItems: [
                      _SubItem(
                        icon: Icons.person_add_outlined,
                        label: '邀請',
                        onTap: () => context.push('/friend-requests'),
                      ),
                      _SubItem(
                        icon: Icons.contacts_outlined,
                        label: '朋友列表',
                        onTap: () => context.push('/friend-list'),
                      ),
                      _SubItem(
                        icon: Icons.block_rounded,
                        label: '黑名單',
                        onTap: () => context.push('/blacklist'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                label: '帳號',
                isDark: isDark,
                items: [
                  _SettingsItem(
                    icon: Icons.person_outline_rounded,
                    iconColor: const Color(0xFF34C759),
                    label: '編輯個人資料',
                    isDark: isDark,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const EditProfilePage()),
                    ),
                  ),
                  _SettingsItem(
                    icon: Icons.settings_outlined,
                    iconColor: const Color(0xFF8E8E93),
                    label: '設定',
                    isDark: isDark,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsGroup(
                label: '其他',
                isDark: isDark,
                items: [
                  _SettingsItem(
                    icon: Icons.logout_rounded,
                    iconColor: const Color(0xFFFF3B30),
                    label: '登出',
                    labelColor: const Color(0xFFFF3B30),
                    isDark: isDark,
                    showChevron: false,
                    onTap: _logout,
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final dynamic profileState;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditTap;
  final bool isDark;

  const _ProfileHeader({
    required this.profileState,
    required this.onAvatarTap,
    required this.onEditTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: Stack(
              children: [
                ChatAvatar(
                  avatarUrl: profileState.avatarUrl,
                  radius: 44,
                  fallbackText: profileState.username.isNotEmpty
                      ? profileState.username[0].toUpperCase()
                      : 'U',
                  fallbackIcon: Icons.person,
                  logTag: 'profile_page',
                ),
                if (profileState.isLoading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A3A3C)
                          : const Color(0xFFE5E5EA),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      size: 13,
                      color: isDark
                          ? Colors.white70
                          : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            profileState.username.isNotEmpty
                ? profileState.username
                : 'Loading...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
              letterSpacing: -0.3,
            ),
          ),
          if (profileState.email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profileState.email,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onEditTap,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('編輯個人資料'),
            style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              side: BorderSide(
                color: isDark
                    ? Colors.white24
                    : Colors.black.withValues(alpha: 0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Settings Group ──────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  final String label;
  final List<_SettingsItem> items;
  final bool isDark;

  const _SettingsGroup({
    required this.label,
    required this.items,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: isDark ? Colors.white38 : Colors.grey[500],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                items[i],
                if (i < items.length - 1)
                  Divider(
                    height: 1,
                    indent: 54,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.07),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Settings Item ────────────────────────────────────────────────────────────

class _SubItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SubItem({required this.icon, required this.label, required this.onTap});
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback? onTap;
  final bool isDark;
  final bool showChevron;
  final bool isExpansion;
  final List<_SubItem> subItems;

  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isDark,
    this.labelColor,
    this.onTap,
    this.showChevron = true,
    this.isExpansion = false,
    this.subItems = const [],
  });

  Widget _iconBox() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: iconColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = labelColor ??
        (isDark ? Colors.white : Colors.black87);
    final subTextColor = isDark ? Colors.white54 : Colors.grey[600]!;
    final chevronColor = isDark ? Colors.white24 : Colors.black26;

    if (isExpansion) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            childrenPadding: EdgeInsets.zero,
            leading: _iconBox(),
            title: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            iconColor: isDark ? Colors.white54 : Colors.grey,
            collapsedIconColor: isDark ? Colors.white38 : Colors.grey,
            children: [
              for (int i = 0; i < subItems.length; i++) ...[
                Divider(
                  height: 1,
                  indent: 54,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.black.withValues(alpha: 0.07),
                ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  leading: Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: Icon(subItems[i].icon,
                        size: 20, color: subTextColor),
                  ),
                  title: Text(
                    subItems[i].label,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: chevronColor,
                  ),
                  onTap: subItems[i].onTap,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            _iconBox(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
            if (showChevron)
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: chevronColor,
              ),
          ],
        ),
      ),
    );
  }
}
