import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:app/models/message.dart';

class LocalDbService {
  LocalDbService._internal();

  static final LocalDbService _instance = LocalDbService._internal();

  factory LocalDbService() => _instance;

  Database? _db;

  Future<Database> initDB() async {
    if (_db != null) {
      return _db!;
    }

    final directory = await getApplicationDocumentsDirectory();
    final dbPath = join(directory.path, 'chat_cache.db');
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE messages('
          'id TEXT PRIMARY KEY, '
          'room_id TEXT, '
          'sender_id TEXT, '
          'receiver_id TEXT, '
          'reply_to_message_id TEXT, '
          'content TEXT, '
          'type TEXT, '
          'created_at INTEGER, '
          'read_by TEXT'
          ')',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE messages ADD COLUMN reply_to_message_id TEXT',
          );
        }
      },
    );
    return _db!;
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
    final rows = await db.query(
      'messages',
      where: 'room_id = ?',
      whereArgs: [roomId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(Message.fromMap).toList();
  }
}
