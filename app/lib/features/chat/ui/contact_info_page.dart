import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:app/features/chat/ui/room_media_page.dart';
import 'package:app/features/chat/providers/chat_setting_provider.dart';
import 'package:app/features/chat/providers/e2ee_provider.dart';
import 'package:app/features/chat/ui/encryption_info_page.dart';
import 'package:app/features/chat/ui/media_visibility_settings_page.dart';
import 'package:app/features/friend/providers/friend_provider.dart';
import 'package:app/features/friend/repositories/friend_repository.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/features/chat/providers/room_list_provider.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/core/backup/backup_manager.dart';

class ContactInfoPage extends ConsumerStatefulWidget {
  final String roomId;
  final String title;
  final bool isRoom;
  final String? avatarUrl;
  final int mediaCount;
  final String? email;
  final String currentUserId;
  final String? ownerId;

  const ContactInfoPage({
    super.key,
    required this.roomId,
    required this.title,
    this.isRoom = false,
    this.avatarUrl,
    this.mediaCount = 0,
    this.email,
    required this.currentUserId,
    this.ownerId,
  });

  @override
  ConsumerState<ContactInfoPage> createState() => _ContactInfoPageState();
}

class _ContactInfoPageState extends ConsumerState<ContactInfoPage> {
  bool _isBlocked = false;
  String? _localAvatarUrl;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _localAvatarUrl = widget.avatarUrl;
    _checkBlockStatus();
  }

  Future<void> _checkBlockStatus() async {
    try {
      final isBlocked = await ref
          .read(friendRepositoryProvider)
          .isBlocked(widget.roomId);
      if (mounted) setState(() => _isBlocked = isBlocked);
    } catch (e) {
      debugPrint('檢查封鎖狀態失敗: $e');
    }
  }

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
    return 0;
  }

  void _showDisappearingMessagesDialog(
    Color primaryTextColor,
    Color accentColor,
    String currentOption,
  ) {
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
                  RadioGroup<String>(
                    onChanged: (val) {
                      if (val != null) {
                        setSheetState(() => tempOption = val);
                        _updateTimer(val);
                        Navigator.pop(context);
                      }
                    },
                    child: Column(
                      children: [
                        _buildTimerOption(
                          '24小時',
                          tempOption,
                          accentColor,
                          primaryTextColor,
                          (val) {
                            setSheetState(() => tempOption = val!);
                            _updateTimer(val!);
                            Navigator.pop(context);
                          },
                        ),
                        _buildTimerOption(
                          '7天',
                          tempOption,
                          accentColor,
                          primaryTextColor,
                          (val) {
                            setSheetState(() => tempOption = val!);
                            _updateTimer(val!);
                            Navigator.pop(context);
                          },
                        ),
                        _buildTimerOption(
                          '90天',
                          tempOption,
                          accentColor,
                          primaryTextColor,
                          (val) {
                            setSheetState(() => tempOption = val!);
                            _updateTimer(val!);
                            Navigator.pop(context);
                          },
                        ),
                        _buildTimerOption(
                          '關閉',
                          tempOption,
                          accentColor,
                          primaryTextColor,
                          (val) {
                            setSheetState(() => tempOption = val!);
                            _updateTimer(val!);
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
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

  Widget _buildTimerOption(
    String title,
    String groupValue,
    Color accentColor,
    Color primaryTextColor,
    ValueChanged<String?> onChanged,
  ) {
    return RadioListTile<String>(
      title: Text(title, style: TextStyle(color: primaryTextColor)),
      value: title,
      activeColor: accentColor,
      toggleable: false,
    );
  }

  void _showMuteDialog(
    Color primaryTextColor,
    Color accentColor,
    int? currentMuteUntil,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                '將通知靜音',
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
                  '選擇靜音持續時間，期間不會收到此對話的通知。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildMuteOptionTile(
                title: '8小時',
                textColor: primaryTextColor,
                onTap: () {
                  final until = DateTime.now().add(const Duration(hours: 8));
                  _updateMute(until.millisecondsSinceEpoch ~/ 1000);
                  Navigator.pop(context);
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor),
              _buildMuteOptionTile(
                title: '1星期',
                textColor: primaryTextColor,
                onTap: () {
                  final until = DateTime.now().add(const Duration(days: 7));
                  _updateMute(until.millisecondsSinceEpoch ~/ 1000);
                  Navigator.pop(context);
                },
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor),
              _buildMuteOptionTile(
                title: '保持關閉',
                textColor: primaryTextColor,
                onTap: () {
                  _updateMute(-1);
                  Navigator.pop(context);
                },
              ),
              if (currentMuteUntil != null) ...[
                Divider(height: 1, color: Theme.of(context).dividerColor),
                _buildMuteOptionTile(
                  title: '取消靜音',
                  textColor: Colors.red,
                  onTap: () {
                    _updateMute(null);
                    Navigator.pop(context);
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMuteOptionTile({
    required String title,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(title, style: TextStyle(color: textColor, fontSize: 16)),
      onTap: onTap,
    );
  }

  Future<void> _updateMute(int? muteUntil) async {
    try {
      final service = ref.read(chatSettingServiceProvider);
      await service.updateMuteUntil(widget.roomId, muteUntil);
      ref.invalidate(chatSettingProvider(widget.roomId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新失敗: $e')));
      }
    }
  }

  void _confirmUnfriend(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('解除好友'),
        content: Text('確定要與 ${widget.title} 解除好友關係嗎？解除後對方將無法繼續傳訊息，但歷史記錄將保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await ref
                    .read(friendViewModelProvider.notifier)
                    .unfriend(widget.roomId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已解除與 ${widget.title} 的好友關係')),
                  );
                  context.pop();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('解除失敗：$e')));
                }
              }
            },
            child: const Text('解除好友', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('更新失敗: $e')));
      }
    }
  }

  Future<void> _exportRoomBackup(
    Color primaryTextColor,
    Color secondaryTextColor,
    Color accentColor,
    Color cardColor,
    bool isDark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(widget.isRoom ? '備份群組對話' : '備份對話'),
        content: Text(
          widget.isRoom
              ? '將匯出「${widget.title}」群組的所有聊天記錄為 JSON 檔案，您可以儲存或分享此檔案。'
              : '將匯出與「${widget.title}」的所有聊天記錄為 JSON 檔案，您可以儲存或分享此檔案。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('匯出', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final localDb = LocalDbService();
      final messages = await localDb.getMessagesByRoom(
        widget.roomId,
        limit: 999999,
        offset: 0,
      );

      final payload = {
        'backup_date': DateTime.now().toIso8601String(),
        'backup_type': widget.isRoom ? 'group' : 'direct',
        'room_id': widget.roomId,
        'room_name': widget.title,
        'message_count': messages.length,
        'conversations': messages.map((m) => m.toMap()).toList(),
      };

      final jsonString = jsonEncode(payload);
      final dir = await getTemporaryDirectory();
      final safeName = widget.title.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), '_');
      final fileName = 'backup_${safeName}_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonString);

      if (!mounted) return;
      Navigator.pop(context); // close loading

      await Share.shareXFiles(
        [XFile(file.path)],
        text: widget.isRoom
            ? '${widget.title} 群組對話備份（${messages.length} 則訊息）'
            : '與 ${widget.title} 的對話備份（${messages.length} 則訊息）',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('備份失敗：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    String? displayAvatarUrl = _localAvatarUrl;
    if (widget.isRoom) {
      final roomState = ref.watch(roomListViewModelProvider);
      try {
        final room = roomState.rooms.cast<dynamic>().firstWhere(
          (r) => r.id == widget.roomId,
          orElse: () => null,
        );
        if (room != null &&
            room.avatarUrl != null &&
            (room.avatarUrl as String).isNotEmpty) {
          displayAvatarUrl = room.avatarUrl as String;
        }
      } catch (e) { 
        debugPrint('Error caught: $e'); 
      }
    }

    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: brightness,
    );
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F6F8);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final accentColor = tokens.accent;
    final dangerColor = colorScheme.error;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.07);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar ─────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: cardColor,
            expandedHeight: 300.0,
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: isDark ? Colors.white : Colors.black87,
              ),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.more_vert,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: cardColor,
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 32),
                      Hero(
                        tag: 'avatar_${widget.roomId}',
                        child: _buildAvatar(displayAvatarUrl, isDark),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.title,
                              style: TextStyle(
                                color: primaryTextColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 22,
                                letterSpacing: -0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.isRoom) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '群組',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (!widget.isRoom &&
                          widget.email != null &&
                          widget.email!.isNotEmpty)
                        Text(
                          widget.email!,
                          style: TextStyle(
                            fontSize: 14,
                            color: secondaryTextColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 20),

              // ── Quick Actions ───────────────────────────────────────
              _QuickActionsRow(
                isDark: isDark,
                cardColor: cardColor,
                accentColor: accentColor,
                onMessage: () => context.pop(),
              ),
              const SizedBox(height: 20),

              // ── SECTION: 媒體與文件 ─────────────────────────────────
              _SectionHeader(label: '媒體與文件', isDark: isDark),
              _InfoCard(
                isDark: isDark,
                cardColor: cardColor,
                dividerColor: dividerColor,
                children: [
                  _InfoTile(
                    icon: Icons.photo_library_rounded,
                    iconColor: const Color(0xFF5157AE),
                    label: '媒體、連結與文件',
                    trailing: Text(
                      '${widget.mediaCount}',
                      style: TextStyle(fontSize: 15, color: secondaryTextColor),
                    ),
                    isDark: isDark,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            RoomMediaPage(roomId: widget.roomId),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── SECTION: 備份 ───────────────────────────────────────
              _SectionHeader(
                label: widget.isRoom ? '群組備份' : '對話備份',
                isDark: isDark,
              ),
              _InfoCard(
                isDark: isDark,
                cardColor: cardColor,
                dividerColor: dividerColor,
                children: [
                  _InfoTile(
                    icon: Icons.backup_rounded,
                    iconColor: const Color(0xFF34C759),
                    label: widget.isRoom ? '備份此群組對話' : '備份此對話',
                    subtitle: '匯出聊天記錄為 JSON 檔案',
                    isDark: isDark,
                    onTap: () => _exportRoomBackup(
                      primaryTextColor,
                      secondaryTextColor,
                      accentColor,
                      cardColor,
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── SECTION: 通知與隱私 ─────────────────────────────────
              _SectionHeader(label: '通知與隱私', isDark: isDark),
              _InfoCard(
                isDark: isDark,
                cardColor: cardColor,
                dividerColor: dividerColor,
                children: [
                  // Mute
                  Consumer(
                    builder: (context, ref, _) {
                      final settingAsync = ref.watch(
                        chatSettingProvider(widget.roomId),
                      );
                      return settingAsync.when(
                        data: (setting) => _InfoTile(
                          icon: Icons.notifications_off_rounded,
                          iconColor: const Color(0xFF8E8E93),
                          label: '將通知靜音',
                          subtitle: setting.isMuted
                              ? setting.muteDescription
                              : null,
                          isDark: isDark,
                          trailing: Switch(
                            value: setting.isMuted,
                            onChanged: (val) {
                              if (val) {
                                _showMuteDialog(
                                  primaryTextColor,
                                  accentColor,
                                  setting.muteUntil,
                                );
                              } else {
                                _updateMute(null);
                              }
                            },
                            activeThumbColor: accentColor,
                          ),
                        ),
                        loading: () => _InfoTile(
                          icon: Icons.notifications_off_rounded,
                          iconColor: const Color(0xFF8E8E93),
                          label: '將通知靜音',
                          isDark: isDark,
                          trailing: const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        error: (_, _) => _InfoTile(
                          icon: Icons.notifications_off_rounded,
                          iconColor: const Color(0xFF8E8E93),
                          label: '將通知靜音',
                          isDark: isDark,
                          trailing: Switch(value: false, onChanged: null),
                        ),
                      );
                    },
                  ),

                  // E2EE
                  Consumer(
                    builder: (context, ref, _) {
                      final e2eeState = ref.watch(
                        e2eeEnabledProvider(widget.roomId),
                      );
                      final isE2EEEnabled = e2eeState.value ?? true;
                      return _InfoTile(
                        icon: Icons.lock_rounded,
                        iconColor: const Color(0xFF34C759),
                        label: '加密',
                        subtitle: isE2EEEnabled ? '端對端加密已啟用' : '目前未加密傳輸',
                        isDark: isDark,
                        trailing: e2eeState.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Switch(
                                value: isE2EEEnabled,
                                onChanged: (val) {
                                  if (val) {
                                    ref
                                        .read(
                                          e2eeEnabledProvider(
                                            widget.roomId,
                                          ).notifier,
                                        )
                                        .toggle(true);
                                  } else {
                                    showDialog(
                                      context: context,
                                      builder: (dialogCtx) => AlertDialog(
                                        backgroundColor: Theme.of(
                                          context,
                                        ).colorScheme.surface,
                                        title: const Text('停用加密？'),
                                        content: const Text(
                                          '關閉後，與此聯絡人的訊息將不再加密傳輸，建議保持開啟以保護隱私。',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dialogCtx),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              ref
                                                  .read(
                                                    e2eeEnabledProvider(
                                                      widget.roomId,
                                                    ).notifier,
                                                  )
                                                  .toggle(false);
                                              Navigator.pop(dialogCtx);
                                            },
                                            child: Text(
                                              '停用',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                                activeThumbColor: accentColor,
                              ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EncryptionInfoPage(
                              contactId: widget.roomId,
                              contactName: widget.title,
                              currentUserId: '',
                              isRoom: widget.isRoom,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // Disappearing messages
                  Consumer(
                    builder: (context, ref, _) {
                      final settingAsync = ref.watch(
                        chatSettingProvider(widget.roomId),
                      );
                      return settingAsync.when(
                        data: (setting) {
                          final currentOption = _formatTimerOption(
                            setting.disappearingTimer,
                          );
                          return _InfoTile(
                            icon: Icons.av_timer_rounded,
                            iconColor: const Color(0xFFFF9500),
                            label: '自動刪除的訊息',
                            subtitle: currentOption,
                            isDark: isDark,
                            onTap: () => _showDisappearingMessagesDialog(
                              primaryTextColor,
                              accentColor,
                              currentOption,
                            ),
                          );
                        },
                        loading: () => _InfoTile(
                          icon: Icons.av_timer_rounded,
                          iconColor: const Color(0xFFFF9500),
                          label: '自動刪除的訊息',
                          isDark: isDark,
                          trailing: const SizedBox(
                            width: 60,
                            child: LinearProgressIndicator(),
                          ),
                        ),
                        error: (_, _) => _InfoTile(
                          icon: Icons.av_timer_rounded,
                          iconColor: const Color(0xFFFF9500),
                          label: '自動刪除的訊息',
                          subtitle: '載入失敗',
                          isDark: isDark,
                          onTap: () =>
                              ref.refresh(chatSettingProvider(widget.roomId)),
                        ),
                      );
                    },
                  ),

                  // Media visibility
                  _InfoTile(
                    icon: Icons.image_rounded,
                    iconColor: const Color(0xFF4F8EF7),
                    label: '媒體瀏覽設定',
                    isDark: isDark,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            MediaVisibilitySettingsPage(roomId: widget.roomId),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── SECTION: 群組管理 ────────────────────────────────────
              if (widget.isRoom) ...[
                _SectionHeader(label: '群組管理', isDark: isDark),
                _InfoCard(
                  isDark: isDark,
                  cardColor: cardColor,
                  dividerColor: dividerColor,
                  children: [
                    _InfoTile(
                      icon: Icons.group_rounded,
                      iconColor: const Color(0xFF5157AE),
                      label: '群組成員',
                      isDark: isDark,
                      onTap: () => context.push(
                        '/group-members',
                        extra: {
                          'roomId': widget.roomId,
                          'ownerId': widget.ownerId,
                          'currentUserId': widget.currentUserId,
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // ── SECTION: 危險操作 ────────────────────────────────────
              _SectionHeader(label: '危險操作', isDark: isDark),
              _InfoCard(
                isDark: isDark,
                cardColor: cardColor,
                dividerColor: dividerColor,
                children: [
                  if (!widget.isRoom)
                    _InfoTile(
                      icon: Icons.person_remove_rounded,
                      iconColor: dangerColor,
                      label: '解除好友',
                      labelColor: dangerColor,
                      showChevron: false,
                      isDark: isDark,
                      onTap: () => _confirmUnfriend(context),
                    ),
                  _InfoTile(
                    icon: Icons.block_rounded,
                    iconColor: dangerColor,
                    label: _isBlocked
                        ? '解除封鎖 ${widget.title}'
                        : '封鎖 ${widget.title}',
                    labelColor: dangerColor,
                    showChevron: false,
                    isDark: isDark,
                    onTap: () async {
                      final action = _isBlocked ? '解除封鎖' : '封鎖';
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          title: Text('$action ${widget.title}？'),
                          content: _isBlocked
                              ? const Text('解除封鎖後，對方可以再次傳訊息給你和發送好友申請。')
                              : const Text('封鎖後，對方無法傳訊息給你，也無法發送好友申請，直至你解除封鎖。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: Text(action),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      try {
                        if (_isBlocked) {
                          await ref
                              .read(friendViewModelProvider.notifier)
                              .unblockUser(widget.roomId);
                        } else {
                          await ref
                              .read(friendViewModelProvider.notifier)
                              .blockUser(widget.roomId);
                        }
                        setState(() => _isBlocked = !_isBlocked);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _isBlocked
                                  ? '已封鎖 ${widget.title}'
                                  : '已解除封鎖 ${widget.title}',
                            ),
                          ),
                        );
                        if (_isBlocked) context.pop();
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('操作失敗：$e'))
                        );
                      }
                    },
                  ),
                  _InfoTile(
                    icon: Icons.thumb_down_alt_rounded,
                    iconColor: dangerColor,
                    label: '檢舉 ${widget.title}',
                    labelColor: dangerColor,
                    showChevron: false,
                    isDark: isDark,
                    onTap: () {},
                  ),
                  if (widget.isRoom) ...[
                    _InfoTile(
                      icon: Icons.exit_to_app_rounded,
                      iconColor: dangerColor,
                      label: '退出群組',
                      labelColor: dangerColor,
                      showChevron: false,
                      isDark: isDark,
                      onTap: () async {
                        final isOwner = widget.currentUserId == widget.ownerId;
                        if (isOwner) {
                          if (!mounted) return;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );

                          List<dynamic> members = [];
                          try {
                            members = await ref
                                .read(roomListViewModelProvider.notifier)
                                .getRoomMemberProfiles(widget.roomId);
                          } catch (e) {
                            if (!context.mounted) return;
                            Navigator.pop(context); // close loading
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('無法取得群組成員：$e')),
                            );
                            return;
                          }

                          if (!context.mounted) return;
                          Navigator.pop(context); // close loading

                          final remainingMembers = members
                              .where((m) => m['id'] != widget.currentUserId)
                              .toList();

                          if (remainingMembers.isEmpty) {
                            if (!mounted) return;
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                title: const Text('解散群組'),
                                content: const Text(
                                  '群組僅剩您一人，退出將直接解散群組。確定要解散嗎？',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('解散'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;

                            if (!context.mounted) return;
                            try {
                              await ref
                                  .read(roomListViewModelProvider.notifier)
                                  .deleteRoom(widget.roomId);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('群組已解散')),
                              );
                              context.go('/rooms');
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('解散群組失敗：$e')),
                              );
                            }
                          } else {
                            if (!mounted) return;
                            final selectedUserId =
                                await showModalBottomSheet<String>(
                                  context: context,
                                  backgroundColor: isDark
                                      ? const Color(0xFF1C1C1E)
                                      : Colors.white,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                  ),
                                  builder: (ctx) {
                                    return SafeArea(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(height: 8),
                                          Container(
                                            width: 36,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withValues(
                                                alpha: 0.3,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          const Text(
                                            '選擇新管理員',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const Padding(
                                            padding: EdgeInsets.all(16.0),
                                            child: Text(
                                              '身為管理員，退出群組前必須先轉交管理員權限給其他成員。',
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                          Flexible(
                                            child: ListView.builder(
                                              shrinkWrap: true,
                                              itemCount:
                                                  remainingMembers.length,
                                              itemBuilder: (context, index) {
                                                final m =
                                                    remainingMembers[index];
                                                final name =
                                                    m['username'] ?? '使用者';
                                                final avatarUrl =
                                                    m['avatar_url'] as String?;
                                                return ListTile(
                                                  leading: CircleAvatar(
                                                    backgroundColor: Colors.grey
                                                        .withValues(alpha: 0.2),
                                                    backgroundImage:
                                                        (avatarUrl != null &&
                                                            avatarUrl
                                                                .isNotEmpty)
                                                        ? NetworkImage(
                                                            resolveFullUrl(
                                                              avatarUrl,
                                                            ),
                                                          )
                                                        : null,
                                                    child:
                                                        (avatarUrl == null ||
                                                            avatarUrl.isEmpty)
                                                        ? Text(
                                                            name.isNotEmpty
                                                                ? name[0]
                                                                      .toUpperCase()
                                                                : '?',
                                                          )
                                                        : null,
                                                  ),
                                                  title: Text(name),
                                                  onTap: () => Navigator.pop(
                                                    ctx,
                                                    m['id'],
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );

                            if (selectedUserId == null || !mounted) return;

                            final newOwnerName =
                                remainingMembers.firstWhere(
                                  (m) => m['id'] == selectedUserId,
                                )['username'] ??
                                '該成員';

                            if (!context.mounted) return;
                            final confirmTransfer = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                title: const Text('轉交管理員並退出'),
                                content: Text(
                                  '確定要將管理員轉交給 $newOwnerName 並退出群組嗎？',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                    child: const Text('確認退出'),
                                  ),
                                ],
                              ),
                            );

                            if (confirmTransfer != true) return;

                            if (!context.mounted) return;
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );

                            try {
                              await ref
                                  .read(roomListViewModelProvider.notifier)
                                  .transferOwnership(
                                    widget.roomId,
                                    selectedUserId,
                                  );
                              await ref
                                  .read(roomListViewModelProvider.notifier)
                                  .leaveRoom(widget.roomId);

                              if (!context.mounted) return;
                              Navigator.pop(context); // close loading
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已成功轉交權限並退出群組')),
                              );
                              context.go('/rooms');
                            } catch (e) {
                              if (!context.mounted) return;
                              Navigator.pop(context); // close loading
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('操作失敗：$e')),
                              );
                            }
                          }
                        } else {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              title: const Text('確定要退出此群組嗎？'),
                              content: const Text('退出後，您將無法再接收此群組的任何新訊息。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('退出'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;

                          if (!context.mounted) return;
                          // Show a loading indicator dialogue optionally, or just let the async operation run
                          try {
                            await ref
                                .read(roomListViewModelProvider.notifier)
                                .leaveRoom(widget.roomId);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已退出群組')),
                            );
                            // Navigate back to the main chat list
                            // Assuming /rooms is the route for the main tab view where chat list lives
                            context.go('/rooms');
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('退出群組失敗：$e')),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }

  void _showAvatarActionSheet() {
    if (!widget.isRoom) return;
    if (widget.currentUserId != widget.ownerId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('只有管理員可以修改群組圖示')));
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('從相簿選擇'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadGroupIcon(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadGroupIcon(ImageSource.camera);
              },
            ),
            if (_localAvatarUrl != null && _localAvatarUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(
                  Icons.delete_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  '移除群組圖示',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeGroupIcon();
                },
              ),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('取消'),
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _removeGroupIcon() async {
    if (mounted) setState(() => _isUploadingAvatar = true);
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      await chatRepo.updateRoom(widget.roomId, avatarUrl: '');
      if (mounted) {
        setState(() => _localAvatarUrl = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('群組圖示已移除')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('移除失敗：$e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _pickAndUploadGroupIcon(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 100,
      );
      if (pickedFile == null) return;
      if (mounted) setState(() => _isUploadingAvatar = true);

      int quality = 90;
      File? targetFile;
      final tmpDir = await Directory.systemTemp.createTemp();
      final targetPath =
          '${tmpDir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';

      while (quality > 10) {
        final xfile = await FlutterImageCompress.compressAndGetFile(
          pickedFile.path,
          targetPath,
          quality: quality,
          minWidth: 256,
          minHeight: 256,
          format: CompressFormat.jpeg,
        );
        if (xfile == null) break;
        final size = await xfile.length();
        if (size <= 200 * 1024) {
          targetFile = File(xfile.path);
          break;
        }
        quality -= 10;
      }

      if (targetFile == null) throw Exception('壓縮失敗');
      final finalSize = await targetFile.length();
      if (finalSize > 500 * 1024) throw Exception('圖示檔案過大，請選擇其他圖片');

      final chatRepo = ref.read(chatRepositoryProvider);
      final uploadedUrl = await chatRepo.uploadMedia(targetFile, 'image');
      if (uploadedUrl.isNotEmpty) {
        await chatRepo.updateRoom(widget.roomId, avatarUrl: uploadedUrl);
        if (mounted) {
          setState(() => _localAvatarUrl = uploadedUrl);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('群組圖示已更新')));
        }
      }
    } catch (e) {
      debugPrint('上傳群組圖示失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失敗：$e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Widget _buildAvatar(String? currentAvatarUrl, bool isDark) {
    final avatarWidget = ChatAvatar(
      avatarUrl: currentAvatarUrl,
      radius: 54,
      fallbackText: widget.title.isNotEmpty
          ? widget.title[0].toUpperCase()
          : '?',
      logTag: 'contact_info',
    );

    if (widget.isRoom && widget.currentUserId == widget.ownerId) {
      final double diameter = 108; // radius 54 * 2
      return SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isUploadingAvatar ? null : _showAvatarActionSheet,
                customBorder: const CircleBorder(),
                child: avatarWidget,
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
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
                  size: 14,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
            if (_isUploadingAvatar) const CircularProgressIndicator(),
          ],
        ),
      );
    }
    return avatarWidget;
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool isDark;
  const _SectionHeader({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: isDark ? Colors.white38 : Colors.grey[500],
        ),
      ),
    );
  }
}

// ─── Info Card ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final bool isDark;
  final Color cardColor;
  final Color dividerColor;
  final List<Widget> children;

  const _InfoCard({
    required this.isDark,
    required this.cardColor,
    required this.dividerColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, indent: 54, color: dividerColor),
          ],
        ],
      ),
    );
  }
}

// ─── Info Tile ────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDark;
  final bool showChevron;

  const _InfoTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isDark,
    this.labelColor,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = labelColor ?? (isDark ? Colors.white : Colors.black87);
    final subColor = isDark ? Colors.white54 : Colors.grey[600]!;
    final chevronColor = isDark ? Colors.white24 : Colors.black26;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (showChevron)
              Icon(Icons.chevron_right_rounded, size: 20, color: chevronColor),
          ],
        ),
      ),
    );
  }
}

// ─── Quick Actions Row ───────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  final bool isDark;
  final Color cardColor;
  final Color accentColor;
  final VoidCallback onMessage;

  const _QuickActionsRow({
    required this.isDark,
    required this.cardColor,
    required this.accentColor,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _QuickActionButton(
            icon: Icons.chat_bubble_rounded,
            label: '訊息',
            color: accentColor,
            isDark: isDark,
            onTap: onMessage,
          ),
          _QuickActionButton(
            icon: Icons.call_rounded,
            label: '語音',
            color: const Color(0xFF34C759),
            isDark: isDark,
            onTap: () {},
          ),
          _QuickActionButton(
            icon: Icons.videocam_rounded,
            label: '視訊',
            color: const Color(0xFFFF9500),
            isDark: isDark,
            onTap: () {},
          ),
          _QuickActionButton(
            icon: Icons.search_rounded,
            label: '搜尋',
            color: const Color(0xFF5157AE),
            isDark: isDark,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}