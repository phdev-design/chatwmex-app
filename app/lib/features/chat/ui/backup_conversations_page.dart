import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:app/core/backup/backup_manager.dart';
import 'package:app/features/chat/ui/backup_history_page.dart';

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

  Future<void> _handleBackupNow() async {
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _BackupPasswordDialog(),
    );

    if (password != null && password.isEmpty) {
      return; // user cancelled without skipping
    }

    ref
        .read(backupManagerProvider.notifier)
        .backupNow(backupPassword: password);
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
          const SnackBar(content: Text('備份完成！'), backgroundColor: Colors.green),
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
            const SizedBox(height: 40),
            // Drive Icon
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_to_drive_rounded, color: primaryBlue, size: 60),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Google Drive 備份',
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
                '將您的對話記錄安全地備份至 Google Drive。如果您遺失手機或更換設備，可以輕鬆還原。',
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
                      activeColor: primaryBlue,
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
                  ],
                ),
              ),
              const Spacer(),
              
              // 底部按鈕區
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
  const _BackupPasswordDialog();

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

    if (pwd.length < 8) {
      setState(() => _error = '密碼長度至少需要 8 個字元');
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
        '設定備份密碼',
        style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '此密碼用於加密您的 E2EE 金鑰，還原時需要輸入相同密碼才能解密訊息。請妥善保存此密碼。',
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(null), // return null for skip
          child: Text('略過 (不備份金鑰)', style: TextStyle(color: hintColor, fontWeight: FontWeight.w500)),
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