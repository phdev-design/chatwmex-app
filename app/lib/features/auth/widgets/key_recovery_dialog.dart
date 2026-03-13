import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/auth/providers/auth_provider.dart';

class KeyRecoveryDialog extends ConsumerStatefulWidget {
  const KeyRecoveryDialog({super.key});

  @override
  ConsumerState<KeyRecoveryDialog> createState() => _KeyRecoveryDialogState();
}

class _KeyRecoveryDialogState extends ConsumerState<KeyRecoveryDialog> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRecoverFromBackup() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      return;
    }
    await ref.read(authViewModelProvider.notifier).recoverKeyFromBackup(password);
  }

  Future<void> _handleForceGenerateNewKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認強制生成新金鑰'),
        content: const Text(
          '強制生成新金鑰後，您將無法解密任何歷史訊息。此操作無法復原。\n\n確定要繼續嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('確定生成'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(authViewModelProvider.notifier).forceGenerateNewKey();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authViewModelProvider);

    // 當還原成功時自動關閉對話框
    ref.listen<AuthState>(authViewModelProvider, (previous, next) {
      if (previous?.needsKeyRecovery == true && 
          next.needsKeyRecovery == false && 
          next.isAuthenticated) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    });

    return AlertDialog(
      title: const Text('偵測到金鑰遺失'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '您的加密金鑰在本地裝置上找不到。您可以使用備份密碼還原金鑰，或強制生成新金鑰（將無法解密歷史訊息）。',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '備份密碼',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              enabled: !authState.isLoading,
            ),
            if (authState.error != null) ...[
              const SizedBox(height: 12),
              Text(
                authState.error!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: authState.isLoading ? null : _handleForceGenerateNewKey,
          child: const Text('強制生成新金鑰'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: authState.isLoading ? null : _handleRecoverFromBackup,
          child: authState.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('從雲端還原金鑰'),
        ),
      ],
    );
  }
}
