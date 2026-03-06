import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:app/core/backup/google_drive_service.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/models/message.dart';

class RestoreResult {
  final int importedCount;
  final int skippedCount;

  RestoreResult({required this.importedCount, required this.skippedCount});
}

class BackupState {
  final bool isBackingUp;
  final String? lastBackupDate;
  final bool autoBackupEnabled;
  final String? error;

  BackupState({
    this.isBackingUp = false,
    this.lastBackupDate,
    this.autoBackupEnabled = false,
    this.error,
  });

  BackupState copyWith({
    bool? isBackingUp,
    String? lastBackupDate,
    bool? autoBackupEnabled,
    String? error,
    bool clearError = false,
  }) {
    return BackupState(
      isBackingUp: isBackingUp ?? this.isBackingUp,
      lastBackupDate: lastBackupDate ?? this.lastBackupDate,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class BackupManager extends StateNotifier<BackupState>
    with WidgetsBindingObserver {
  final GoogleDriveService _googleDriveService;
  final LocalDbService _localDbService;

  BackupManager(this._googleDriveService, this._localDbService)
    : super(BackupState()) {
    _loadSettings();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAutoBackup();
    }
  }

  Future<void> _checkAutoBackup() async {
    if (!state.autoBackupEnabled) return;

    // Auto backup once a day
    if (state.lastBackupDate != null) {
      try {
        final last = DateTime.parse(state.lastBackupDate!);
        if (DateTime.now().difference(last).inHours < 24) {
          return; // backup was too recent
        }
      } catch (_) {}
    }

    if (await signInSilently()) {
      backupNow();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackup = prefs.getString('lastBackupDate');
    final autoBackup = prefs.getBool('autoBackupEnabled') ?? false;
    state = state.copyWith(
      lastBackupDate: lastBackup,
      autoBackupEnabled: autoBackup,
    );
  }

  Future<bool> signIn() async {
    final account = await _googleDriveService.signIn();
    return account != null;
  }

  Future<bool> signInSilently() async {
    final account = await _googleDriveService.signInSilently();
    return account != null;
  }

  Future<List<dynamic>> fetchBackupHistory() async {
    final files = await _googleDriveService.listBackups();
    return files
        .map(
          (f) => {
            'id': f.id,
            'name': f.name,
            'date': f.createdTime?.toIso8601String() ?? '',
            'size': f.size ?? '0',
          },
        )
        .toList();
  }

  /// Exports all local SQLite messages (conversations) to a JSON string
  /// mirroring the requested structure.
  Future<String> exportAllConversationsToJSON() async {
    final messages = await _localDbService.getAllMessages();
    final payload = {
      'backup_date': DateTime.now().toIso8601String(),
      'app_version': "1.0.0", // Hardcoded app version for now
      'conversations': messages.map((m) => m.toMap()).toList(),
    };
    return jsonEncode(payload);
  }

  /// Imports messages from a JSON string, filtering duplicates by ID.
  Future<RestoreResult?> importFromJSON(String jsonString) async {
    try {
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      final remoteList = decoded['conversations'] as List<dynamic>?;
      if (remoteList == null) return null;

      final currentMessages = await _localDbService.getAllMessages();
      final existingIds = currentMessages.map((m) => m.id).toSet();

      final toInsert = <Message>[];
      int skippedCount = 0;

      for (final item in remoteList) {
        final message = Message.fromMap(item as Map<String, dynamic>);
        if (!existingIds.contains(message.id)) {
          toInsert.add(message);
        } else {
          skippedCount++;
        }
      }

      if (toInsert.isNotEmpty) {
        // Here we just insert missing messages without deleting existing ones
        final updatedList = [...currentMessages, ...toInsert];
        await _localDbService.restoreMessages(updatedList);
      }

      return RestoreResult(
        importedCount: toInsert.length,
        skippedCount: skippedCount,
      );
    } catch (e) {
      state = state.copyWith(error: '還原 JSON 錯誤：$e', clearError: false);
      return null;
    }
  }

  Future<RestoreResult?> restoreBackup(String fileId) async {
    state = state.copyWith(isBackingUp: true, clearError: true);
    try {
      final jsonString = await _googleDriveService.downloadBackup(fileId);
      if (jsonString == null || jsonString.isEmpty) {
        state = state.copyWith(
          isBackingUp: false,
          error: '下載備份檔失敗。',
          clearError: false,
        );
        return null;
      }

      final result = await importFromJSON(jsonString);
      state = state.copyWith(isBackingUp: false);
      return result;
    } catch (e) {
      state = state.copyWith(
        isBackingUp: false,
        error: '下載或還原發生錯誤：$e',
        clearError: false,
      );
      return null;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> setAutoBackup(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoBackupEnabled', enabled);
    state = state.copyWith(autoBackupEnabled: enabled);
  }

  Future<void> backupNow() async {
    state = state.copyWith(isBackingUp: true, clearError: true);

    try {
      // 1. Export JSON using the new helper
      final jsonString = await exportAllConversationsToJSON();

      // 2. Upload
      final formatter = DateFormat('yyyy-MM-dd_HH-mm-ss');
      final fileName = 'backup_${formatter.format(DateTime.now())}.json';

      final success = await _googleDriveService.uploadBackup(
        jsonString,
        fileName,
      );

      if (success) {
        final prefs = await SharedPreferences.getInstance();
        final nowStr = DateTime.now().toIso8601String();
        await prefs.setString('lastBackupDate', nowStr);
        state = state.copyWith(isBackingUp: false, lastBackupDate: nowStr);
      } else {
        state = state.copyWith(
          isBackingUp: false,
          error: 'Google Drive 上傳失敗，請確認登入狀態及網路。',
          clearError: false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isBackingUp: false,
        error: '備份發生未知錯誤：$e',
        clearError: false,
      );
    }
  }
}

final backupManagerProvider = StateNotifierProvider<BackupManager, BackupState>(
  (ref) {
    final driveService = ref.watch(googleDriveServiceProvider);
    final localDb = LocalDbService();
    return BackupManager(driveService, localDb);
  },
);
