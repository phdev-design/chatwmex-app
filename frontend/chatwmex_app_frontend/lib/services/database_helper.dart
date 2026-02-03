import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../models/message.dart';
import '../models/chat_room.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('chatwmex.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const textNullableType = 'TEXT';
    const integerType = 'INTEGER NOT NULL';
    const integerNullableType = 'INTEGER'; // Nullable integer
    const boolType = 'INTEGER NOT NULL'; // 0 or 1

    await db.execute('''
CREATE TABLE chat_rooms (
  id $idType,
  name $textType,
  last_message $textType,
  last_message_time $textType,
  unread_count $integerType,
  avatar_url $textNullableType,
  is_group $boolType,
  participants $textType
)
''');

    await db.execute('''
CREATE TABLE messages (
  id $idType,
  sender_id $textType,
  sender_name $textType,
  content $textType,
  timestamp $textType,
  room_id $textType,
  type $textType,
  file_url $textNullableType,
  duration $integerNullableType,
  file_size $integerNullableType,
  reactions $textType,
  read_by $textType,
  status $integerType
)
''');
  }

  // --- Chat Rooms ---

  Future<void> insertChatRoom(ChatRoom chatRoom) async {
    final db = await instance.database;
    await db.insert(
      'chat_rooms',
      chatRoom.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertChatRooms(List<ChatRoom> chatRooms) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var room in chatRooms) {
      batch.insert(
        'chat_rooms',
        room.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChatRoom>> getChatRooms() async {
    final db = await instance.database;
    final orderBy = 'last_message_time DESC';
    final result = await db.query('chat_rooms', orderBy: orderBy);
    return result.map((json) => ChatRoom.fromMap(json)).toList();
  }

  // --- Messages ---

  Future<void> insertMessage(Message message) async {
    final db = await instance.database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertMessages(List<Message> messages) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var msg in messages) {
      batch.insert(
        'messages',
        msg.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Message>> getMessages(String roomId,
      {int limit = 50, int offset = 0}) async {
    final db = await instance.database;
    final orderBy = 'timestamp DESC';
    final result = await db.query(
      'messages',
      where: 'room_id = ?',
      whereArgs: [roomId],
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return result.map((json) => Message.fromMap(json)).toList();
  }

  Future<void> updateMessageStatus(String id, MessageStatus status) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'status': status.index},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateMessageReadBy(String id, List<String> readBy) async {
    final db = await instance.database;
    await db.update(
      'messages',
      {'read_by': jsonEncode(readBy)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Message>> getPendingMessages() async {
    final db = await instance.database;
    final result = await db.query(
      'messages',
      where: 'status = ?',
      whereArgs: [MessageStatus.sending.index],
    );
    return result.map((json) => Message.fromMap(json)).toList();
  }

  Future<void> deleteMessage(String id) async {
    final db = await instance.database;
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMessages(String roomId) async {
    final db = await instance.database;
    await db.delete(
      'messages',
      where: 'room_id = ?',
      whereArgs: [roomId],
    );
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
