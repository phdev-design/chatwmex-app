import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:app/models/message.dart';

class LocalDbService {
  LocalDbService._internal();

  static final LocalDbService _instance = LocalDbService._internal();

  factory LocalDbService() => _instance;

  Database? _db;
  String? _dbPath;
  final List<Map<String, Object?>> _dbEventLog = [];
  String? _logPath;

  Future<Database> initDB({String? overridePath}) async {
    if (_db != null) {
      return _db!;
    }

    final dbPath = await _resolveDbPath(overridePath);
    _db = await _openDatabase(dbPath);
    return _db!;
  }

  Future<Database> _openDatabase(String dbPath) async {
    return openDatabase(
      dbPath,
      version: 6, // 👉 Bump to 6 for is_decrypted column
      onCreate: (db, version) async {
        await _createMessagesTable(db);
        await _createPublicKeysTable(db); // 👉 Add this
        await _logDbEvent('db_create', {'version': version});
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 5) {
          await _createPublicKeysTable(db); // 👉 Add this
        }
        if (oldVersion < 6) {
          await _ensureMessagesColumns(db);
        }
        await _logDbEvent('db_upgrade', {'from': oldVersion, 'to': newVersion});
      },
      onOpen: (db) async {
        await _createPublicKeysTable(db); // 👉 Ensure table exists just in case
        final version = await db.rawQuery('PRAGMA user_version');
        await _logDbEvent('db_open', {'version': version});
      },
    );
  }

  Future<String> _resolveDbPath(String? overridePath) async {
    if (overridePath != null && overridePath.isNotEmpty) {
      _dbPath = overridePath;
      return overridePath;
    }
    final directory = await getApplicationDocumentsDirectory();
    _dbPath = join(directory.path, 'chat_cache.db');
    return _dbPath!;
  }

  Future<void> _createMessagesTable(Database db) async {
    await db.execute(
      'CREATE TABLE messages('
      'id TEXT PRIMARY KEY, '
      'client_msg_id TEXT, '
      'room_id TEXT, '
      'sender_id TEXT, '
      'receiver_id TEXT, '
      'reply_to_message_id TEXT, '
      'reactions TEXT, '
      'is_unsent INTEGER DEFAULT 0, '
      'content TEXT, '
      'type TEXT, '
      'created_at INTEGER, '
      'is_read INTEGER, '
      'read_at INTEGER, '
      'read_by TEXT, '
      'status TEXT DEFAULT "sent", ' // 訊息狀態：pending/sent/delivered/read/failed
      'link_preview TEXT, ' // 連結預覽
      'file_key TEXT, ' // 加密檔案金鑰（用於音訊/圖片/影片）
      'decrypt_retry_count INTEGER DEFAULT 0, ' // 🔐 E2EE 解密重試計數器
      'is_decrypted INTEGER DEFAULT 0' // 🔐 解密狀態追蹤（獨立於 is_read）
      ')',
    );
  }

  Future<void> _createPublicKeysTable(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS public_keys('
      'user_id TEXT PRIMARY KEY, '
      'public_key TEXT, '
      'updated_at INTEGER'
      ')',
    );
  }

  Future<void> _ensureMessagesColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    if (columns.isEmpty) {
      await _createMessagesTable(db);
      await _logDbEvent('db_repair', {'action': 'create_messages_table'});
      return;
    }
    
    // Fix 1: Correctly extract column names from PRAGMA table_info
    final existing = columns
        .map((row) => row['name'] as String)
        .toSet();
    await _logDbEvent('db_check', {'columns': existing.toList()});
    
    final missing = <String, String>{
      'client_msg_id': 'ALTER TABLE messages ADD COLUMN client_msg_id TEXT',
      'reply_to_message_id':
          'ALTER TABLE messages ADD COLUMN reply_to_message_id TEXT',
      'reactions': 'ALTER TABLE messages ADD COLUMN reactions TEXT',
      'is_unsent':
          'ALTER TABLE messages ADD COLUMN is_unsent INTEGER DEFAULT 0',
      'is_read': 'ALTER TABLE messages ADD COLUMN is_read INTEGER',
      'read_at': 'ALTER TABLE messages ADD COLUMN read_at INTEGER',
      'read_by': 'ALTER TABLE messages ADD COLUMN read_by TEXT',
      'link_preview': 'ALTER TABLE messages ADD COLUMN link_preview TEXT',
      // 新増：status 欄位，預設為 sent
      'status': 'ALTER TABLE messages ADD COLUMN status TEXT DEFAULT "sent"',
      // 新増：file_key 欄位，用於加密音訊/圖片/影片
      'file_key': 'ALTER TABLE messages ADD COLUMN file_key TEXT',
      // 🔐 新增：decrypt_retry_count 欄位，用於 E2EE 解密重試計數
      'decrypt_retry_count': 'ALTER TABLE messages ADD COLUMN decrypt_retry_count INTEGER DEFAULT 0',
      // 🔐 新增：is_decrypted 欄位，用於追蹤解密狀態（獨立於 is_read）
      'is_decrypted': 'ALTER TABLE messages ADD COLUMN is_decrypted INTEGER DEFAULT 0',
    };
    
    for (final entry in missing.entries) {
      if (!existing.contains(entry.key)) {
        try {
          await db.execute(entry.value);
          await _logDbEvent('db_repair', {'add_column': entry.key});
        } catch (e) {
          // Fix 2: Handle duplicate column error gracefully
          if (e.toString().contains('duplicate column')) {
            await _logDbEvent('db_repair', {
              'add_column': entry.key,
              'status': 'already_exists',
            });
            continue;
          }
          rethrow;
        }
      }
    }
  }

  Future<void> _logDbEvent(String event, Map<String, Object?> data) async {
    final payload = <String, Object?>{
      'time': DateTime.now().toIso8601String(),
      'event': event,
      'data': data,
    };
    _dbEventLog.add(payload);
    debugPrint('LocalDbService:$event $data');
    final logPath = await _resolveLogPath();
    if (_dbPath != ':memory:') {
      final file = File(logPath);
      await file.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
  }

  Future<String> _resolveLogPath() async {
    if (_logPath != null && _logPath!.isNotEmpty) {
      return _logPath!;
    }
    if (_dbPath != null && _dbPath!.isNotEmpty && _dbPath != ':memory:') {
      _logPath = join(dirname(_dbPath!), 'chat_cache.log');
      return _logPath!;
    }
    if (_dbPath == ':memory:') {
      _logPath = ':memory:';
      return _logPath!;
    }
    final directory = await getApplicationDocumentsDirectory();
    _logPath = join(directory.path, 'chat_cache.log');
    return _logPath!;
  }

  List<Map<String, Object?>> getDbEventReport() {
    return List<Map<String, Object?>>.from(_dbEventLog);
  }

  Future<String> readDbLogFile() async {
    final logPath = await _resolveLogPath();
    final file = File(logPath);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<void> insertMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    final db = await initDB();
    final batch = db.batch();
    for (final message in messages) {
      batch.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Message>> getMessagesByRoom(
    String roomId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await initDB();

    // 👉 關鍵修正：同時比對 room_id、sender_id 與 receiver_id
    // 這樣不論是群組 (room_id) 還是私訊 (sender_id/receiver_id)，都能正確撈出歷史訊息！
    final rows = await db.query(
      'messages',
      where: 'room_id = ? OR sender_id = ? OR receiver_id = ?',
      whereArgs: [roomId, roomId, roomId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Message.fromMap).toList();
  }

  Future<List<Message>> getAllMessages() async {
    final db = await initDB();
    final rows = await db.query('messages', orderBy: 'created_at ASC');
    return rows.map(Message.fromMap).toList();
  }

  Future<void> restoreMessages(List<Message> messages) async {
    final db = await initDB();
    final batch = db.batch();
    batch.delete('messages');
    for (final message in messages) {
      batch.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteMessageLocal(String messageId) async {
    if (messageId.isEmpty) return;
    final db = await initDB();
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  /// 清除特定聊天室（含私訊 sender/receiver 關聯）的所有本地訊息
  Future<void> clearRoomMessages(String roomId) async {
    if (roomId.isEmpty) return;
    final db = await initDB();
    await db.delete(
      'messages',
      where: 'room_id = ? OR sender_id = ? OR receiver_id = ?',
      whereArgs: [roomId, roomId, roomId],
    );
  }

  /// 取得所有狀態為 pending 的訊息（用於重連同步）
  Future<List<Message>> getPendingMessages() async {
    final db = await initDB();
    final rows = await db.query(
      'messages',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );
    return rows.map(Message.fromMap).toList();
  }

  /// 更新單筆訊息的狀態
  Future<void> updateMessageStatus(String id, MessageStatus status) async {
    if (id.isEmpty) return;
    final db = await initDB();
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ? OR client_msg_id = ?',
      whereArgs: [id, id],
    );
  }

  Future<void> savePublicKey(String userId, String publicKey) async {
    final db = await initDB();
    await db.insert('public_keys', {
      'user_id': userId,
      'public_key': publicKey,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getPublicKey(String userId) async {
    final db = await initDB();
    final result = await db.query(
      'public_keys',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    if (result.isNotEmpty) {
      return result.first['public_key'] as String?;
    }
    return null;
  }

  Future<void> clearAllPublicKeys() async {
    final db = await initDB();
    await db.delete('public_keys');
  }

  // 🔐 ========== E2EE Auto-Resend Support Methods ==========

  /// 根據訊息 ID 取得單筆訊息（包含原始明文內容）
  /// 用於發送方收到 re_encrypt_request 時，從本地資料庫撈取原始訊息
  Future<Message?> getMessageById(String messageId) async {
    if (messageId.isEmpty) return null;
    final db = await initDB();
    
    final rows = await db.query(
      'messages',
      where: 'id = ? OR client_msg_id = ?',
      whereArgs: [messageId, messageId],
      limit: 1,
    );
    
    if (rows.isEmpty) return null;
    return Message.fromMap(rows.first);
  }

  /// 取得訊息的解密重試計數器
  /// 用於檢查是否已達最大重試次數（最多 2 次）
  Future<int> getDecryptRetryCount(String messageId) async {
    if (messageId.isEmpty) return 0;
    final db = await initDB();
    
    final rows = await db.query(
      'messages',
      columns: ['decrypt_retry_count'],
      where: 'id = ? OR client_msg_id = ?',
      whereArgs: [messageId, messageId],
      limit: 1,
    );
    
    if (rows.isEmpty) return 0;
    return (rows.first['decrypt_retry_count'] as int?) ?? 0;
  }

  /// 更新訊息的解密重試計數器
  /// 每次解密失敗時呼叫，用於追蹤重試次數（最多 2 次）
  Future<void> updateDecryptRetryCount(String messageId, int retryCount) async {
    if (messageId.isEmpty) return;
    final db = await initDB();
    
    await db.update(
      'messages',
      {'decrypt_retry_count': retryCount},
      where: 'id = ? OR client_msg_id = ?',
      whereArgs: [messageId, messageId],
    );
  }

  /// 更新訊息內容與狀態（用於接收到 re_encrypt_response 後更新本地訊息）
  /// 將解密成功的明文內容寫回資料庫，並重置重試計數器
  Future<void> updateMessageContentAndStatus({
    required String messageId,
    required String newContent,
    required MessageStatus newStatus,
  }) async {
    if (messageId.isEmpty) return;
    final db = await initDB();
    
    await db.update(
      'messages',
      {
        'content': newContent,
        'status': newStatus.name,
        'decrypt_retry_count': 0,  // 重置重試計數器
      },
      where: 'id = ? OR client_msg_id = ?',
      whereArgs: [messageId, messageId],
    );
  }

  /// 取得所有狀態為 decryptingRetry 的訊息
  /// 用於 app 重啟或 WebSocket 重連時，自動重試解密失敗的訊息
  Future<List<Message>> getDecryptingRetryMessages() async {
    final db = await initDB();
    
    final rows = await db.query(
      'messages',
      where: 'status = ?',
      whereArgs: ['decryptingRetry'],
      orderBy: 'created_at ASC',
    );
    
    return rows.map(Message.fromMap).toList();
  }

  /// 🔐 標記訊息為已解密（設定 is_decrypted = 1）
  /// 用於接收到 re_encrypt_response 並成功解密後，更新本地資料庫
  Future<void> markMessageAsDecrypted(String messageId) async {
    if (messageId.isEmpty) return;
    final db = await initDB();
    
    await db.update(
      'messages',
      {'is_decrypted': 1},
      where: 'id = ? OR client_msg_id = ?',
      whereArgs: [messageId, messageId],
    );
  }

  /// 🔐 取得所有未解密的訊息（is_decrypted = 0）
  /// 用於 E2EE Auto-Resend 初始化時，檢查哪些訊息需要重新加密
  Future<List<Message>> getUndecryptedMessages() async {
    final db = await initDB();
    
    final rows = await db.query(
      'messages',
      where: 'is_decrypted = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );
    
    return rows.map(Message.fromMap).toList();
  }

  /// 🔐 E2EE Key Recovery: 標記所有未解密訊息為永久無法復原
  /// 當用戶強制生成新金鑰後，將所有 is_decrypted = 0 的訊息設定為：
  /// - decrypt_retry_count = 999（最大值，停止重試）
  /// - content = '🔐 訊息無法復原'
  /// - status = 'failed'
  Future<void> markAllUndecryptedAsUnrecoverable() async {
    final db = await initDB();
    
    await db.update(
      'messages',
      {
        'decrypt_retry_count': 999,
        'content': '🔐 訊息無法復原',
        'status': 'failed',
      },
      where: 'is_decrypted = ?',
      whereArgs: [0],
    );
  }
}
