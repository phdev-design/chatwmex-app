import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../providers/theme_provider.dart';
import '../utils/token_storage.dart';
import '../widgets/theme_switch_widget.dart';
import '../config/version_config.dart';
import '../services/profile_api_service.dart';
import 'login_page.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _userInfo;
  bool _isLoading = true;
  bool _notificationsEnabled = true;
  bool _isUploadingAvatar = false;
  String? _avatarUrl;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final NotificationService _notificationService = NotificationService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _loadUserInfo();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    try {
      final userInfo = await TokenStorage.getUser();
      final notificationStatus =
          await _notificationService.checkNotificationPermission();

      setState(() {
        _userInfo = userInfo ??
            {
              'username': '訪客用戶',
              'email': 'guest@example.com',
              'avatar_url': null,
            };
        _avatarUrl = _userInfo?['avatar_url'];
        _notificationsEnabled = notificationStatus;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登出確認'),
        content: const Text('您確定要登出嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              print('Logging out, disconnecting ChatService...');
              ChatService().disableReconnect();
              ChatService().disconnect();

              await TokenStorage.clearAll();

              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('登出'),
          ),
        ],
      ),
    );
  }

  void _showNotificationSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('通知設定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '當前狀態：${_notificationsEnabled ? "已開啟" : "已關閉"}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            const Text('通知功能說明：'),
            const SizedBox(height: 8),
            const Text('• 當您不在聊天室時接收新消息通知'),
            const Text('• 顯示發送者姓名和消息內容'),
            const Text('• 點擊通知可快速進入對應聊天室'),
            const SizedBox(height: 16),
            if (!_notificationsEnabled)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '通知已關閉，您將不會收到新消息提醒',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          if (!_notificationsEnabled)
            ElevatedButton(
              onPressed: () async {
                await _notificationService.openAppSettings();
                Navigator.pop(context);
                final newStatus =
                    await _notificationService.checkNotificationPermission();
                if (mounted) {
                  setState(() {
                    _notificationsEnabled = newStatus;
                  });
                }
              },
              child: const Text('去設置開啟'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('開啟推播通知'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('為了及時收到新消息，請開啟推播通知權限。'),
            const SizedBox(height: 16),
            if (Platform.isIOS) ...[
              const Text('iOS 設置步驟：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('1. 點擊「開啟權限」按鈕'),
              const Text('2. 在彈出的對話框中選擇「允許」'),
              const Text('3. 如果沒有彈出對話框，請到：'),
              const Text('   設定 → Chat2MeX → 通知 → 開啟'),
            ] else ...[
              const Text('Android 設置步驟：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('設置 → 應用 → Chat2MeX → 通知 → 開啟'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍後設置'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final status =
                  await _notificationService.requestNotificationPermission();

              if (status.isGranted) {
                if (mounted) {
                  setState(() {
                    _notificationsEnabled = true;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('通知權限已開啟！'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else if (status.isPermanentlyDenied) {
                if (mounted) {
                  _showOpenSettingsDialog();
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('需要通知權限才能接收消息通知'),
                      action: SnackBarAction(
                        label: '去設置',
                        textColor: Colors.white,
                        onPressed: () async {
                          await _notificationService.openAppSettings();
                          final newStatus = await _notificationService
                              .checkNotificationPermission();
                          if (newStatus && mounted) {
                            setState(() {
                              _notificationsEnabled = true;
                            });
                          }
                        },
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('開啟權限'),
          ),
        ],
      ),
    );
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要權限'),
        content: const Text('通知權限已被關閉。請在設置中手動開啟通知權限，以便接收新消息通知。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _notificationService.openAppSettings();
            },
            child: const Text('去設置'),
          ),
        ],
      ),
    );
  }

  Future<void> _enableNotifications() async {
    try {
      await _notificationService.initialize();
      final hasPermission =
          await _notificationService.checkNotificationPermission();

      if (hasPermission) {
        setState(() {
          _notificationsEnabled = true;
        });
        _notificationService.setNotificationsEnabled(true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('通知已開啟'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        _showPermissionDialog();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('開啟通知失敗：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildProfileHeader() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              GestureDetector(
                onTap: _isUploadingAvatar ? null : _showAvatarOptions,
                child: Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                _avatarUrl!,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Text(
                                      _getUserInitials(),
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          : Center(
                              child: Text(
                                _getUserInitials(),
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                    ),
                    if (_isUploadingAvatar)
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                    if (!_isUploadingAvatar)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.primary,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _userInfo?['username'] ?? '用戶',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _userInfo?['email'] ?? '',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          children: [
            _buildSettingsTile(
              icon: Icons.person,
              title: '編輯個人資料',
              subtitle: '更改您的姓名、頭像等',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditProfilePage(),
                  ),
                ).then((_) {
                  _loadUserInfo();
                });
              },
            ),
            _buildSettingsTile(
              icon: Icons.notifications,
              title: '通知設定',
              subtitle: _notificationsEnabled ? '已開啟' : '已關閉',
              onTap: () {
                _showNotificationSettings();
              },
              trailing: Switch(
                value: _notificationsEnabled,
                onChanged: (value) async {
                  if (value) {
                    await _notificationService.initialize();
                    final hasPermission = await _notificationService
                        .checkNotificationPermission();
                    if (!hasPermission) {
                      _showPermissionDialog();
                    } else {
                      setState(() {
                        _notificationsEnabled = true;
                      });
                      _notificationService.setNotificationsEnabled(true);
                    }
                  } else {
                    setState(() {
                      _notificationsEnabled = false;
                    });
                    _notificationService.setNotificationsEnabled(false);
                    _notificationService.clearAllNotifications();
                  }
                },
              ),
            ),
            _buildSettingsTile(
              icon: Icons.privacy_tip,
              title: '隱私設定',
              subtitle: '控制您的隱私選項',
              onTap: () {},
            ),
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return _buildSettingsTile(
                  icon: themeProvider.currentThemeIcon,
                  title: '主題設定',
                  subtitle: '當前：${themeProvider.currentThemeName}',
                  onTap: () {
                    _showThemeDialog();
                  },
                  trailing: const ThemeToggleButton(),
                );
              },
            ),
            // 🔥 修改：這裡的按鈕將調用新的簡易通知方法
            _buildSettingsTile(
              icon: Icons.notifications_active,
              title: '測試通知 (教學)',
              subtitle: '發送一個簡單的標題和內容',
              onTap: () async {
                // 調用我們在 NotificationService 中新增的簡易方法
                await _notificationService.showSimpleNotification(
                  title: '測試標題',
                  body: '這是來自 YouTube 教學的測試內容。',
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('簡易測試通知已發送'),
                      backgroundColor: Colors.blue,
                    ),
                  );
                }
              },
            ),
            _buildSettingsTile(
              icon: Icons.help,
              title: '幫助與支援',
              subtitle: '常見問題、聯絡我們',
              onTap: () {},
            ),
            _buildSettingsTile(
              icon: Icons.info,
              title: '關於',
              subtitle: VersionConfig.fullVersion,
              onTap: () {
                _showAboutDialog();
              },
            ),
            const SizedBox(height: 24),
            _buildSettingsTile(
              icon: Icons.logout,
              title: '登出',
              subtitle: '登出您的帳戶',
              onTap: _logout,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.1)
                        : Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isDestructive
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: isDestructive
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6),
                            ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing
                else
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return AlertDialog(
            title: const Text('選擇主題'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('淺色模式'),
                  subtitle: const Text('適合白天使用'),
                  value: ThemeMode.light,
                  groupValue: themeProvider.themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      themeProvider.setThemeMode(value);
                      Navigator.pop(context);
                    }
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('深色模式'),
                  subtitle: const Text('適合夜晚使用'),
                  value: ThemeMode.dark,
                  groupValue: themeProvider.themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      themeProvider.setThemeMode(value);
                      Navigator.pop(context);
                    }
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('跟隨系統'),
                  subtitle: const Text('自動切換'),
                  value: ThemeMode.system,
                  groupValue: themeProvider.themeMode,
                  onChanged: (value) {
                    if (value != null) {
                      themeProvider.setThemeMode(value);
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: VersionConfig.appName,
      applicationVersion: VersionConfig.version,
      applicationIcon: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.chat_bubble,
          color: Colors.white,
          size: 32,
        ),
      ),
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text('一個簡潔、安全的即時通訊應用，讓您與朋友、家人和同事保持聯繫。'),
        ),
      ],
    );
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!(Platform.isIOS && kDebugMode))
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('拍照'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('從相簿選擇'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('移除頭像'),
                onTap: () {
                  Navigator.pop(context);
                  _removeAvatar();
                },
              ),
            if (Platform.isIOS && kDebugMode)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange[700], size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'iOS 模擬器不支持相機功能，請在真機上測試完整功能',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('取消'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (Platform.isIOS && kDebugMode) {
        if (source == ImageSource.camera) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('iOS 模擬器不支持相機功能，請使用相簿選擇'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        await _uploadAvatar(File(image.path));
      }
    } catch (e) {
      print('選擇圖片失敗: $e');
      if (mounted) {
        String errorMessage = '選擇圖片失敗';

        if (e.toString().contains('PlatformException')) {
          if (Platform.isIOS) {
            errorMessage = 'iOS 模擬器不支持此功能，請在真機上測試';
          } else {
            errorMessage = '圖片選擇器初始化失敗，請檢查權限設置';
          }
        } else if (e.toString().contains('Permission denied')) {
          errorMessage = '請在設置中允許相機和相簿權限';
        } else {
          errorMessage = '選擇圖片失敗: $e';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '重試',
              textColor: Colors.white,
              onPressed: () {
                _showAvatarOptions();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _uploadAvatar(File imageFile) async {
    setState(() {
      _isUploadingAvatar = true;
    });

    try {
      final result = await ProfileApiService.uploadAvatar(imageFile);

      if (mounted) {
        if (result['success']) {
          final updatedUserInfo = Map<String, dynamic>.from(_userInfo ?? {});
          updatedUserInfo['avatar_url'] = result['avatar_url'];

          await TokenStorage.saveUser(updatedUserInfo);

          setState(() {
            _userInfo = updatedUserInfo;
            _avatarUrl = result['avatar_url'];
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('頭像上傳成功！'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? '上傳失敗'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('上傳頭像失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上傳頭像失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _removeAvatar() async {
    try {
      final result = await ProfileApiService.removeAvatar();

      if (mounted) {
        if (result['success']) {
          final updatedUserInfo = Map<String, dynamic>.from(_userInfo ?? {});
          updatedUserInfo['avatar_url'] = null;

          await TokenStorage.saveUser(updatedUserInfo);

          setState(() {
            _userInfo = updatedUserInfo;
            _avatarUrl = null;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('頭像已移除'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? '移除失敗'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('移除頭像失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('移除頭像失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getUserInitials() {
    final username = _userInfo?['username'] ?? '';
    final email = _userInfo?['email'] ?? '';

    if (username.isNotEmpty && username != '訪客用戶') {
      final words = username.split(' ');
      if (words.length >= 2) {
        return '${words[0][0]}${words[1][0]}'.toUpperCase();
      }
      return username.substring(0, 1).toUpperCase();
    }

    if (email.isNotEmpty) {
      return email.substring(0, 1).toUpperCase();
    }

    return 'U';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('個人資料'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildProfileHeader(),
                  const SizedBox(height: 24),
                  _buildSettingsSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}
