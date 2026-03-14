import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/auth/repositories/auth_repository.dart';
import 'package:app/features/auth/providers/auth_provider.dart';

/// 🔐 E2EE Key Backup Prompt Dialog
/// 在用戶生成新金鑰後顯示，提示用戶設定備份密碼以便未來還原金鑰
class KeyBackupPromptDialog extends ConsumerStatefulWidget {
  const KeyBackupPromptDialog({super.key});

  @override
  ConsumerState<KeyBackupPromptDialog> createState() => _KeyBackupPromptDialogState();
}

class _KeyBackupPromptDialogState extends ConsumerState<KeyBackupPromptDialog> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSetupBackup() async {
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // 驗證密碼
    if (password.isEmpty) {
      setState(() {
        _errorMessage = '請輸入備份密碼';
      });
      return;
    }

    if (password.length < 8) {
      setState(() {
        _errorMessage = '密碼長度至少 8 個字元';
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _errorMessage = '兩次輸入的密碼不一致';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final crypto = ref.read(cryptoServiceProvider);
      final authRepo = ref.read(authRepositoryProvider);

      // 1. 取得當前私鑰
      final rawPrivateKey = await crypto.getRawPrivateKey();
      if (rawPrivateKey == null) {
        throw Exception('無法取得私鑰');
      }

      // 2. 使用密碼加密私鑰
      final encryptedData = await crypto.encryptPrivateKeyForBackup(
        rawPrivateKey,
        password,
      );

      // 3. 上傳到伺服器
      await authRepo.uploadKeyBackup(
        encryptedPrivateKey: encryptedData['encryptedKeyBase64']!,
        salt: encryptedData['saltBase64']!,
      );

      // 4. 更新狀態並關閉對話框
      final authNotifier = ref.read(authViewModelProvider.notifier);
      final currentState = ref.read(authViewModelProvider);
      authNotifier.state = currentState.copyWith(needsKeyBackup: false);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 金鑰備份設定成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '備份失敗：${e.toString()}';
      });
    }
  }

  void _handleSkip() {
    // 更新狀態並關閉對話框
    final authNotifier = ref.read(authViewModelProvider.notifier);
    final currentState = ref.read(authViewModelProvider);
    authNotifier.state = currentState.copyWith(needsKeyBackup: false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('🔐 設定金鑰備份'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '為了避免未來金鑰遺失，建議您設定備份密碼。',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              '備份密碼將用於加密您的私鑰並上傳到伺服器，未來更換裝置時可使用此密碼還原金鑰。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              decoration: InputDecoration(
                labelText: '備份密碼（至少 8 個字元）',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                ),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: !_isConfirmPasswordVisible,
              decoration: InputDecoration(
                labelText: '確認密碼',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _isConfirmPasswordVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  },
                ),
              ),
              enabled: !_isLoading,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : _handleSkip,
          child: const Text('稍後設定'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleSetupBackup,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('設定備份'),
        ),
      ],
    );
  }
}
