import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:app/core/backup/backup_manager.dart';
import 'package:app/features/chat/ui/backup_history_page.dart';
import 'package:app/models/backup_mode.dart';
import 'package:app/models/backup_frequency.dart';

/// 備份目的地
enum _BackupDestination { googleDrive, exportFile }

class BackupConversationsPage extends ConsumerStatefulWidget {
  const BackupConversationsPage({super.key});

  @override
  ConsumerState<BackupConversationsPage> createState() =>
      _BackupConversationsPageState();
}

class _BackupConversationsPageState
    extends ConsumerState<BackupConversationsPage> {
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _checkSignIn());
  }

  Future<void> _checkSignIn() async {
    try {
      final success = await ref
          .read(backupManagerProvider.notifier)
          .signInSilently();
      debugPrint('[BackupPage] signInSilently result: $success');
      if (mounted) setState(() => _isAuthenticated = success);
    } catch (e, st) {
      debugPrint('[BackupPage] signInSilently error: $e\n$st');
      if (mounted) setState(() => _isAuthenticated = false);
    }
  }

  Future<void> _handleSignIn() async {
    try {
      final success = await ref.read(backupManagerProvider.notifier).signIn();
      debugPrint('[BackupPage] signIn result: $success');
      if (mounted) setState(() => _isAuthenticated = success);
    } catch (e, st) {
      debugPrint('[BackupPage] signIn error: $e\n$st');
      if (mounted) {
        setState(() => _isAuthenticated = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登入失敗：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 顯示備份頻率選擇對話框
  void _showFrequencyDialog(BackupFrequency currentFrequency) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white60 : Colors.black54;
    final dialogBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: dialogBgColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('選擇備份頻率', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 18)),
        children: BackupFrequency.values.map((freq) {
          final isSelected = freq == currentFrequency;
          return SimpleDialogOption(
            onPressed: () {
              ref.read(backupManagerProvider.notifier).setAutoBackupFrequency(freq);
              Navigator.of(ctx).pop();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? const Color(0xFF007AFF) : Colors.grey,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          freq.displayName,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          freq.description,
                          style: TextStyle(fontSize: 12, color: subtitleColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 顯示備份時間選擇器
  Future<void> _showTimePicker() async {
    final currentTime = ref.read(backupManagerProvider).autoBackupTime;
    TimeOfDay initial = const TimeOfDay(hour: 3, minute: 0);
    if (currentTime != null) {
      try {
        final parts = currentTime.split(':');
        initial = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {}
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '選擇自動備份時間',
      cancelText: '取消',
      confirmText: '確認',
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(primary: Color(0xFF007AFF))
                : const ColorScheme.light(primary: Color(0xFF007AFF)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final timeStr = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      ref.read(backupManagerProvider.notifier).setAutoBackupTime(timeStr);
    }
  }

  /// 顯示備份模式選擇對話框
  void _showBackupModeDialog(BackupMode currentMode) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white60 : Colors.black54;
    final dialogBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: dialogBgColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('選擇備份模式', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 18)),
        children: BackupMode.values.map((mode) {
          final isSelected = mode == currentMode;
          return SimpleDialogOption(
            onPressed: () {
              ref.read(backupManagerProvider.notifier).setBackupMode(mode);
              Navigator.of(ctx).pop();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? const Color(0xFF007AFF) : Colors.grey,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mode.displayName,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          mode.description,
                          style: TextStyle(fontSize: 12, color: subtitleColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 顯示備份目的地選擇底部面板
  Future<_BackupDestination?> _showDestinationPicker() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.grey[600]!;
    const primaryBlue = Color(0xFF007AFF);

    return showModalBottomSheet<_BackupDestination>(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖曳指示條
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '選擇備份方式',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_to_drive_rounded, color: primaryBlue, size: 24),
                  ),
                  title: Text('備份至 Google Drive', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                  subtitle: Text('上傳至雲端，可跨裝置還原', style: TextStyle(color: subTextColor, fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () => Navigator.of(ctx).pop(_BackupDestination.googleDrive),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.file_download_outlined, color: Colors.green, size: 24),
                  ),
                  title: Text('匯出檔案', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                  subtitle: Text('匯出 JSON 檔案，可自行儲存或分享', style: TextStyle(color: subTextColor, fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () => Navigator.of(ctx).pop(_BackupDestination.exportFile),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleBackupNow() async {
    final backupMode = ref.read(backupManagerProvider).backupMode;
    
    // 根據備份模式決定是否需要密碼
    if (backupMode == BackupMode.none) {
      // none 模式：顯示提示訊息，不執行備份
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('目前備份模式設定為「不備份」，請先在設定中變更備份模式'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // 選擇備份目的地
    final destination = await _showDestinationPicker();
    if (destination == null) return; // 使用者取消
    
    String? password;
    if (backupMode == BackupMode.keyOnly) {
      // keyOnly 模式：必須輸入密碼
      password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _BackupPasswordDialog(required: true),
      );
      
      if (password == null) {
        return; // 使用者取消
      }
    } else if (backupMode == BackupMode.full) {
      // full 模式：可選擇是否輸入密碼
      password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _BackupPasswordDialog(required: false),
      );
      
      if (password != null && password.isEmpty) {
        return; // user cancelled without skipping
      }
    }

    final notifier = ref.read(backupManagerProvider.notifier);

    switch (destination) {
      case _BackupDestination.googleDrive:
        if (!_isAuthenticated) {
          // 尚未登入 Google Drive，先嘗試登入
          final success = await notifier.signIn();
          if (mounted) setState(() => _isAuthenticated = success);
          if (!success) return;
        }
        notifier.backupNow(backupPassword: password);
        break;
      case _BackupDestination.exportFile:
        notifier.exportToFile(backupPassword: password);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(backupManagerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 統一主題配色
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F6F8);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.grey[600]!;
    final primaryBlue = const Color(0xFF007AFF); // iOS 風格藍色

    ref.listen<BackupState>(backupManagerProvider, (prev, next) {
      if (next.error != null && next.error!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!), backgroundColor: Colors.red),
        );
        ref.read(backupManagerProvider.notifier).clearError();
      } else if (prev?.isBackingUp == true &&
          next.isBackingUp == false &&
          next.error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作完成！'), backgroundColor: Colors.green),
        );
      }
    });

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          '備份對話',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: textColor,
          ),
        ),
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 可滾動的上方內容區
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    // Drive Icon
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: primaryBlue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.backup_rounded, color: primaryBlue, size: 60),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '備份與匯出',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36.0),
                      child: Text(
                        '將您的對話記錄備份至 Google Drive，或匯出為檔案自行保存。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: subTextColor, fontSize: 14, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 48),

                    if (!_isAuthenticated) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _handleSignIn,
                            icon: const Icon(Icons.login_rounded, size: 20),
                            label: const Text(
                              '連接 Google Drive',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Authenticated State (卡片式設定區塊)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
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
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: Text(
                                '上次備份',
                                style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                              ),
                              trailing: Text(
                                _formatLastBackup(state.lastBackupDate),
                                style: TextStyle(color: subTextColor, fontSize: 14),
                              ),
                            ),
                            Divider(
                              height: 1,
                              indent: 16,
                              color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.07),
                            ),
                            SwitchListTile(
                              activeThumbColor: primaryBlue,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: Text(
                                '自動備份',
                                style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                '當應用程式開啟時自動背景備份',
                                style: TextStyle(color: subTextColor, fontSize: 12),
                              ),
                              value: state.autoBackupEnabled,
                              onChanged: state.isBackingUp
                                  ? null
                                  : (val) {
                                      ref
                                          .read(backupManagerProvider.notifier)
                                          .setAutoBackup(val);
                                    },
                            ),
                            // 自動備份頻率與時間設定（僅在自動備份開啟時顯示）
                            if (state.autoBackupEnabled) ...[
                              Divider(
                                height: 1,
                                indent: 16,
                                color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.07),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                title: Text(
                                  '備份頻率',
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  state.autoBackupFrequency.description,
                                  style: TextStyle(color: subTextColor, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      state.autoBackupFrequency.displayName,
                                      style: TextStyle(color: subTextColor, fontSize: 14),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.chevron_right_rounded, size: 20, color: subTextColor),
                                  ],
                                ),
                                onTap: state.isBackingUp
                                    ? null
                                    : () => _showFrequencyDialog(state.autoBackupFrequency),
                              ),
                              Divider(
                                height: 1,
                                indent: 16,
                                color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.07),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                title: Text(
                                  '備份時間',
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  '設定每次自動備份的排程時間',
                                  style: TextStyle(color: subTextColor, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      state.autoBackupTime ?? '未設定',
                                      style: TextStyle(color: subTextColor, fontSize: 14),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.chevron_right_rounded, size: 20, color: subTextColor),
                                  ],
                                ),
                                onTap: state.isBackingUp ? null : _showTimePicker,
                              ),
                            ],
                            Divider(
                              height: 1,
                              indent: 16,
                              color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.07),
                            ),
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: Text(
                                '備份模式',
                                style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                state.backupMode.displayName,
                                style: TextStyle(color: subTextColor, fontSize: 12),
                              ),
                              trailing: Icon(Icons.chevron_right_rounded, size: 20, color: subTextColor),
                              onTap: state.isBackingUp
                                  ? null
                                  : () => _showBackupModeDialog(state.backupMode),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 底部按鈕區（固定在底部）
            if (_isAuthenticated) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: state.isBackingUp
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const BackupHistoryPage(),
                              ),
                            );
                          },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                      foregroundColor: textColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('查看備份記錄', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: state.isBackingUp ? null : _handleBackupNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: state.isBackingUp
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              '備份中...',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          '立即備份',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _formatLastBackup(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '未曾備份';
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return DateFormat('yyyy/MM/dd HH:mm').format(date);
    } catch (_) {
      return '未曾備份';
    }
  }
}

// ─── 密碼輸入彈窗 ─────────────────────────────────────────────────────────────

class _BackupPasswordDialog extends StatefulWidget {
  final bool required;
  
  const _BackupPasswordDialog({this.required = false});

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _pwdController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePwd = true;
  bool _obscureConfirm = true;
  String? _error;

  void _submit() {
    final pwd = _pwdController.text;
    final confirm = _confirmController.text;

    if (pwd.length < 6) {
      setState(() => _error = '密碼長度至少需要 6 個字元');
      return;
    }
    if (pwd != confirm) {
      setState(() => _error = '兩次輸入的密碼不一致');
      return;
    }
    Navigator.of(context).pop(pwd);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white54 : Colors.black54;
    final primaryBlue = const Color(0xFF007AFF);

    final inputDecorationTheme = InputDecoration(
      filled: true,
      fillColor: isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade100,
      labelStyle: TextStyle(color: hintColor, fontSize: 14),
      errorStyle: const TextStyle(color: Colors.redAccent),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: primaryBlue, width: 1.5),
      ),
    );

    return AlertDialog(
      backgroundColor: dialogBgColor,
      surfaceTintColor: Colors.transparent, // 移除 Material 3 預設的染色
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.required ? '設定備份密碼（必填）' : '設定備份密碼',
        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.required
                  ? '僅金鑰備份模式需要設定密碼來加密您的 E2EE 金鑰。還原時需要輸入相同密碼才能解密訊息。請妥善保存此密碼。'
                  : '此密碼用於加密您的 E2EE 金鑰，還原時需要輸入相同密碼才能解密訊息。請妥善保存此密碼。',
              style: TextStyle(color: hintColor, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _pwdController,
              obscureText: _obscurePwd,
              style: TextStyle(color: textColor),
              decoration: inputDecorationTheme.copyWith(
                labelText: '密碼',
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePwd ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    color: hintColor,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                ),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              style: TextStyle(color: textColor),
              decoration: inputDecorationTheme.copyWith(
                labelText: '確認密碼',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    color: hintColor,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        if (!widget.required)
          TextButton(
            onPressed: () => Navigator.of(context).pop(null), // return null for skip
            child: Text('略過 (不備份金鑰)', style: TextStyle(color: hintColor, fontWeight: FontWeight.w500)),
          ),
        if (widget.required)
          TextButton(
            onPressed: () => Navigator.of(context).pop(null), // return null for cancel
            child: Text('取消', style: TextStyle(color: hintColor, fontWeight: FontWeight.w500)),
          ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('確認', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}