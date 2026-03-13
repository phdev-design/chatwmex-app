import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:app/core/backup/backup_manager.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/models/backup_file_info.dart';
import 'package:app/core/backup/google_drive_service.dart';

class BackupHistoryPage extends ConsumerStatefulWidget {
  const BackupHistoryPage({super.key});

  @override
  ConsumerState<BackupHistoryPage> createState() => _BackupHistoryPageState();
}

class _BackupHistoryPageState extends ConsumerState<BackupHistoryPage> {
  bool _isLoading = true;
  List<BackupFileInfo> _backups = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final googleDriveService = ref.read(googleDriveServiceProvider);
      final backupFiles = await googleDriveService.listAllBackups();
      if (mounted) {
        setState(() {
          _backups = backupFiles;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '無法取得備份記錄: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '未知時間';
    try {
      final date = DateTime.parse(isoDate).toLocal();
      return DateFormat('yyyy/MM/dd HH:mm:ss').format(date);
    } catch (_) {
      return isoDate;
    }
  }

  Future<void> _showRestoreConfirmation(BackupFileInfo backup) async {
    // 根據備份類型顯示不同的確認對話框
    final String title = backup.type == BackupType.keyOnly
        ? '還原金鑰備份？'
        : '還原此備份？';
    final String content = backup.type == BackupType.keyOnly
        ? '這將還原您的加密金鑰，並從伺服器同步歷史訊息。'
        : '這將把備份中的對話合併進目前的資料，不會刪除現有對話。';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          content,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('還原', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (backup.type == BackupType.keyOnly) {
        // 僅金鑰還原流程
        await _handleKeyOnlyRestore(backup);
      } else {
        // 完整備份還原流程
        await _handleFullRestore(backup);
      }
    }
  }

  /// 處理僅金鑰還原
  Future<void> _handleKeyOnlyRestore(BackupFileInfo backup) async {
    // 顯示密碼輸入對話框
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _RestorePasswordDialog(),
    );

    if (password == null || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已取消還原'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // 呼叫 restoreKeyOnly
    final success = await ref
        .read(backupManagerProvider.notifier)
        .restoreKeyOnly(fileId: backup.id, backupPassword: password);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('私鑰還原成功！正在從伺服器同步訊息...'),
            backgroundColor: Colors.green,
          ),
        );
        // TODO: 觸發從後端同步加密歷史訊息
      } else {
        final error = ref.read(backupManagerProvider).error ?? '還原金鑰失敗';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 處理完整備份還原
  Future<void> _handleFullRestore(BackupFileInfo backup) async {
    final result = await ref
        .read(backupManagerProvider.notifier)
        .restoreBackup(backup.id);
    if (mounted) {
      if (result != null) {
        if (result.encryptedPrivateKey != null &&
            result.privateKeySalt != null) {
          final password = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (context) => const _RestorePasswordDialog(),
          );

          if (password != null && password.isNotEmpty) {
            try {
              final cryptoService = ref.read(cryptoServiceProvider);
              final rawKey = await cryptoService.decryptPrivateKeyFromBackup(
                result.encryptedPrivateKey!,
                result.privateKeySalt!,
                password,
              );
              await cryptoService.restorePrivateKey(rawKey);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ 金鑰還原成功，訊息現在可以正常解密'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ 密碼錯誤，請重試'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('⚠️ 已跳過金鑰還原，舊訊息可能無法解密'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '還原成功！共匯入 ${result.importedCount} 則對話，跳過 ${result.skippedCount} 則重複對話。',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final error = ref.read(backupManagerProvider).error ?? '還原失敗';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(backupManagerProvider);

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: const Text('備份記錄'),
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchHistory,
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _fetchHistory, child: _buildBody()),
    );

    return Stack(
      children: [
        scaffold,
        if (state.isBackingUp)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.blueAccent),
                  SizedBox(height: 16),
                  Text(
                    '還原中...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchHistory, child: const Text('重試')),
          ],
        ),
      );
    }

    if (_backups.isEmpty) {
      return const Center(
        child: Text(
          '目前沒有任何備份記錄',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _backups.length,
      itemBuilder: (context, index) {
        final backup = _backups[index];
        final String date = _formatDate(
          backup.createdTime?.toIso8601String() ?? '',
        );
        final String size = backup.displaySize;
        final String typeLabel = backup.displayName;

        return Dismissible(
          key: Key(backup.id),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1C1C1E),
                title: const Text(
                  '刪除備份？',
                  style: TextStyle(color: Colors.white),
                ),
                content: const Text(
                  '您確定要刪除這筆備份嗎？此操作無法還原。',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      '取消',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      '刪除',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            );
          },
          onDismissed: (direction) async {
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            // 1. Optimistically remove from UI to satisfy Dismissible's synchronous requirement
            setState(() {
              _backups.removeAt(index);
            });

            // 2. Perform the async deletion
            final success = await ref
                .read(backupManagerProvider.notifier)
                .deleteBackup(backup.id);

            if (mounted) {
              if (success) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('備份已刪除'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                // 3. If failed, restore the item and show error
                setState(() {
                  _backups.insert(index, backup);
                });
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('刪除失敗'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(
                backup.type == BackupType.keyOnly
                    ? Icons.vpn_key
                    : Icons.history,
                color: backup.type == BackupType.keyOnly
                    ? Colors.amber
                    : Colors.blueAccent,
              ),
              title: Text(
                typeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                '$date • $size',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => _showRestoreConfirmation(backup),
            ),
          ),
        );
      },
    );
  }
}

class _RestorePasswordDialog extends StatefulWidget {
  const _RestorePasswordDialog();

  @override
  State<_RestorePasswordDialog> createState() => _RestorePasswordDialogState();
}

class _RestorePasswordDialogState extends State<_RestorePasswordDialog> {
  final _pwdController = TextEditingController();
  bool _obscurePwd = true;

  void _submit() {
    final pwd = _pwdController.text;
    if (pwd.isEmpty) return;
    Navigator.of(context).pop(pwd);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      title: const Text('此備份包含 E2EE 金鑰', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '輸入備份時設定的密碼來還原您的加密金鑰，這樣才能正常讀取訊息。',
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
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePwd ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white54,
                  ),
                  onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(null), // return null for skip
          child: const Text('略過', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('還原金鑰', style: TextStyle(color: Colors.blueAccent)),
        ),
      ],
    );
  }
}
