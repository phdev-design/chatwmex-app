import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/models/message.dart';

/// Unit Tests for Task 6.6 and 6.7: markMessageAsDecrypted() and getUndecryptedMessages()
/// **Validates: Requirements 2.6, 2.7, 3.3**
/// 
/// Tests the new LocalDbService methods for tracking decryption state:
/// - markMessageAsDecrypted() sets is_decrypted = 1
/// - getUndecryptedMessages() returns only messages where is_decrypted = 0
/// - Error handling for invalid message IDs
/// - Concurrent updates to same message
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Unit Tests - markMessageAsDecrypted() method', () {
    test('6.6.1: Message is marked as decrypted (is_decrypted = 1)', () async {
      // Arrange
      final service = LocalDbService();
      final db = await service.initDB(overridePath: inMemoryDatabasePath);
      
      final roomId = 'room_mark_test_${DateTime.now().millisecondsSinceEpoch}';
      final messageId = 'msg_mark_${DateTime.now().millisecondsSinceEpoch}';
      
      final message = Message(
        id: messageId,
        content: '🔐 解密失敗',
        senderId: 'user1',
        roomId: roomId,
        type: MessageType.text,
        createdAt: DateTime.now(),
      );
      
      await service.insertMessages([message]);
      
      // Verify initial state (is_decrypted = 0)
      var result = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );
      expect(result.first['is_decrypted'], equals(0));

      // Act
      await service.markMessageAsDecrypted(messageId);

      // Assert
      result = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );
      expect(result.first['is_decrypted'], equals(1),
          reason: 'Message should be marked as decrypted');
    });

    test('6.6.2: Database update executes correctly', () async {
      // Arrange
      final service = LocalDbService();
      final db = await service.initDB(overridePath: inMemoryDatabasePath);
      
      final roomId = 'room_update_test_${DateTime.now().millisecondsSinceEpoch}';
      final messageId = 'msg_update_${DateTime.now().millisecondsSinceEpoch}';
      
      final message = Message(
        id: messageId,
        content: 'Test message',
        senderId: 'user1',
        roomId: roomId,
        type: MessageType.text,
        createdAt: DateTime.now(),
      );
      
      await service.insertMessages([message]);

      // Act
      await service.markMessageAsDecrypted(messageId);

      // Assert - Verify the UPDATE was executed
      final result = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );
      
      expect(result.length, equals(1));
      expect(result.first['is_decrypted'], equals(1));
      expect(result.first['content'], equals('Test message'),
          reason: 'Other fields should remain unchanged');
    });

    test('6.6.3: Error handling for invalid message ID', () async {
      // Arrange
      final service = LocalDbService();
      await service.initDB(overridePath: inMemoryDatabasePath);
      
      const invalidMessageId = 'non_existent_message_id';

      // Act & Assert - Should not throw error
      await expectLater(
        service.markMessageAsDecrypted(invalidMessageId),
        completes,
        reason: 'Should handle invalid message ID gracefully',
      );
    });

    test('6.6.4: Error handling for empty message ID', () async {
      // Arrange
      final service = LocalDbService();
      await service.initDB(overridePath: inMemoryDatabasePath);

      // Act & Assert - Should return early without error
      await expectLater(
        service.markMessageAsDecrypted(''),
        completes,
        reason: 'Should handle empty message ID gracefully',
      );
    });

    test('6.6.5: Concurrent updates to same message', () async {
      // Arrange
      final service = LocalDbService();
      final db = await service.initDB(overridePath: inMemoryDatabasePath);
      
      final roomId = 'room_concurrent_${DateTime.now().millisecondsSinceEpoch}';
      final messageId = 'msg_concurrent_${DateTime.now().millisecondsSinceEpoch}';
      
      final message = Message(
        id: messageId,
        content: 'Concurrent test',
        senderId: 'user1',
        roomId: roomId,
        type: MessageType.text,
        createdAt: DateTime.now(),
      );
      
      await service.insertMessages([message]);

      // Act - Trigger 5 concurrent updates
      await Future.wait([
        service.markMessageAsDecrypted(messageId),
        service.markMessageAsDecrypted(messageId),
        service.markMessageAsDecrypted(messageId),
        service.markMessageAsDecrypted(messageId),
        service.markMessageAsDecrypted(messageId),
      ]);

      // Assert - Message should still be marked as decrypted (no corruption)
      final result = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );
      
      expect(result.length, equals(1));
      expect(result.first['is_decrypted'], equals(1),
          reason: 'Concurrent updates should not corrupt data');
    });

    test('6.6.6: Marking already decrypted message is idempotent', () async {
      // Arrange
      final service = LocalDbService();
      final db = await service.initDB(overridePath: inMemoryDatabasePath);
      
      final roomId = 'room_idempotent_${DateTime.now().millisecondsSinceEpoch}';
      final messageId = 'msg_idempotent_${DateTime.now().millisecondsSinceEpoch}';
      
      final message = Message(
        id: messageId,
        content: 'Idempotent test',
        senderId: 'user1',
        roomId: roomId,
        type: MessageType.text,
        createdAt: DateTime.now(),
      );
      
      await service.insertMessages([message]);
      
      // Mark as decrypted first time
      await service.markMessageAsDecrypted(messageId);

      // Act - Mark as decrypted again
      await service.markMessageAsDecrypted(messageId);

      // Assert - Should still be marked as decrypted
      final result = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );
      
      expect(result.first['is_decrypted'], equals(1),
          reason: 'Marking already decrypted message should be idempotent');
    });
  });

  group('Unit Tests - getUndecryptedMessages() method', () {
    test('6.7.1: Returns only messages where is_decrypted = 0', () async {
      // Arrange
      final service = LocalDbService();
      final db = await service.initDB(overridePath: inMemoryDatabasePath);
      
      final roomId = 'room_undecrypted_${DateTime.now().millisecondsSinceEpoch}';
      
      // Create 3 undecrypted messages and 2 decrypted messages
      final messages = [
        Message(
          id: 'undecrypted1_${DateTime.now().millisecondsSinceEpoch}',
          content: '🔐 解密失敗',
          senderId: 'user1',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
        Message(
          id: 'undecrypted2_${DateTime.now().millisecondsSinceEpoch}',
          content: '🔐 解密失敗',
          senderId: 'user2',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
        Message(
          id: 'undecrypted3_${DateTime.now().millisecondsSinceEpoch}',
          content: '🔐 解密失敗',
          senderId: 'user3',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
      ];
      
      await service.insertMessages(messages);
      
      // Mark 2 messages as decrypted
      await service.markMessageAsDecrypted(messages[1].id);
      await service.markMessageAsDecrypted(messages[2].id);

      // Act
      final undecryptedMessages = await service.getUndecryptedMessages();

      // Assert
      final undecryptedInRoom = undecryptedMessages.where((m) => m.roomId == roomId).toList();
      expect(undecryptedInRoom.length, equals(1),
          reason: 'Should return only 1 undecrypted message');
      expect(undecryptedInRoom.first.id, equals(messages[0].id));
    });

    test('6.7.2: Excludes messages where is_decrypted = 1', () async {
      // Arrange
      final service = LocalDbService();
      await service.initDB(overridePath: inMemoryDatabasePath);
      
      final roomId = 'room_exclude_${DateTime.now().millisecondsSinceEpoch}';
      
      final messages = [
        Message(
          id: 'decrypted1_${DateTime.now().millisecondsSinceEpoch}',
          content: 'Decrypted message 1',
          senderId: 'user1',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
        Message(
          id: 'decrypted2_${DateTime.now().millisecondsSinceEpoch}',
          content: 'Decrypted message 2',
          senderId: 'user2',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
      ];
      
      await service.insertMessages(messages);
      
      // Mark all as decrypted
      await service.markMessageAsDecrypted(messages[0].id);
      await service.markMessageAsDecrypted(messages[1].id);

      // Act
      final undecryptedMessages = await service.getUndecryptedMessages();

      // Assert
      final undecryptedInRoom = undecryptedMessages.where((m) => m.roomId == roomId).toList();
      expect(undecryptedInRoom.length, equals(0),
          reason: 'Should not return any decrypted messages');
    });

    test('6.7.3: Handles empty result set', () async {
      // Arrange
      final service = LocalDbService();
      await service.initDB(overridePath: inMemoryDatabasePath);
      
      final roomId = 'room_empty_${DateTime.now().millisecondsSinceEpoch}';
      
      // Create messages and mark all as decrypted
      final messages = [
        Message(
          id: 'all_decrypted1_${DateTime.now().millisecondsSinceEpoch}',
          content: 'Message 1',
          senderId: 'user1',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
      ];
      
      await service.insertMessages(messages);
      await service.markMessageAsDecrypted(messages[0].id);

      // Act
      final undecryptedMessages = await service.getUndecryptedMessages();

      // Assert
      final undecryptedInRoom = undecryptedMessages.where((m) => m.roomId == roomId).toList();
      expect(undecryptedInRoom, isEmpty,
          reason: 'Should return empty list when all messages are decrypted');
    });

    test('6.7.4: Query performance with large datasets', () async {
      // Arrange
      final service = LocalDbService();
      await service.initDB(overridePath: inMemoryDatabasePath);
      
      final roomId = 'room_performance_${DateTime.now().millisecondsSinceEpoch}';
      
      // Create 100 messages (50 undecrypted, 50 decrypted)
      final messages = List.generate(100, (i) => Message(
        id: 'perf_msg_${i}_${DateTime.now().millisecondsSinceEpoch}',
        content: i < 50 ? '🔐 解密失敗' : 'Decrypted message $i',
        senderId: 'user$i',
        roomId: roomId,
        type: MessageType.text,
        createdAt: DateTime.now(),
      ));
      
      await service.insertMessages(messages);
      
      // Mark second half as decrypted
      for (int i = 50; i < 100; i++) {
        await service.markMessageAsDecrypted(messages[i].id);
      }

      // Act
      final stopwatch = Stopwatch()..start();
      final undecryptedMessages = await service.getUndecryptedMessages();
      stopwatch.stop();

      // Assert
      final undecryptedInRoom = undecryptedMessages.where((m) => m.roomId == roomId).toList();
      expect(undecryptedInRoom.length, equals(50),
          reason: 'Should return exactly 50 undecrypted messages');
      expect(stopwatch.elapsedMilliseconds, lessThan(1000),
          reason: 'Query should complete in less than 1 second');
    });

    test('6.7.5: Returns messages across multiple rooms', () async {
      // Arrange
      final service = LocalDbService();
      await service.initDB(overridePath: inMemoryDatabasePath);
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final room1 = 'room1_$timestamp';
      final room2 = 'room2_$timestamp';
      final room3 = 'room3_$timestamp';
      
      final messages = [
        Message(
          id: 'room1_msg1_$timestamp',
          content: '🔐 解密失敗',
          senderId: 'user1',
          roomId: room1,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
        Message(
          id: 'room2_msg1_$timestamp',
          content: '🔐 解密失敗',
          senderId: 'user2',
          roomId: room2,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
        Message(
          id: 'room3_msg1_$timestamp',
          content: '🔐 解密失敗',
          senderId: 'user3',
          roomId: room3,
          type: MessageType.text,
          createdAt: DateTime.now(),
        ),
      ];
      
      await service.insertMessages(messages);

      // Act
      final undecryptedMessages = await service.getUndecryptedMessages();

      // Assert
      final undecryptedInRooms = undecryptedMessages.where((m) => 
        m.roomId == room1 || m.roomId == room2 || m.roomId == room3
      ).toList();
      
      expect(undecryptedInRooms.length, equals(3),
          reason: 'Should return undecrypted messages from all rooms');
      
      final roomIds = undecryptedInRooms.map((m) => m.roomId).toSet();
      expect(roomIds, containsAll([room1, room2, room3]));
    });

    test('6.7.6: Respects message status field (does not filter by status)', () async {
      // Arrange
      final service = LocalDbService();
      await service.initDB(overridePath: inMemoryDatabasePath);
      
      final roomId = 'room_status_${DateTime.now().millisecondsSinceEpoch}';
      
      // Create messages with different statuses, all undecrypted
      final messages = [
        Message(
          id: 'read_undecrypted_${DateTime.now().millisecondsSinceEpoch}',
          content: '🔐 解密失敗',
          senderId: 'user1',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
          status: MessageStatus.read,
        ),
        Message(
          id: 'delivered_undecrypted_${DateTime.now().millisecondsSinceEpoch}',
          content: '🔐 解密失敗',
          senderId: 'user2',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
          status: MessageStatus.delivered,
        ),
        Message(
          id: 'sent_undecrypted_${DateTime.now().millisecondsSinceEpoch}',
          content: '🔐 解密失敗',
          senderId: 'user3',
          roomId: roomId,
          type: MessageType.text,
          createdAt: DateTime.now(),
          status: MessageStatus.sent,
        ),
      ];
      
      await service.insertMessages(messages);

      // Act
      final undecryptedMessages = await service.getUndecryptedMessages();

      // Assert
      final undecryptedInRoom = undecryptedMessages.where((m) => m.roomId == roomId).toList();
      expect(undecryptedInRoom.length, equals(3),
          reason: 'Should return all undecrypted messages regardless of status');
      
      // Verify all statuses are present
      final statuses = undecryptedInRoom.map((m) => m.status).toSet();
      expect(statuses, containsAll([MessageStatus.read, MessageStatus.delivered, MessageStatus.sent]));
    });
  });
}
