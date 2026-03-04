import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:app/core/storage/local_db_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('messages table has required columns', () async {
    final db = await LocalDbService().initDB(
      overridePath: inMemoryDatabasePath,
    );
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    final names = columns.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll([
        'id',
        'client_msg_id',
        'room_id',
        'sender_id',
        'receiver_id',
        'reply_to_message_id',
        'reactions',
        'is_unsent',
        'content',
        'type',
        'created_at',
        'is_read',
        'read_at',
        'read_by',
      ]),
    );
    await db.close();
  });
}
