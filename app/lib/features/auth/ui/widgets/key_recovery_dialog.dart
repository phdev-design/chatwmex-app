import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/auth/providers/auth_provider.dart';
import 'package:app/features/auth/repositories/auth_repository.dart';

/// 🔐 E2EE Key Recovery Dialog
/// 當偵測到私鑰遺失時顯示此對話框，讓用戶選擇：
/// 1. 從雲端還原金鑰（需要輸入備份密碼）
/// 2. 強制生成新金鑰（歷史訊息將無法解密）
class KeyRecoveryDialog extends ConsumerStatefulWidget {
  const KeyRecoveryDialog({super.key});

  @override
  ConsumerState<KeyRecoveryDialog> createState() => _KeyRecoveryDialogState();
}

class _KeyRecoveryDialogState extends ConsumerState<KeyRecoveryDialog> {
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isCheckingBackup = true;
  bool _hasBackup = false;

  @override
  void initState() {
    super.initState();
    _checkBackupAvailability();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBackupAvailability() async {
    // 檢查伺服器是否有備份
    final authRepo = ref.read(authRepositoryProvider);
    final backup = await authRepo.getKeyBackup();
    
    setState(() {
      _isCheckingBackup = false;
      _hasBackup = backup != null;
    });
  }

  Future<void> _handleRestore() async {
    final password = _passwordController.text.trim();
    
    if (password.isEmpty) {
      _showError('請輸入備份密碼');
      return;
    }

    await ref.read(authViewModelProvider.notifier).recoverKeyFromBackup(password);
    
    final authState = ref.read(authViewModelProvider);
    if (authState.isAuthenticated && !authState.needsKeyRecovery) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    } else if (authState.error != null) {
      _showError(authState.error!);
    }
  }

  Future<void> _handleForceGenerate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 確認生成新金鑰'),
        content: const Text(
          '您的加密金鑰已遺失，無法復原舊訊息。\n\n'
          '生成新金鑰後：\n'
          '• 所有歷史訊息將永久無法解密\n'
          '• 新訊息將正常加密運作\n\n'
          '確定要繼續嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('確定生成'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authViewModelProvider.notifier).forceGenerateNewKey();
      
      final authState = ref.read(authViewModelProvider);
      if (authState.isAuthenticated && !authState.needsKeyRecovery) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authViewModelProvider);

    return PopScope(
      canPop: false, // 防止用戶按返回鍵關閉對話框
      child: AlertDialog(
        title: const Text('🔐 金鑰遺失'),
        content: _isCheckingBackup
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '偵測到您的加密金鑰已遺失（可能是重新安裝應用或更換裝置）。',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    if (_hasBackup) ...[
                      const Text(
                        '✅ 伺服器上有您的金鑰備份',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '請輸入備份密碼以還原金鑰：',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: '備份密碼',
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
                        enabled: !authState.isLoading,
                      ),
                    ] else ...[
                      const Text(
                        '❌ 伺服器上沒有金鑰備份',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '您需要生成新的金鑰對。請注意：\n'
                        '• 所有歷史訊息將永久無法解密\n'
                        '• 新訊息將正常加密運作',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ],
                ),
              ),
        actions: _isCheckingBackup
            ? null
            : [
                if (_hasBackup) ...[
                  TextButton(
                    onPressed: authState.isLoading ? null : _handleForceGenerate,
                    child: const Text('生成新金鑰'),
                  ),
                  ElevatedButton(
                    onPressed: authState.isLoading ? null : _handleRestore,
                    child: authState.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('還原金鑰'),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: authState.isLoading ? null : _handleForceGenerate,
                    child: authState.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('生成新金鑰'),
                  ),
                ],
              ],
      ),
    );
  }
}
