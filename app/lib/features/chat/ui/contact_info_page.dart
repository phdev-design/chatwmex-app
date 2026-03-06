import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:app/features/chat/ui/room_media_page.dart';
import 'package:app/features/chat/providers/chat_setting_provider.dart';
import 'package:app/features/chat/providers/e2ee_provider.dart';
import 'package:app/features/chat/ui/encryption_info_page.dart'; // 👉 匯入 EncryptionInfoPage

class ContactInfoPage extends ConsumerStatefulWidget {
  final String roomId;
  final String title;
  final bool isRoom;
  final String? avatarUrl;
  final int mediaCount; // 👉 1. 新增這行
  final String? email; // 👉 1. 新增 email 參數

  const ContactInfoPage({
    super.key,
    required this.roomId,
    required this.title,
    this.isRoom = false,
    this.avatarUrl,
    this.mediaCount = 0, // 👉 2. 設定預設值
    this.email, // 👉 2. 加入建構子
  });

  @override
  ConsumerState<ContactInfoPage> createState() => _ContactInfoPageState();
}

class _ContactInfoPageState extends ConsumerState<ContactInfoPage> {
  String _formatTimerOption(int seconds) {
    if (seconds == 0) return '關閉';
    if (seconds == 86400) return '24小時';
    if (seconds == 604800) return '7天';
    if (seconds == 7776000) return '90天';
    return '關閉';
  }

  int _parseTimerOption(String option) {
    if (option == '24小時') return 86400;
    if (option == '7天') return 604800;
    if (option == '90天') return 7776000;
    return 0; // '關閉'
  }

  void _showDisappearingMessagesDialog(Color primaryTextColor, Color accentColor, String currentOption) {
    String tempOption = currentOption;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    '自動刪除的訊息',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      '選取此聊天室新訊息的自動刪除時間。這不會影響既有的訊息。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildOption(
                    title: '24小時',
                    value: '24小時',
                    groupValue: tempOption,
                    accentColor: accentColor,
                    primaryTextColor: primaryTextColor,
                    onChanged: (val) {
                      setSheetState(() => tempOption = val!);
                      _updateTimer(val!);
                      Navigator.pop(context);
                    },
                  ),
                  _buildOption(
                    title: '7天',
                    value: '7天',
                    groupValue: tempOption,
                    accentColor: accentColor,
                    primaryTextColor: primaryTextColor,
                    onChanged: (val) {
                      setSheetState(() => tempOption = val!);
                      _updateTimer(val!);
                      Navigator.pop(context);
                    },
                  ),
                  _buildOption(
                    title: '90天',
                    value: '90天',
                    groupValue: tempOption,
                    accentColor: accentColor,
                    primaryTextColor: primaryTextColor,
                    onChanged: (val) {
                      setSheetState(() => tempOption = val!);
                      _updateTimer(val!);
                      Navigator.pop(context);
                    },
                  ),
                  _buildOption(
                    title: '關閉',
                    value: '關閉',
                    groupValue: tempOption,
                    accentColor: accentColor,
                    primaryTextColor: primaryTextColor,
                    onChanged: (val) {
                      setSheetState(() => tempOption = val!);
                      _updateTimer(val!);
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateTimer(String option) async {
    final timerSeconds = _parseTimerOption(option);
    try {
      final service = ref.read(chatSettingServiceProvider);
      await service.updateChatSetting(widget.roomId, timerSeconds);
      ref.invalidate(chatSettingProvider(widget.roomId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失敗: $e')),
        );
      }
    }
  }

  Widget _buildOption({
    required String title,
    required String value,
    required String groupValue,
    required Color accentColor,
    required Color primaryTextColor,
    required ValueChanged<String?> onChanged,
  }) {
    return RadioListTile<String>(
      title: Text(title, style: TextStyle(color: primaryTextColor)),
      value: value,
      groupValue: groupValue,
      activeColor: accentColor,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: brightness,
    );
    final Color bgColor = isDark
        ? const Color(0xFF0B141A)
        : colorScheme.surface;
    final Color surfaceColor = isDark
        ? const Color(0xFF111B21)
        : colorScheme.surfaceContainerHighest;
    final Color accentColor = tokens.accent;
    final Color dangerColor = colorScheme.error;
    final Color primaryTextColor = colorScheme.onSurface;
    final Color secondaryTextColor = colorScheme.onSurfaceVariant;
    final Color dividerColor = colorScheme.outlineVariant.withValues(
      alpha: 0.35,
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: surfaceColor,
            expandedHeight: 320.0,
            pinned: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: primaryTextColor),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.more_vert, color: primaryTextColor),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                widget.title,
                style: TextStyle(
                  color: primaryTextColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                ),
              ),
              background: Container(
                color: surfaceColor,
                // 使用 Center + SingleChildScrollView 避免往上捲動壓縮高度時發生 RenderFlex Overflow
                child: Center(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        Hero(tag: 'avatar_${widget.roomId}', child: _buildAvatar()),
                        const SizedBox(height: 12),
                        // 👉 3. 將原本寫死的電話改為顯示 email
                        if (!widget.isRoom && widget.email != null && widget.email!.isNotEmpty)
                          Text(
                            widget.email!,
                            style: TextStyle(
                              fontSize: 16,
                              color: secondaryTextColor,
                            ),
                          ),
                        const SizedBox(height: 40), // 預留空間給底部的 title，避免文字重疊
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 12),

              // === 媒體、連結與文件 ===
              Container(
                color: surfaceColor,
                child: ListTile(
                  title: Text(
                    '媒體、連結與文件',
                    style: TextStyle(color: primaryTextColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 👉 3. 替換原本的 '0' 為 $mediaCount
                      Text(
                        '${widget.mediaCount}',
                        style: TextStyle(color: secondaryTextColor),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: secondaryTextColor),
                    ],
                  ),
                  onTap: () {
                    // 2. 點擊後跳轉到 RoomMediaPage
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RoomMediaPage(roomId: widget.roomId),
                      ),
                    );

                    // 如果你的 go_router 已經配好了路徑，也可以改成：
                    // context.push('/rooms/${widget.roomId}/media');
                  },
                ),
              ),
              const SizedBox(height: 12),

              // === 通知設定區塊 ===
              Container(
                color: surfaceColor,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.notifications_off,
                        color: secondaryTextColor,
                      ),
                      title: Text(
                        '將通知靜音',
                        style: TextStyle(color: primaryTextColor),
                      ),
                      trailing: Switch(
                        value: false,
                        onChanged: (val) {},
                        activeThumbColor: accentColor,
                      ),
                    ),
                    Divider(height: 1, color: dividerColor),
                    ListTile(
                      leading: Icon(
                        Icons.music_note,
                        color: secondaryTextColor,
                      ),
                      title: Text(
                        '自訂通知',
                        style: TextStyle(color: primaryTextColor),
                      ),
                      onTap: () {},
                    ),
                    Divider(height: 1, color: dividerColor),
                    ListTile(
                      leading: Icon(Icons.image, color: secondaryTextColor),
                      title: Text(
                        '媒體瀏覽設定',
                        style: TextStyle(color: primaryTextColor),
                      ),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // === 隱私設定區塊 ===
              Container(
                color: surfaceColor,
                child: Column(
                  children: [
                    Consumer(
                      builder: (context, ref, child) {
                        final e2eeState = ref.watch(e2eeEnabledProvider(widget.roomId));
                        final isE2EEEnabled = e2eeState.value ?? true;

                        return ListTile(
                          leading: Icon(Icons.lock, color: secondaryTextColor),
                          title: Text('加密', style: TextStyle(color: primaryTextColor)),
                          subtitle: Text(
                            isE2EEEnabled ? '訊息和通話都受到端對端加密。點按以切換。' : '目前未加密傳輸。不建議關閉。',
                            style: TextStyle(color: secondaryTextColor, fontSize: 13),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EncryptionInfoPage(
                                  contactId: widget.roomId,
                                  contactName: widget.title,
                                  currentUserId: '', // Not strictly needed for UI shown
                                ),
                              ),
                            );
                          },
                          trailing: e2eeState.isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Switch(
                                  value: isE2EEEnabled,
                                  onChanged: (val) {
                                    if (val) {
                                      // 開啟直接套用
                                      ref.read(e2eeEnabledProvider(widget.roomId).notifier).toggle(true);
                                    } else {
                                      // 關閉需要確認
                                      showDialog(
                                        context: context,
                                        builder: (dialogCtx) => AlertDialog(
                                          backgroundColor: Theme.of(context).colorScheme.surface,
                                          title: const Text('停用加密？'),
                                          content: const Text('關閉後，與此聯絡人的訊息將不再加密傳輸，建議保持開啟以保護隱私。'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(dialogCtx),
                                              child: const Text('取消'),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                ref.read(e2eeEnabledProvider(widget.roomId).notifier).toggle(false);
                                                Navigator.pop(dialogCtx);
                                              },
                                              child: Text('停用', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  },
                                  activeThumbColor: accentColor,
                                ),
                        );
                      },
                    ),
                    Divider(height: 1, color: dividerColor),
                    Consumer(
                      builder: (context, ref, child) {
                        final settingAsync = ref.watch(chatSettingProvider(widget.roomId));
                        
                        return settingAsync.when(
                          data: (setting) {
                            final currentOption = _formatTimerOption(setting.disappearingTimer);
                            return ListTile(
                              leading: Icon(Icons.av_timer, color: secondaryTextColor),
                              title: Text(
                                '自動刪除的訊息',
                                style: TextStyle(color: primaryTextColor),
                              ),
                              subtitle: Text(
                                currentOption,
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 13,
                                ),
                              ),
                              onTap: () {
                                _showDisappearingMessagesDialog(primaryTextColor, accentColor, currentOption);
                              },
                            );
                          },
                          loading: () => ListTile(
                            leading: Icon(Icons.av_timer, color: secondaryTextColor),
                            title: Text('自動刪除的訊息', style: TextStyle(color: primaryTextColor)),
                            subtitle: const LinearProgressIndicator(),
                          ),
                          error: (err, stack) => ListTile(
                            leading: Icon(Icons.av_timer, color: secondaryTextColor),
                            title: Text('自動刪除的訊息', style: TextStyle(color: primaryTextColor)),
                            subtitle: Text('載入失敗', style: TextStyle(color: dangerColor)),
                            onTap: () => ref.refresh(chatSettingProvider(widget.roomId)),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // === 封鎖與檢舉區塊 ===
              Container(
                color: surfaceColor,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.block, color: dangerColor),
                      title: Text(
                        '封鎖 ${widget.title}',
                        style: TextStyle(color: dangerColor),
                      ),
                      onTap: () {},
                    ),
                    Divider(height: 1, color: dividerColor),
                    ListTile(
                      leading: Icon(
                        Icons.thumb_down_alt_outlined,
                        color: dangerColor,
                      ),
                      title: Text(
                        '檢舉 ${widget.title}',
                        style: TextStyle(color: dangerColor),
                      ),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return ChatAvatar(
      avatarUrl: widget.avatarUrl,
      radius: 60,
      fallbackText: widget.title.isNotEmpty ? widget.title[0].toUpperCase() : '?',
      logTag: 'contact_info',
    );
  }
}
