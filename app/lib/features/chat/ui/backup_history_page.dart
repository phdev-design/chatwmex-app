import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:app/core/backup/backup_manager.dart';

class BackupHistoryPage extends ConsumerStatefulWidget {
  const BackupHistoryPage({super.key});

  @override
  ConsumerState<BackupHistoryPage> createState() => _BackupHistoryPageState();
}

class _BackupHistoryPageState extends ConsumerState<BackupHistoryPage> {
  bool _isLoading = true;
  List<dynamic> _backups = [];
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
      final records = await ref
          .read(backupManagerProvider.notifier)
          .fetchBackupHistory();
      if (mounted) {
        setState(() {
          _backups = records;
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

  String _formatSize(String byteSize) {
    try {
      final bytes = int.parse(byteSize);
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } catch (_) {
      return '';
    }
  }

  Future<void> _showRestoreConfirmation(String fileId, String date) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('還原此備份？', style: TextStyle(color: Colors.white)),
        content: const Text(
          '這將把備份中的對話合併進目前的資料，不會刪除現有對話。',
          style: TextStyle(color: Colors.white70),
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
      final result = await ref
          .read(backupManagerProvider.notifier)
          .restoreBackup(fileId);
      if (mounted) {
        if (result != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '還原成功！共匯入 ${result.importedCount} 則對話，跳過 ${result.skippedCount} 則重複對話。',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          final error = ref.read(backupManagerProvider).error ?? '還原失敗';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red),
          );
        }
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
            color: Colors.black87,
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
        final backup = _backups[index] as Map<String, dynamic>;
        final String name = backup['name'] ?? '未知檔案';
        final String date = _formatDate(backup['date'] ?? '');
        final String size = _formatSize(backup['size'] ?? '');

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: const Icon(Icons.history, color: Colors.blueAccent),
            title: Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              '$date • $size',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              if (backup['id'] != null) {
                _showRestoreConfirmation(backup['id'] as String, date);
              }
            },
          ),
        );
      },
    );
  }
}
