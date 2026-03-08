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
      print('[BackupPage] signIn result: $success'); // 加這行
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

    if (password != null && password.isEmpty)
      return; // user cancelled without skipping

    ref
        .read(backupManagerProvider.notifier)
        .backupNow(backupPassword: password);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(backupManagerProvider);

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
      backgroundColor: const Color(0xFF000000), // Match dark theme
      appBar: AppBar(
        title: const Text('備份對話'),
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Drive Icon
            const Center(
              child: Icon(Icons.add_to_drive, color: Colors.white, size: 80),
            ),
            const SizedBox(height: 16),
            const Text(
              'Google Drive 備份',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                '將您的對話記錄安全地備份至 Google Drive。如果您遺失手機或更換設備，可以輕鬆還原。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
            const SizedBox(height: 48),

            if (!_isAuthenticated) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _handleSignIn,
                    icon: const Icon(Icons.login),
                    label: const Text(
                      '連接 Google Drive',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ] else ...[
              // Authenticated State
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: const Text(
                        '上次備份',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _formatLastBackup(state.lastBackupDate),
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    SwitchListTile(
                      activeThumbColor: Colors.blueAccent,
                      title: const Text(
                        '自動備份',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '當應用程式開啟時自動背景備份',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
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
                      side: const BorderSide(color: Colors.blueAccent),
                      foregroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('查看備份記錄', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: state.isBackingUp ? null : _handleBackupNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            '立即備份',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
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
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      title: const Text('設定備份密碼', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '此密碼用於加密您的 E2EE 金鑰，還原時需要輸入相同密碼才能解密訊息。請妥善保存此密碼。',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pwdController,
              obscureText: _obscurePwd,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '密碼',
                labelStyle: const TextStyle(color: Colors.white54),
                errorText: _error,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePwd ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white54,
                  ),
                  onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                ),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: '確認密碼',
                labelStyle: const TextStyle(color: Colors.white54),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white54,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(null), // return null for skip
          child: const Text('略過（不備份金鑰）', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('確認', style: TextStyle(color: Colors.blueAccent)),
        ),
      ],
    );
  }
}
