import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:app/core/backup/google_drive_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/models/message.dart';
import 'package:app/models/backup_mode.dart';
import 'package:app/models/backup_frequency.dart';
import 'package:app/models/key_backup_file.dart';

class RestoreResult {
  final int importedCount;
  final int skippedCount;
  final String? encryptedPrivateKey;
  final String? privateKeySalt;

  RestoreResult({
    required this.importedCount,
    required this.skippedCount,
    this.encryptedPrivateKey,
    this.privateKeySalt,
  });
}

class BackupState {
  final bool isBackingUp;
  final String? lastBackupDate;
  final bool autoBackupEnabled;
  final String? autoBackupTime;
  final BackupFrequency autoBackupFrequency;
  final String? error;
  final String? linkedGoogleEmail;
  final BackupMode backupMode;

  BackupState({
    this.isBackingUp = false,
    this.lastBackupDate,
    this.autoBackupEnabled = false,
    this.autoBackupTime,
    this.autoBackupFrequency = BackupFrequency.daily,
    this.error,
    this.linkedGoogleEmail,
    this.backupMode = BackupMode.full,
  });

  BackupState copyWith({
    bool? isBackingUp,
    String? lastBackupDate,
    bool? autoBackupEnabled,
    String? autoBackupTime,
    BackupFrequency? autoBackupFrequency,
    String? error,
    bool clearError = false,
    String? linkedGoogleEmail,
    BackupMode? backupMode,
  }) {
    return BackupState(
      isBackingUp: isBackingUp ?? this.isBackingUp,
      lastBackupDate: lastBackupDate ?? this.lastBackupDate,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      autoBackupTime: autoBackupTime ?? this.autoBackupTime,
      autoBackupFrequency: autoBackupFrequency ?? this.autoBackupFrequency,
      error: clearError ? null : (error ?? this.error),
      linkedGoogleEmail: linkedGoogleEmail ?? this.linkedGoogleEmail,
      backupMode: backupMode ?? this.backupMode,
    );
  }
}

class BackupManager extends StateNotifier<BackupState>
    with WidgetsBindingObserver {
  final GoogleDriveService _googleDriveService;
  final LocalDbService _localDbService;
  final CryptoService _cryptoService;
  final StorageService _storageService;

  BackupManager(
    this._googleDriveService,
    this._localDbService,
    this._cryptoService,
    this._storageService,
  ) : super(BackupState()) {
    _loadSettings();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _isAuthenticating = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAutoBackup();
    }
  }

  /// Validates time string matches "HH:mm" where HH is 00-23 and mm is 00-59.
  bool _validateTimeFormat(String time) {
    final regex = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
    return regex.hasMatch(time);
  }

  /// Determines if a backup has already occurred within the current frequency period.
  /// Compares lastBackupDate with current date based on the configured frequency.
  bool _hasBackupHappenedInCurrentPeriod() {
    if (state.lastBackupDate == null) return false;

    try {
      final lastBackup = DateTime.parse(state.lastBackupDate!).toLocal();
      final now = DateTime.now();

      switch (state.autoBackupFrequency) {
        case BackupFrequency.daily:
          return lastBackup.year == now.year &&
                 lastBackup.month == now.month &&
                 lastBackup.day == now.day;
        case BackupFrequency.weekly:
          // 計算本週一 00:00
          final weekStart = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          return lastBackup.isAfter(weekStart) || lastBackup.isAtSameMomentAs(weekStart);
        case BackupFrequency.monthly:
          return lastBackup.year == now.year && lastBackup.month == now.month;
      }
    } catch (e) {
      debugPrint('[BackupManager] Error parsing lastBackupDate: $e');
      return false;
    }
  }

  /// Checks if the current time has passed the configured scheduled time.
  /// Returns false if autoBackupTime is invalid or not set.
  bool _isScheduledTimePassed() {
    if (state.autoBackupTime == null) return false;

    try {
      final parts = state.autoBackupTime!.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      final now = DateTime.now();
      final scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);

      return now.isAfter(scheduledTime);
    } catch (e) {
      debugPrint('[BackupManager] Error parsing autoBackupTime: $e');
      return false; // Treat parse errors conservatively
    }
  }

  /// Checks if an automatic backup should be triggered.
  /// 
  /// Behavior depends on autoBackupTime configuration:
  /// - If null: Uses 24-hour interval logic (backward compatible)
  /// - If set: Uses scheduled time logic with daily reset
  /// 
  /// LIMITATION: This method only runs when app resumes to foreground.
  /// For true background execution, integrate with workmanager or similar.
  /// Background execution requires:
  /// - Platform permissions (Android: SCHEDULE_EXACT_ALARM, iOS: background modes)
  /// - Headless authentication handling
  /// - Battery optimization exemptions
  Future<void> _checkAutoBackup() async {
    if (_isAuthenticating) return;
    if (!state.autoBackupEnabled) return;

    // Backward compatibility: interval-based when no scheduled time
    if (state.autoBackupTime == null) {
      if (state.lastBackupDate != null) {
        try {
          final last = DateTime.parse(state.lastBackupDate!);
          final hours = switch (state.autoBackupFrequency) {
            BackupFrequency.daily => 24,
            BackupFrequency.weekly => 24 * 7,
            BackupFrequency.monthly => 24 * 30,
          };
          if (DateTime.now().difference(last).inHours < hours) {
            return; // backup was too recent
          }
        } catch (e) {
          debugPrint('[BackupManager] Error parsing lastBackupDate: $e');
        }
      }

      if (await signInSilently()) {
        backupNow();
      }
      return;
    }

    // Scheduled time logic
    if (_hasBackupHappenedInCurrentPeriod()) {
      return; // Already backed up in this period
    }

    if (!_isScheduledTimePassed()) {
      return; // Scheduled time hasn't arrived yet
    }

    // Execute backup (foreground wake-up compensation)
    if (await signInSilently()) {
      backupNow();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackup = prefs.getString('lastBackupDate');
    final autoBackup = prefs.getBool('autoBackupEnabled') ?? false;
    final autoBackupTime = prefs.getString('autoBackupTime');

    // Load backup frequency
    final freqStr = prefs.getString('autoBackupFrequency');
    final autoBackupFrequency = freqStr != null
        ? BackupFrequency.fromString(freqStr)
        : BackupFrequency.daily;

    // Load backup mode from SharedPreferences
    final backupModeStr = prefs.getString('backupMode');
    final backupMode = backupModeStr != null 
        ? BackupMode.fromString(backupModeStr) 
        : BackupMode.full;

    // Load linked email based on current app user
    final userId = await _storageService.read('user_id');
    String? linkedEmail;
    if (userId != null && userId.isNotEmpty) {
      linkedEmail = prefs.getString('drive_linked_email_$userId');
    }

    state = state.copyWith(
      lastBackupDate: lastBackup,
      autoBackupEnabled: autoBackup,
      autoBackupTime: autoBackupTime,
      autoBackupFrequency: autoBackupFrequency,
      linkedGoogleEmail: linkedEmail,
      backupMode: backupMode,
    );
  }

  Future<bool> _verifyAndLinkGoogleAccount() async {
    final currentUserEmail = _googleDriveService.currentUser?.email;
    if (currentUserEmail == null) return false;

    final userId = await _storageService.read('user_id');
    if (userId == null || userId.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();

    if (state.linkedGoogleEmail == null) {
      // 本地尚未綁定，將此次的 Google Email 綁定給當前的 user_id
      await prefs.setString('drive_linked_email_$userId', currentUserEmail);
      state = state.copyWith(linkedGoogleEmail: currentUserEmail);
      return true;
    } else {
      // 本地已經綁定過，比對是否一致
      if (state.linkedGoogleEmail != currentUserEmail) {
        // 不一致，拒絕登入並強迫切斷
        await _googleDriveService.disconnect();
        state = state.copyWith(
          error: '請選擇您原本綁定的 Google 帳號：${state.linkedGoogleEmail}',
          clearError: false,
        );
        return false;
      }
      return true;
    }
  }

  Future<void> _syncLatestBackupDateFromDrive() async {
    try {
      final history = await fetchBackupHistory();
      if (history.isNotEmpty) {
        final latestBackup = history.first as Map<String, dynamic>;
        final date = latestBackup['date'] as String?;
        if (date != null && date.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('lastBackupDate', date);
          state = state.copyWith(lastBackupDate: date);
        }
      }
    } catch (e) {
      debugPrint('[BackupManager] sync latest backup date error: $e');
    }
  }

  Future<bool> signIn() async {
    if (_isAuthenticating) return false;
    _isAuthenticating = true;
    debugPrint('[BackupManager] signIn called');
    try {
      final result = await _googleDriveService.signIn();
      debugPrint('[BackupManager] signIn result: $result');

      if (result) {
        final isValid = await _verifyAndLinkGoogleAccount();
        if (!isValid) return false;

        await _syncLatestBackupDateFromDrive();
      }
      return result;
    } finally {
      _isAuthenticating = false;
    }
  }

  Future<bool> signInSilently() async {
    final result = await _googleDriveService.signInSilently();
    if (result) {
      final isValid = await _verifyAndLinkGoogleAccount();
      if (!isValid) return false;

      await _syncLatestBackupDateFromDrive();
    }
    return result;
  }

  Future<void> clearSession() async {
    await _googleDriveService.signOut();
    state = BackupState();
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
  Future<String> exportAllConversationsToJSON({String? backupPassword}) async {
    final messages = await _localDbService.getAllMessages();
    Map<String, String>? keyBackupData;

    try {
      if (backupPassword != null && backupPassword.isNotEmpty) {
        final rawKey = await _cryptoService.getRawPrivateKey();
        if (rawKey != null) {
          keyBackupData = await _cryptoService.encryptPrivateKeyForBackup(
            rawKey,
            backupPassword,
          );
        }
      }
    } catch (e) {
      debugPrint('[BackupManager] Error encrypting private key backup: $e');
      // Continue anyway, worst case we backup without the key
    }

    final payload = {
      'backup_date': DateTime.now().toIso8601String(),
      'app_version': "1.0.0", // Hardcoded app version for now
      'e2ee_key_backup': ?keyBackupData,
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

      String? encryptedPrivateKey;
      String? privateKeySalt;
      if (decoded.containsKey('e2ee_key_backup')) {
        final keyBackup = decoded['e2ee_key_backup'] as Map<String, dynamic>;
        encryptedPrivateKey = keyBackup['encrypted_private_key']?.toString();
        privateKeySalt = keyBackup['salt']?.toString();
      }

      if (toInsert.isNotEmpty) {
        // Here we just insert missing messages without deleting existing ones
        final updatedList = [...currentMessages, ...toInsert];
        await _localDbService.restoreMessages(updatedList);
      }

      return RestoreResult(
        importedCount: toInsert.length,
        skippedCount: skippedCount,
        encryptedPrivateKey: encryptedPrivateKey,
        privateKeySalt: privateKeySalt,
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

  /// 設定自動備份頻率
  Future<void> setAutoBackupFrequency(BackupFrequency frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('autoBackupFrequency', frequency.name);
    state = state.copyWith(autoBackupFrequency: frequency);
  }

  /// Sets the scheduled backup time in "HH:mm" format (24-hour).
  /// Pass null to disable scheduled backups and revert to 24-hour interval.
  /// 
  /// Validates format and persists to SharedPreferences.
  /// Sets error state if validation fails.
  Future<void> setAutoBackupTime(String? time) async {
    // Validation
    if (time != null && !_validateTimeFormat(time)) {
      state = state.copyWith(
        error: 'Invalid time format. Use HH:mm (00:00 to 23:59)',
        clearError: false,
      );
      return;
    }

    // Persist
    final prefs = await SharedPreferences.getInstance();
    if (time == null) {
      await prefs.remove('autoBackupTime');
    } else {
      await prefs.setString('autoBackupTime', time);
    }

    // Update state
    state = state.copyWith(autoBackupTime: time, clearError: true);
  }

  /// 設定備份模式
  ///
  /// 將備份模式持久化至 SharedPreferences 並更新狀態。
  ///
  /// [mode] 要設定的備份模式（full, keyOnly, 或 none）
  Future<void> setBackupMode(BackupMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backupMode', mode.name);
    state = state.copyWith(backupMode: mode);
  }

  /// 執行僅金鑰備份
  ///
  /// 從 CryptoService 取得原始私鑰，使用 backupPassword 加密後上傳至 Google Drive。
  /// 備份檔案名稱為 chatwmex_key_backup.json，包含加密後的私鑰、salt、演算法資訊等。
  ///
  /// [backupPassword] 用於加密私鑰的密碼（必填）
  ///
  /// 錯誤處理：
  /// - 無私鑰：顯示「無法取得私鑰」錯誤
  /// - 上傳失敗：顯示「上傳至 Google Drive 失敗」錯誤
  /// - 其他錯誤：顯示具體錯誤訊息
  Future<void> backupKeyOnly({required String backupPassword}) async {
    state = state.copyWith(isBackingUp: true, clearError: true);

    try {
      // 1. 取得原始私鑰
      final rawPrivateKey = await _cryptoService.getRawPrivateKey();
      if (rawPrivateKey == null) {
        throw Exception('無法取得私鑰');
      }

      // 2. 使用密碼加密私鑰
      final encryptedData = await _cryptoService.encryptPrivateKeyForBackup(
        rawPrivateKey,
        backupPassword,
      );

      // 3. 建立金鑰備份檔案 JSON 結構
      final keyBackupFile = {
        'version': '1.0',
        'encryptedKey': encryptedData['encryptedKeyBase64'],
        'salt': encryptedData['saltBase64'],
        'iv': '', // AES-GCM 的 nonce 已包含在 encryptedKey 中
        'algorithm': 'AES-GCM-256',
        'timestamp': DateTime.now().toIso8601String(),
      };

      // 4. 上傳至 Google Drive
      final jsonString = jsonEncode(keyBackupFile);
      final fileName = 'chatwmex_key_backup.json';
      
      final success = await _googleDriveService.uploadBackup(
        jsonString,
        fileName,
      );

      if (success) {
        // 5. 更新 lastBackupDate 與 BackupState
        final prefs = await SharedPreferences.getInstance();
        final nowStr = DateTime.now().toIso8601String();
        await prefs.setString('lastBackupDate', nowStr);
        state = state.copyWith(isBackingUp: false, lastBackupDate: nowStr);
      } else {
        throw Exception('上傳至 Google Drive 失敗');
      }
    } catch (e) {
      // 6. 處理錯誤情境
      state = state.copyWith(
        isBackingUp: false,
        error: '僅金鑰備份失敗：$e',
        clearError: false,
      );
    }
  }

  /// 還原僅金鑰備份
  ///
  /// 從 Google Drive 下載金鑰備份檔案，解析 JSON 並驗證版本相容性，
  /// 使用 backupPassword 解密私鑰，然後還原私鑰至 FlutterSecureStorage。
  ///
  /// [fileId] Google Drive 檔案 ID
  /// [backupPassword] 用於解密私鑰的密碼（必填）
  ///
  /// 回傳 true 表示還原成功，false 表示還原失敗
  ///
  /// 錯誤處理：
  /// - 下載失敗：顯示「下載備份檔失敗」錯誤
  /// - 版本不相容：顯示「備份檔案版本不相容」錯誤
  /// - 密碼錯誤：顯示「恢復密碼錯誤，請重新輸入」錯誤
  /// - 檔案損壞：顯示「備份檔案損壞，無法還原」錯誤
  Future<bool> restoreKeyOnly({
    required String fileId,
    required String backupPassword,
  }) async {
    state = state.copyWith(isBackingUp: true, clearError: true);

    try {
      // 1. 從 Google Drive 下載金鑰備份檔案
      final jsonString = await _googleDriveService.downloadBackup(fileId);
      if (jsonString == null || jsonString.isEmpty) {
        throw Exception('下載備份檔失敗');
      }

      // 2. 解析 JSON
      final Map<String, dynamic> jsonData;
      try {
        jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('備份檔案損壞，無法還原');
      }

      // 3. 使用 KeyBackupFile 模型解析並驗證
      final KeyBackupFile keyBackupFile;
      try {
        keyBackupFile = KeyBackupFile.fromJson(jsonData);
      } catch (e) {
        throw Exception('備份檔案損壞，無法還原');
      }

      // 4. 驗證檔案格式
      if (!keyBackupFile.isValid()) {
        throw Exception('備份檔案損壞，無法還原');
      }

      // 5. 驗證版本相容性
      if (keyBackupFile.version != '1.0') {
        throw Exception('備份檔案版本不相容');
      }

      // 6. 解密私鑰
      final String rawPrivateKey;
      try {
        rawPrivateKey = await _cryptoService.decryptPrivateKeyFromBackup(
          keyBackupFile.encryptedKey,
          keyBackupFile.salt,
          backupPassword,
        );
      } catch (e) {
        if (e.toString().contains('Passphrase incorrect')) {
          throw Exception('恢復密碼錯誤，請重新輸入');
        } else {
          throw Exception('解密失敗：資料可能已損壞');
        }
      }

      // 7. 還原私鑰至 FlutterSecureStorage
      await _cryptoService.restorePrivateKey(rawPrivateKey);

      state = state.copyWith(isBackingUp: false);
      return true;
    } catch (e) {
      // 8. 處理錯誤情境
      state = state.copyWith(
        isBackingUp: false,
        error: '還原金鑰失敗：$e',
        clearError: false,
      );
      return false;
    }
  }

  Future<bool> deleteBackup(String fileId) async {
    state = state.copyWith(isBackingUp: true, clearError: true);
    try {
      final success = await _googleDriveService.deleteBackup(fileId);
      state = state.copyWith(isBackingUp: false);
      return success;
    } catch (e) {
      state = state.copyWith(
        isBackingUp: false,
        error: '刪除備份失敗：$e',
        clearError: false,
      );
      return false;
    }
  }

  /// 根據備份模式執行對應的備份操作
  ///
  /// 根據 state.backupMode 決定執行哪種備份：
  /// - BackupMode.full: 執行完整備份（對話紀錄 + 媒體 + 私鑰）
  /// - BackupMode.keyOnly: 執行僅金鑰備份（需要 backupPassword）
  /// - BackupMode.none: 不執行任何備份操作
  ///
  /// [backupPassword] 備份密碼（keyOnly 模式必填，full 模式可選）
  ///
  /// 錯誤處理：
  /// - keyOnly 模式缺少密碼：顯示「僅金鑰備份需要設定密碼」錯誤
  Future<void> backupNow({String? backupPassword}) async {
    // 根據備份模式決定執行哪種備份
    switch (state.backupMode) {
      case BackupMode.full:
        // 執行完整備份邏輯
        await _backupFull(backupPassword: backupPassword);
        break;
      
      case BackupMode.keyOnly:
        // 驗證密碼存在
        if (backupPassword == null || backupPassword.isEmpty) {
          state = state.copyWith(
            error: '僅金鑰備份需要設定密碼',
            clearError: false,
          );
          return;
        }
        // 執行僅金鑰備份
        await backupKeyOnly(backupPassword: backupPassword);
        break;
      
      case BackupMode.none:
        // 不執行任何備份操作
        break;
    }
  }

  /// 執行完整備份（內部方法）
  ///
  /// 備份所有對話紀錄、媒體檔案與加密金鑰至 Google Drive。
  ///
  /// [backupPassword] 可選的備份密碼，用於加密私鑰
  Future<void> _backupFull({String? backupPassword}) async {
    state = state.copyWith(isBackingUp: true, clearError: true);

    try {
      // 1. Export JSON using the new helper
      final jsonString = await exportAllConversationsToJSON(
        backupPassword: backupPassword,
      );

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

  /// 匯出備份檔案至本機（透過系統分享面板）
  ///
  /// 產生 JSON 備份檔案後，使用 share_plus 開啟系統分享面板，
  /// 讓使用者自行選擇儲存位置或分享方式。
  ///
  /// [backupPassword] 可選的備份密碼，用於加密私鑰
  ///
  /// 回傳 true 表示檔案已成功產生並開啟分享面板
  Future<bool> exportToFile({String? backupPassword}) async {
    state = state.copyWith(isBackingUp: true, clearError: true);

    try {
      final jsonString = await exportAllConversationsToJSON(
        backupPassword: backupPassword,
      );

      // 寫入暫存檔案
      final tempDir = await getTemporaryDirectory();
      final formatter = DateFormat('yyyy-MM-dd_HH-mm-ss');
      final fileName = 'backup_${formatter.format(DateTime.now())}.json';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(jsonString);

      // 透過系統分享面板匯出
      await Share.shareXFiles([XFile(file.path)]);

      state = state.copyWith(isBackingUp: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isBackingUp: false,
        error: '匯出檔案失敗：$e',
        clearError: false,
      );
      return false;
    }
  }
}

final backupManagerProvider = StateNotifierProvider<BackupManager, BackupState>(
  (ref) {
    final driveService = ref.watch(googleDriveServiceProvider);
    final cryptoService = ref.watch(cryptoServiceProvider);
    final storageService = ref.watch(storageServiceProvider);
    final localDb = LocalDbService();
    return BackupManager(driveService, localDb, cryptoService, storageService);
  },
);
