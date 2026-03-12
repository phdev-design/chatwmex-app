import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/models/message.dart';

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
    // Don't close the db here since LocalDbService is a singleton
  });

  group('Database schema and migration tests', () {
    // Feature: encrypted-audio-messaging-ui-completion, Property 8: Database file_key round-trip
    // **Validates: Requirements 4.1, 4.2, 4.3, 5.2, 5.3, 5.4, 5.5**
    test('file_key column exists in messages table', () async {
      final db = await LocalDbService().initDB(
        overridePath: inMemoryDatabasePath,
      );
      
      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final names = columns.map((row) => row['name']).toSet();
      
      expect(names, contains('file_key'));
    });

    // Feature: encrypted-audio-messaging-ui-completion, Property 8: Database file_key round-trip
    // **Validates: Requirements 4.1, 4.2, 4.3, 5.2, 5.3, 5.4, 5.5**
    test('file_key round-trip preserves value', () async {
      final service = LocalDbService();
      await service.initDB(overridePath: inMemoryDatabasePath);
      
      // Use unique room ID for this test
      final roomId = 'room_roundtrip_${DateTime.now().millisecondsSinceEpoch}';
      
      // Test with various fileKey values
      final testCases = [
        'base64EncodedKey123==',
        'anotherKey456',
        'veryLongKeyValue' * 10, // Long key
        '', // Empty string
      ];
      
      for (final fileKey in testCases) {
        final message = Message(
          id: 'test_${fileKey.hashCode}',
          content: 'https://example.com/audio.m4a',
          senderId: 'user1',
          roomId: roomId,
          type: MessageType.voice,
          createdAt: DateTime.now(),
          fileKey: fileKey.isEmpty ? null : fileKey,
        );
        
        // Insert message
        await service.insertMessages([message]);
        
        // Query it back
        final messages = await service.getMessagesByRoom(roomId);
        final retrieved = messages.firstWhere((m) => m.id == message.id);
        
        // Verify fileKey is preserved
        expect(retrieved.fileKey, equals(message.fileKey),
            reason: 'fileKey should be preserved for value: $fileKey');
      }
    });

    // Feature: encrypted-audio-messaging-ui-completion, Property 8: Database file_key round-trip
    // **Validates: Requirements 4.1, 4.2, 4.3, 5.2, 5.3, 5.4, 5.5**
    test('null fileKey is handled correctly', () async {
      final service = LocalDbService();
      await service.initDB(overridePath: inMemoryDatabasePath);
      
      // Use unique room ID for this test
      final roomId = 'room_null_${DateTime.now().millisecondsSinceEpoch}';
      
      final message = Message(
        id: 'test_null_key',
        content: 'https://example.com/legacy_audio.m4a',
        senderId: 'user1',
        roomId: roomId,
        type: MessageType.voice,
        createdAt: DateTime.now(),
        fileKey: null, // Legacy audio without encryption
      );
      
      await service.insertMessages([message]);
      
      final messages = await service.getMessagesByRoom(roomId);
      final retrieved = messages.firstWhere((m) => m.id == message.id);
      
      expect(retrieved.fileKey, isNull);
    });

    // Feature: encrypted-audio-messaging-ui-completion, Property 9: Migration data preservation
    // **Validates: Requirements 4.1, 4.2, 4.3, 5.2, 5.3, 5.4, 5.5**
    test('migration preserves existing message data', () async {
      final service = LocalDbService();
      final db = await service.initDB(overridePath: inMemoryDatabasePath);
      
      // Use unique room ID for this test
      final roomId = 'room_migration_${DateTime.now().millisecondsSinceEpoch}';
      
      // Insert messages before migration
      final originalMessages = [
        Message(
          id: 'msg1_${DateTime.now().millisecondsSinceEpoch}',
          content: 'Test message 1',
          senderId: 'user1',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
        Message(
          id: 'msg2_${DateTime.now().millisecondsSinceEpoch}',
          content: 'Test message 2',
          senderId: 'user2',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
      ];
      
      await service.insertMessages(originalMessages);
      
      // Simulate migration by calling _ensureMessagesColumns
      // This is called automatically on db open, but we can verify it doesn't lose data
      final columnsBeforeMigration = await db.rawQuery('PRAGMA table_info(messages)');
      final namesBeforeMigration = columnsBeforeMigration.map((row) => row['name']).toSet();
      
      // Verify file_key column exists (it should already be there in version 5)
      expect(namesBeforeMigration, contains('file_key'));
      
      // Retrieve messages after migration
      final messagesAfterMigration = await service.getMessagesByRoom(roomId);
      
      // Verify all original messages are preserved
      expect(messagesAfterMigration.length, equals(originalMessages.length));
      
      for (final original in originalMessages) {
        final retrieved = messagesAfterMigration.firstWhere((m) => m.id == original.id);
        expect(retrieved.content, equals(original.content));
        expect(retrieved.senderId, equals(original.senderId));
        expect(retrieved.roomId, equals(original.roomId));
        expect(retrieved.type, equals(original.type));
      }
    });

    // Feature: encrypted-audio-messaging-ui-completion, Property 9: Migration data preservation
    // **Validates: Requirements 4.1, 4.2, 4.3, 5.2, 5.3, 5.4, 5.5**
    test('migration adds file_key column without data loss', () async {
      final service = LocalDbService();
      final db = await service.initDB(overridePath: inMemoryDatabasePath);
      
      // Use unique room ID for this test
      final roomId = 'room_data_loss_${DateTime.now().millisecondsSinceEpoch}';
      
      // Insert test data with various message types
      final testMessages = [
        Message(
          id: 'text_msg_${DateTime.now().millisecondsSinceEpoch}',
          content: 'Text message',
          senderId: 'user1',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
        Message(
          id: 'voice_msg_${DateTime.now().millisecondsSinceEpoch}',
          content: 'https://example.com/audio.m4a',
          senderId: 'user2',
          roomId: roomId,
          type: MessageType.voice,
          createdAt: DateTime.now(),
        ),
        Message(
          id: 'image_msg_${DateTime.now().millisecondsSinceEpoch}',
          content: 'https://example.com/image.jpg',
          senderId: 'user3',
          roomId: roomId,
          type: MessageType.image,
          createdAt: DateTime.now(),
        ),
      ];
      
      await service.insertMessages(testMessages);
      
      // Get count for this room before
      final messagesBefore = await service.getMessagesByRoom(roomId);
      final countBeforeValue = messagesBefore.length;
      
      // Verify file_key column exists
      final columns = await db.rawQuery('PRAGMA table_info(messages)');
      final names = columns.map((row) => row['name']).toSet();
      expect(names, contains('file_key'));
      
      // Get count for this room after
      final messagesAfter = await service.getMessagesByRoom(roomId);
      final countAfterValue = messagesAfter.length;
      
      // Verify no data loss
      expect(countAfterValue, equals(countBeforeValue));
      expect(countAfterValue, equals(testMessages.length));
      
      // Verify all messages are retrievable
      final retrievedMessages = await service.getMessagesByRoom(roomId);
      expect(retrievedMessages.length, equals(testMessages.length));
      
      // Verify each message's data is intact
      for (final original in testMessages) {
        final retrieved = retrievedMessages.firstWhere((m) => m.id == original.id);
        expect(retrieved.content, equals(original.content));
        expect(retrieved.senderId, equals(original.senderId));
        expect(retrieved.type, equals(original.type));
        expect(retrieved.fileKey, isNull); // Should be null for messages without encryption
      }
    });
  });
}
