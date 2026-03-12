import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/providers/room_media_provider.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:app/models/message.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/core/storage/storage_service.dart';

/// Bug Condition Exploration Test for Media Count Display Mismatch
/// 
/// **Property 1: Bug Condition - Count Matches Rendered Items**
/// **Validates: Requirements 1.1, 1.2, 1.3**
/// 
/// CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists
/// DO NOT attempt to fix the test or the code when it fails
/// 
/// This test encodes the expected behavior - it will validate the fix when it passes after implementation
/// 
/// GOAL: Surface counterexamples that demonstrate the bug exists
/// 
/// Bug Condition: Messages with Base64 encrypted content (≥40 chars with +/= characters) 
/// that fail decryption are included in state.messages.length but resolveFullUrl returns 
/// empty string for them, causing them to be filtered from rendering.
/// 
/// Expected Outcome: Test FAILS showing count mismatch (e.g., state.messages.length=10 
/// but countOfRenderedItems=7)

void main() {
  group('Bug Condition Exploration - Media Count Display Mismatch', () {
    late ProviderContainer container;
    late MockChatRepository mockRepository;

    setUp(() {
      mockRepository = MockChatRepository();
      
      container = ProviderContainer(
        overrides: [
          chatRepositoryProvider.overrideWithValue(mockRepository),
          storageServiceProvider.overrideWithValue(MockStorageService()),
          cryptoServiceProvider.overrideWithValue(MockCryptoService()),
          publicKeyCacheServiceProvider.overrideWithValue(MockPublicKeyCacheService()),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    /// **Property 1: Bug Condition - Count Matches Rendered Items**
    /// **Validates: Requirements 1.1, 1.2, 1.3**
    /// 
    /// Test Scenario 1: Mixed valid/invalid messages
    /// Backend returns 10 messages, 3 have invalid Base64 encrypted content
    /// 
    /// EXPECTED ON UNFIXED CODE: 
    /// - state.messages.length = 10 (includes all messages)
    /// - countOfRenderedItems = 7 (only messages where resolveFullUrl returns non-empty)
    /// - TEST FAILS with mismatch
    test('EXPECTED TO FAIL: 10 messages with 3 invalid Base64 content - count should match rendered items', () async {
      // Arrange: Create 10 messages, 3 with invalid Base64 encrypted content
      final messages = [
        // 7 valid messages with plaintext URLs
        _createMessage('msg1', 'https://example.com/image1.jpg'),
        _createMessage('msg2', 'https://example.com/image2.jpg'),
        _createMessage('msg3', '/uploads/images/file3.jpg'),
        _createMessage('msg4', '/uploads/images/file4.jpg'),
        _createMessage('msg5', '507f1f77bcf86cd799439011'), // ObjectID
        _createMessage('msg6', 'https://example.com/image6.jpg'),
        _createMessage('msg7', '/uploads/images/file7.jpg'),
        
        // 3 invalid messages with Base64 encrypted content (≥40 chars with +/= characters)
        // These simulate failed decryption - content remains encrypted
        _createMessage('msg8', 'aGVsbG8gd29ybGQgdGhpcyBpcyBhIGxvbmcgYmFzZTY0IGVuY29kZWQgc3RyaW5nKys='),
        _createMessage('msg9', 'YW5vdGhlciBsb25nIGJhc2U2NCBlbmNvZGVkIGNvbnRlbnQgd2l0aCBzcGVjaWFsIGNoYXJzKy8r'),
        _createMessage('msg10', 'dGhpcmQgaW52YWxpZCBlbmNyeXB0ZWQgY29udGVudCB0aGF0IGZhaWxzIGRlY3J5cHRpb24rLys='),
      ];

      mockRepository.setMockMessages(messages);

      // Act: Load initial media
      final notifier = container.read(
        roomMediaProvider(
          (roomId: 'test-room', type: 'image'),
        ).notifier,
      );
      await notifier.loadInitial();

      final state = container.read(
        roomMediaProvider(
          (roomId: 'test-room', type: 'image'),
        ),
      );

      // Calculate how many messages are actually renderable
      final renderableCount = state.messages.where((msg) {
        final url = resolveFullUrl(msg.content);
        return url.isNotEmpty;
      }).length;

      // Assert: Count should match rendered items
      // ON UNFIXED CODE: This will FAIL because state.messages.length includes all 10 messages
      // but only some have non-empty URLs from resolveFullUrl
      expect(
        state.messages.length,
        equals(renderableCount),
        reason: 'BUG DETECTED: state.messages.length (${state.messages.length}) '
                'does not match renderable count ($renderableCount). '
                'Messages with invalid encrypted content are counted but not rendered.',
      );

      // Document the counterexamples
      final invalidMessages = state.messages.where((msg) {
        final url = resolveFullUrl(msg.content);
        return url.isEmpty;
      }).toList();

      print('\n=== COUNTEREXAMPLES FOUND ===');
      print('Total messages in state: ${state.messages.length}');
      print('Renderable messages: $renderableCount');
      print('Invalid messages (in state but not renderable): ${invalidMessages.length}');
      for (final msg in invalidMessages) {
        print('  - Message ${msg.id}: content="${msg.content.substring(0, 40)}..."');
        print('    resolveFullUrl returns: "${resolveFullUrl(msg.content)}"');
      }
      print('=============================\n');
    });

    /// **Property 1: Bug Condition - Count Matches Rendered Items**
    /// **Validates: Requirements 1.1, 1.2, 1.3**
    /// 
    /// Test Scenario 2: All invalid messages
    /// Backend returns 5 messages, all have invalid encrypted content
    /// 
    /// EXPECTED ON UNFIXED CODE:
    /// - state.messages.length = 5
    /// - countOfRenderedItems = 0
    /// - TEST FAILS with mismatch
    test('EXPECTED TO FAIL: 5 messages all invalid - count should match rendered items (0)', () async {
      // Arrange: Create 5 messages, all with invalid Base64 encrypted content
      final messages = [
        _createMessage('msg1', 'aGVsbG8gd29ybGQgdGhpcyBpcyBhIGxvbmcgYmFzZTY0IGVuY29kZWQgc3RyaW5nKys='),
        _createMessage('msg2', 'YW5vdGhlciBsb25nIGJhc2U2NCBlbmNvZGVkIGNvbnRlbnQgd2l0aCBzcGVjaWFsIGNoYXJzKy8r'),
        _createMessage('msg3', 'dGhpcmQgaW52YWxpZCBlbmNyeXB0ZWQgY29udGVudCB0aGF0IGZhaWxzIGRlY3J5cHRpb24rLys='),
        _createMessage('msg4', 'Zm91cnRoIGludmFsaWQgZW5jcnlwdGVkIG1lc3NhZ2Ugd2l0aCBiYXNlNjQgY2hhcnMrLz0='),
        _createMessage('msg5', 'ZmlmdGggaW52YWxpZCBlbmNyeXB0ZWQgbWVzc2FnZSB3aXRoIGJhc2U2NCBjaGFycysrKz0='),
      ];

      mockRepository.setMockMessages(messages);

      // Act: Load initial media
      final notifier = container.read(
        roomMediaProvider(
          (roomId: 'test-room', type: 'image'),
        ).notifier,
      );
      await notifier.loadInitial();

      final state = container.read(
        roomMediaProvider(
          (roomId: 'test-room', type: 'image'),
        ),
      );

      // Calculate renderable count
      final renderableCount = state.messages.where((msg) {
        final url = resolveFullUrl(msg.content);
        return url.isNotEmpty;
      }).length;

      // Assert: Count should match rendered items (should be 0)
      // ON UNFIXED CODE: This will FAIL because state.messages.length includes all messages
      // but some/all may not be renderable
      expect(
        state.messages.length,
        equals(renderableCount),
        reason: 'BUG DETECTED: state.messages.length (${state.messages.length}) '
                'does not match renderable count ($renderableCount). '
                'All messages have invalid encrypted content but are still counted.',
      );

      final invalidMessages = state.messages.where((msg) {
        final url = resolveFullUrl(msg.content);
        return url.isEmpty;
      }).toList();

      print('\n=== COUNTEREXAMPLES (All Invalid) ===');
      print('Total messages in state: ${state.messages.length}');
      print('Renderable messages: $renderableCount');
      print('Invalid messages: ${invalidMessages.length}');
      for (final msg in invalidMessages) {
        print('  - Message ${msg.id}: content="${msg.content.substring(0, 40)}..."');
      }
      print('=====================================\n');
    });

    /// **Property 1: Bug Condition - Count Matches Rendered Items**
    /// **Validates: Requirements 1.1, 1.2, 1.3**
    /// 
    /// Test Scenario 3: Pagination with invalid messages in both batches
    /// Initial load: 10 messages (3 invalid), Load more: 10 messages (2 invalid)
    /// 
    /// EXPECTED ON UNFIXED CODE:
    /// - state.messages.length = 20
    /// - countOfRenderedItems = 15
    /// - TEST FAILS with mismatch
    test('EXPECTED TO FAIL: Pagination with invalid messages in both batches - count should match rendered items', () async {
      // Arrange: First batch - 10 messages with 3 invalid
      final firstBatch = [
        _createMessage('msg1', 'https://example.com/image1.jpg'),
        _createMessage('msg2', 'https://example.com/image2.jpg'),
        _createMessage('msg3', '/uploads/images/file3.jpg'),
        _createMessage('msg4', 'aGVsbG8gd29ybGQgdGhpcyBpcyBhIGxvbmcgYmFzZTY0IGVuY29kZWQgc3RyaW5nKys='), // Invalid
        _createMessage('msg5', '/uploads/images/file5.jpg'),
        _createMessage('msg6', 'https://example.com/image6.jpg'),
        _createMessage('msg7', 'YW5vdGhlciBsb25nIGJhc2U2NCBlbmNvZGVkIGNvbnRlbnQgd2l0aCBzcGVjaWFsIGNoYXJzKy8r'), // Invalid
        _createMessage('msg8', '/uploads/images/file8.jpg'),
        _createMessage('msg9', 'dGhpcmQgaW52YWxpZCBlbmNyeXB0ZWQgY29udGVudCB0aGF0IGZhaWxzIGRlY3J5cHRpb24rLys='), // Invalid
        _createMessage('msg10', 'https://example.com/image10.jpg'),
      ];

      // Second batch - 10 messages with 2 invalid
      final secondBatch = [
        _createMessage('msg11', 'https://example.com/image11.jpg'),
        _createMessage('msg12', 'Zm91cnRoIGludmFsaWQgZW5jcnlwdGVkIG1lc3NhZ2Ugd2l0aCBiYXNlNjQgY2hhcnMrLz0='), // Invalid
        _createMessage('msg13', '/uploads/images/file13.jpg'),
        _createMessage('msg14', 'https://example.com/image14.jpg'),
        _createMessage('msg15', '/uploads/images/file15.jpg'),
        _createMessage('msg16', 'ZmlmdGggaW52YWxpZCBlbmNyeXB0ZWQgbWVzc2FnZSB3aXRoIGJhc2U2NCBjaGFycysrKz0='), // Invalid
        _createMessage('msg17', 'https://example.com/image17.jpg'),
        _createMessage('msg18', '/uploads/images/file18.jpg'),
        _createMessage('msg19', 'https://example.com/image19.jpg'),
        _createMessage('msg20', '/uploads/images/file20.jpg'),
      ];

      mockRepository.setMockMessages(firstBatch);
      mockRepository.setMockMessagesForPagination(secondBatch);

      // Act: Load initial media
      final notifier = container.read(
        roomMediaProvider(
          (roomId: 'test-room', type: 'image'),
        ).notifier,
      );
      await notifier.loadInitial();

      // Load more
      await notifier.loadMore();

      final state = container.read(
        roomMediaProvider(
          (roomId: 'test-room', type: 'image'),
        ),
      );

      // Calculate renderable count
      final renderableCount = state.messages.where((msg) {
        final url = resolveFullUrl(msg.content);
        return url.isNotEmpty;
      }).length;

      // Assert: Count should match rendered items
      // ON UNFIXED CODE: This will FAIL because state.messages.length includes all messages
      // but some have invalid encrypted content
      expect(
        state.messages.length,
        equals(renderableCount),
        reason: 'BUG DETECTED: After pagination, state.messages.length (${state.messages.length}) '
                'does not match renderable count ($renderableCount). '
                'Invalid messages from both batches are counted but not rendered.',
      );

      // Document counterexamples
      final invalidMessages = state.messages.where((msg) {
        final url = resolveFullUrl(msg.content);
        return url.isEmpty;
      }).toList();

      print('\n=== COUNTEREXAMPLES (Pagination) ===');
      print('Total messages in state: ${state.messages.length}');
      print('Renderable messages: $renderableCount');
      print('Invalid messages across both batches: ${invalidMessages.length}');
      for (final msg in invalidMessages) {
        print('  - Message ${msg.id}: content="${msg.content.substring(0, 40)}..."');
      }
      print('====================================\n');
    });
  });
}

// Helper function to create test messages
Message _createMessage(String id, String content) {
  return Message(
    id: id,
    content: content,
    senderId: 'test-user',
    roomId: 'test-room',
    type: MessageType.image,
    createdAt: DateTime.now(),
  );
}

// Mock implementations
class MockChatRepository implements ChatRepository {
  List<Message> _messages = [];
  List<Message> _paginationMessages = [];
  bool _isFirstCall = true;

  void setMockMessages(List<Message> messages) {
    _messages = messages;
    _isFirstCall = true;
  }

  void setMockMessagesForPagination(List<Message> messages) {
    _paginationMessages = messages;
  }

  @override
  Future<PaginatedMessages> getRoomResources(
    String roomId, {
    String type = 'media',
    String cursor = '',
    int limit = 20,
  }) async {
    // Return first batch on initial load, second batch on pagination
    if (cursor.isEmpty && _isFirstCall) {
      _isFirstCall = false;
      return PaginatedMessages(
        messages: _messages,
        nextCursor: 'cursor-1',
        hasMore: _paginationMessages.isNotEmpty,
      );
    } else if (cursor == 'cursor-1') {
      return PaginatedMessages(
        messages: _paginationMessages,
        nextCursor: '',
        hasMore: false,
      );
    }
    return const PaginatedMessages(messages: [], nextCursor: '', hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockStorageService implements StorageService {
  @override
  Future<String?> read(String key) async {
    if (key == 'user_id') return 'test-user-id';
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCryptoService implements CryptoService {
  @override
  Future<String> decryptMessage(String encryptedContent, String publicKey) async {
    // Simulate decryption failure for Base64 content
    if (encryptedContent.length >= 40 && 
        (encryptedContent.contains('+') || 
         encryptedContent.contains('/') || 
         encryptedContent.contains('='))) {
      // Return the encrypted content unchanged (simulating decryption failure)
      return encryptedContent;
    }
    return encryptedContent;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPublicKeyCacheService implements PublicKeyCacheService {
  @override
  Future<String?> getPublicKey(String userId) async {
    return 'mock-public-key';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
