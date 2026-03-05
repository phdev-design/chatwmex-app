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
      version: 4,
      onCreate: (db, version) async {
        await _createMessagesTable(db);
        await _logDbEvent('db_create', {'version': version});
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureMessagesColumns(db);
        await _logDbEvent('db_upgrade', {'from': oldVersion, 'to': newVersion});
      },
      onOpen: (db) async {
        await _ensureMessagesColumns(db);
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
      'read_by TEXT, ' // 👉 記得上一行結尾要加逗號
      'link_preview TEXT' // 👉 新增這行
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
    final existing = columns
        .map((row) => row['name'])
        .whereType<String>()
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
      // 👉 新增下面這一行
      'link_preview': 'ALTER TABLE messages ADD COLUMN link_preview TEXT',
    };
    for (final entry in missing.entries) {
      if (!existing.contains(entry.key)) {
        await db.execute(entry.value);
        await _logDbEvent('db_repair', {'add_column': entry.key});
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

  Future<void> deleteMessageLocal(String messageId) async {
    if (messageId.isEmpty) return;
    final db = await initDB();
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }
}
