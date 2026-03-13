import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/providers/room_media_provider.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:app/models/message.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/core/storage/storage_service.dart';

/// Preservation Property Tests for Media Count Display Mismatch Fix
/// 
/// **Property 2: Preservation - Valid Messages Unchanged**
/// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
/// 
/// IMPORTANT: Follow observation-first methodology
/// These tests observe behavior on UNFIXED code for valid messages
/// (where resolveFullUrl returns non-empty strings)
/// 
/// EXPECTED OUTCOME: Tests PASS on unfixed code (confirms baseline behavior to preserve)
/// 
/// Property-based testing approach: Generate many test cases for stronger guarantees
/// that valid messages continue to be processed correctly after the fix.

void main() {
  group('Preservation Property Tests - Valid Messages Unchanged', () {
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

    /// **Property 2: Preservation - Plaintext URL Messages**
    /// **Validates: Requirements 3.1, 3.3**
    /// 
    /// Property: For all messages with plaintext URLs (http://, https://),
    /// resolveFullUrl returns non-empty string AND message is in state.messages
    /// AND count equals number of rendered items
    test('Property: Messages with plaintext URLs are included in state and rendered', () async {
      // Generate test cases: various plaintext URL formats
      final testCases = [
        'https://example.com/image.jpg',
        'http://example.com/photo.png',
        'https://cdn.example.com/media/file123.jpg',
        'http://localhost:8080/uploads/test.png',
        'https://example.com/path/to/image.jpg?query=param',
        'https://example.com/image.jpg#fragment',
      ];

      for (final url in testCases) {
        // Arrange: Create messages with plaintext URLs
        final messages = [
          _createMessage('msg1', url),
          _createMessage('msg2', 'https://example.com/other.jpg'),
          _createMessage('msg3', 'http://example.com/another.png'),
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

        // Assert: All messages should be in state
        expect(state.messages.length, equals(3),
            reason: 'All plaintext URL messages should be in state');

        // Assert: All messages should have non-empty URLs from resolveFullUrl
        for (final msg in state.messages) {
          final resolvedUrl = resolveFullUrl(msg.content);
          expect(resolvedUrl.isNotEmpty, isTrue,
              reason: 'resolveFullUrl should return non-empty for plaintext URL: ${msg.content}');
        }

        // Assert: Count matches rendered items
        final renderableCount = state.messages.where((msg) {
          final url = resolveFullUrl(msg.content);
          return url.isNotEmpty;
        }).length;

        expect(state.messages.length, equals(renderableCount),
            reason: 'Count should match rendered items for plaintext URLs');

        // Reset for next test case
        container.dispose();
        container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(mockRepository),
            storageServiceProvider.overrideWithValue(MockStorageService()),
            cryptoServiceProvider.overrideWithValue(MockCryptoService()),
            publicKeyCacheServiceProvider.overrideWithValue(MockPublicKeyCacheService()),
          ],
        );
      }
    });

    /// **Property 2: Preservation - Relative Path Messages**
    /// **Validates: Requirements 3.1, 3.3**
    /// 
    /// Property: For all messages with relative paths (/uploads/),
    /// resolveFullUrl returns non-empty string AND message is in state.messages
    /// AND count equals number of rendered items
    test('Property: Messages with relative paths are included in state and rendered', () async {
      // Generate test cases: various relative path formats
      final testCases = [
        '/uploads/images/file1.jpg',
        '/uploads/images/file2.png',
        '/uploads/media/photo.jpg',
        '/uploads/files/document.pdf',
        '/uploads/images/subfolder/image.jpg',
      ];

      for (final path in testCases) {
        // Arrange: Create messages with relative paths
        final messages = [
          _createMessage('msg1', path),
          _createMessage('msg2', '/uploads/images/other.jpg'),
          _createMessage('msg3', '/uploads/media/another.png'),
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

        // Assert: All messages should be in state
        expect(state.messages.length, equals(3),
            reason: 'All relative path messages should be in state');

        // Assert: All messages should have non-empty URLs from resolveFullUrl
        for (final msg in state.messages) {
          final resolvedUrl = resolveFullUrl(msg.content);
          expect(resolvedUrl.isNotEmpty, isTrue,
              reason: 'resolveFullUrl should return non-empty for relative path: ${msg.content}');
        }

        // Assert: Count matches rendered items
        final renderableCount = state.messages.where((msg) {
          final url = resolveFullUrl(msg.content);
          return url.isNotEmpty;
        }).length;

        expect(state.messages.length, equals(renderableCount),
            reason: 'Count should match rendered items for relative paths');

        // Reset for next test case
        container.dispose();
        container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(mockRepository),
            storageServiceProvider.overrideWithValue(MockStorageService()),
            cryptoServiceProvider.overrideWithValue(MockCryptoService()),
            publicKeyCacheServiceProvider.overrideWithValue(MockPublicKeyCacheService()),
          ],
        );
      }
    });

    /// **Property 2: Preservation - ObjectID Messages**
    /// **Validates: Requirements 3.1, 3.3**
    /// 
    /// Property: For all messages with MongoDB ObjectIDs (24-char hex),
    /// resolveFullUrl returns non-empty string AND message is in state.messages
    /// AND count equals number of rendered items
    test('Property: Messages with ObjectIDs are included in state and rendered', () async {
      // Generate test cases: various valid ObjectID formats
      final testCases = [
        '507f1f77bcf86cd799439011',
        '507f191e810c19729de860ea',
        '5f8d0d55b54764421b7156c9',
        'abcdef1234567890abcdef12',
        'ABCDEF1234567890ABCDEF12', // Uppercase
        'AbCdEf1234567890AbCdEf12', // Mixed case
      ];

      for (final objectId in testCases) {
        // Arrange: Create messages with ObjectIDs
        final messages = [
          _createMessage('msg1', objectId),
          _createMessage('msg2', '507f1f77bcf86cd799439011'),
          _createMessage('msg3', '507f191e810c19729de860ea'),
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

        // Assert: All messages should be in state
        expect(state.messages.length, equals(3),
            reason: 'All ObjectID messages should be in state');

        // Assert: All messages should have non-empty URLs from resolveFullUrl
        for (final msg in state.messages) {
          final resolvedUrl = resolveFullUrl(msg.content);
          expect(resolvedUrl.isNotEmpty, isTrue,
              reason: 'resolveFullUrl should return non-empty for ObjectID: ${msg.content}');
        }

        // Assert: Count matches rendered items
        final renderableCount = state.messages.where((msg) {
          final url = resolveFullUrl(msg.content);
          return url.isNotEmpty;
        }).length;

        expect(state.messages.length, equals(renderableCount),
            reason: 'Count should match rendered items for ObjectIDs');

        // Reset for next test case
        container.dispose();
        container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(mockRepository),
            storageServiceProvider.overrideWithValue(MockStorageService()),
            cryptoServiceProvider.overrideWithValue(MockCryptoService()),
            publicKeyCacheServiceProvider.overrideWithValue(MockPublicKeyCacheService()),
          ],
        );
      }
    });

    /// **Property 2: Preservation - Mixed Valid Message Types**
    /// **Validates: Requirements 3.1, 3.3**
    /// 
    /// Property: For any combination of valid message types (URLs, paths, ObjectIDs),
    /// all messages are in state.messages AND count equals number of rendered items
    test('Property: Mixed valid message types are all included and counted correctly', () async {
      // Generate test cases: combinations of valid message types
      final testCases = [
        // Case 1: Mix of URLs and paths
        [
          'https://example.com/image1.jpg',
          '/uploads/images/file2.jpg',
          'http://example.com/image3.png',
          '/uploads/media/file4.png',
        ],
        // Case 2: Mix of URLs and ObjectIDs
        [
          'https://example.com/image1.jpg',
          '507f1f77bcf86cd799439011',
          'http://example.com/image3.png',
          '507f191e810c19729de860ea',
        ],
        // Case 3: Mix of paths and ObjectIDs
        [
          '/uploads/images/file1.jpg',
          '507f1f77bcf86cd799439011',
          '/uploads/media/file3.png',
          '507f191e810c19729de860ea',
        ],
        // Case 4: Mix of all three types
        [
          'https://example.com/image1.jpg',
          '/uploads/images/file2.jpg',
          '507f1f77bcf86cd799439011',
          'http://example.com/image4.png',
          '/uploads/media/file5.png',
          '507f191e810c19729de860ea',
        ],
      ];

      for (final contents in testCases) {
        // Arrange: Create messages with mixed valid types
        final messages = contents
            .asMap()
            .entries
            .map((entry) => _createMessage('msg${entry.key + 1}', entry.value))
            .toList();

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

        // Assert: All messages should be in state
        expect(state.messages.length, equals(contents.length),
            reason: 'All valid messages should be in state');

        // Assert: All messages should have non-empty URLs from resolveFullUrl
        for (final msg in state.messages) {
          final resolvedUrl = resolveFullUrl(msg.content);
          expect(resolvedUrl.isNotEmpty, isTrue,
              reason: 'resolveFullUrl should return non-empty for valid content: ${msg.content}');
        }

        // Assert: Count matches rendered items
        final renderableCount = state.messages.where((msg) {
          final url = resolveFullUrl(msg.content);
          return url.isNotEmpty;
        }).length;

        expect(state.messages.length, equals(renderableCount),
            reason: 'Count should match rendered items for mixed valid types');

        // Reset for next test case
        container.dispose();
        container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(mockRepository),
            storageServiceProvider.overrideWithValue(MockStorageService()),
            cryptoServiceProvider.overrideWithValue(MockCryptoService()),
            publicKeyCacheServiceProvider.overrideWithValue(MockPublicKeyCacheService()),
          ],
        );
      }
    });

    /// **Property 2: Preservation - Pagination Without Duplicates**
    /// **Validates: Requirements 3.2**
    /// 
    /// Property: For pagination scenarios with valid messages,
    /// merged list has no duplicates AND all messages have valid URLs
    test('Property: Pagination merges messages correctly without duplicates', () async {
      // Generate test cases: different pagination scenarios
      final testScenarios = [
        // Scenario 1: No overlap between batches
        {
          'first': [
            'https://example.com/image1.jpg',
            '/uploads/images/file2.jpg',
            '507f1f77bcf86cd799439011',
          ],
          'second': [
            'https://example.com/image4.jpg',
            '/uploads/images/file5.jpg',
            '507f191e810c19729de860ea',
          ],
        },
        // Scenario 2: Intentional duplicate IDs (should be filtered)
        {
          'first': [
            'https://example.com/image1.jpg',
            '/uploads/images/file2.jpg',
          ],
          'second': [
            'https://example.com/image1.jpg', // Same ID as first batch
            '/uploads/images/file3.jpg',
          ],
        },
      ];

      for (final scenario in testScenarios) {
        final firstContents = scenario['first'] as List<String>;
        final secondContents = scenario['second'] as List<String>;

        // Arrange: Create first batch
        final firstBatch = firstContents
            .asMap()
            .entries
            .map((entry) => _createMessage('msg${entry.key + 1}', entry.value))
            .toList();

        // Create second batch (reuse IDs if content matches for duplicate test)
        final secondBatch = secondContents
            .asMap()
            .entries
            .map((entry) {
              // Check if this content exists in first batch
              final existingIndex = firstContents.indexOf(entry.value);
              if (existingIndex != -1) {
                // Reuse the same ID to test duplicate filtering
                return _createMessage('msg${existingIndex + 1}', entry.value);
              }
              return _createMessage('msg${firstContents.length + entry.key + 1}', entry.value);
            })
            .toList();

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

        // Assert: No duplicate message IDs
        final messageIds = state.messages.map((m) => m.id).toList();
        final uniqueIds = messageIds.toSet();
        expect(messageIds.length, equals(uniqueIds.length),
            reason: 'Pagination should not create duplicate messages');

        // Assert: All messages have valid URLs
        for (final msg in state.messages) {
          final resolvedUrl = resolveFullUrl(msg.content);
          expect(resolvedUrl.isNotEmpty, isTrue,
              reason: 'All paginated messages should have valid URLs: ${msg.content}');
        }

        // Assert: Count matches rendered items
        final renderableCount = state.messages.where((msg) {
          final url = resolveFullUrl(msg.content);
          return url.isNotEmpty;
        }).length;

        expect(state.messages.length, equals(renderableCount),
            reason: 'Count should match rendered items after pagination');

        // Reset for next test case
        container.dispose();
        container = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(mockRepository),
            storageServiceProvider.overrideWithValue(MockStorageService()),
            cryptoServiceProvider.overrideWithValue(MockCryptoService()),
            publicKeyCacheServiceProvider.overrideWithValue(MockPublicKeyCacheService()),
          ],
        );
      }
    });

    /// **Property 2: Preservation - Month-Based Grouping**
    /// **Validates: Requirements 3.4**
    /// 
    /// Property: For valid messages, month-based grouping works correctly
    /// and all grouped messages have valid URLs
    test('Property: Month-based grouping works correctly for valid messages', () async {
      // Arrange: Create messages with different dates
      final now = DateTime.now();
      final lastMonth = DateTime(now.year, now.month - 1, 15);
      final twoMonthsAgo = DateTime(now.year, now.month - 2, 20);

      final messages = [
        _createMessageWithDate('msg1', 'https://example.com/image1.jpg', now),
        _createMessageWithDate('msg2', '/uploads/images/file2.jpg', now),
        _createMessageWithDate('msg3', '507f1f77bcf86cd799439011', lastMonth),
        _createMessageWithDate('msg4', 'https://example.com/image4.jpg', lastMonth),
        _createMessageWithDate('msg5', '/uploads/images/file5.jpg', twoMonthsAgo),
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

      // Get grouped messages
      final grouped = notifier.groupedMessages;

      // Assert: Grouping should work (at least 1 group, likely 3)
      expect(grouped.isNotEmpty, isTrue,
          reason: 'Messages should be grouped by month');

      // Assert: All messages in all groups have valid URLs
      for (final group in grouped.values) {
        for (final msg in group) {
          final resolvedUrl = resolveFullUrl(msg.content);
          expect(resolvedUrl.isNotEmpty, isTrue,
              reason: 'All grouped messages should have valid URLs: ${msg.content}');
        }
      }

      // Assert: Total messages in groups equals state.messages.length
      final totalInGroups = grouped.values.fold<int>(0, (sum, group) => sum + group.length);
      expect(totalInGroups, equals(state.messages.length),
          reason: 'All messages should be included in grouping');

      // Assert: Count matches rendered items
      final renderableCount = state.messages.where((msg) {
        final url = resolveFullUrl(msg.content);
        return url.isNotEmpty;
      }).length;

      expect(state.messages.length, equals(renderableCount),
          reason: 'Count should match rendered items for grouped messages');
    });

    /// **Property 2: Preservation - Large Batch of Valid Messages**
    /// **Validates: Requirements 3.1, 3.3**
    /// 
    /// Property: For large batches of valid messages (stress test),
    /// all messages are processed correctly and count matches rendered items
    test('Property: Large batch of valid messages processed correctly', () async {
      // Generate a large batch of valid messages (50 messages)
      final messages = <Message>[];
      for (int i = 0; i < 50; i++) {
        final contentType = i % 3;
        String content;
        switch (contentType) {
          case 0:
            content = 'https://example.com/image$i.jpg';
            break;
          case 1:
            content = '/uploads/images/file$i.jpg';
            break;
          case 2:
            // Generate valid ObjectID (24 hex chars)
            content = '507f1f77bcf86cd79943${i.toString().padLeft(4, '0')}';
            break;
          default:
            content = 'https://example.com/default.jpg';
        }
        messages.add(_createMessage('msg$i', content));
      }

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

      // Assert: All messages should be in state
      expect(state.messages.length, equals(50),
          reason: 'All 50 valid messages should be in state');

      // Assert: All messages should have non-empty URLs from resolveFullUrl
      for (final msg in state.messages) {
        final resolvedUrl = resolveFullUrl(msg.content);
        expect(resolvedUrl.isNotEmpty, isTrue,
            reason: 'resolveFullUrl should return non-empty for valid content: ${msg.content}');
      }

      // Assert: Count matches rendered items
      final renderableCount = state.messages.where((msg) {
        final url = resolveFullUrl(msg.content);
        return url.isNotEmpty;
      }).length;

      expect(state.messages.length, equals(renderableCount),
          reason: 'Count should match rendered items for large batch');
    });
  });
}

// Helper functions to create test messages
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

Message _createMessageWithDate(String id, String content, DateTime createdAt) {
  return Message(
    id: id,
    content: content,
    senderId: 'test-user',
    roomId: 'test-room',
    type: MessageType.image,
    createdAt: createdAt,
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
  Future<String> decryptMessage(
    String encryptedContent,
    String publicKey, {
    String? messageId,
    String? senderId,
  }) async {
    // For preservation tests, we simulate successful decryption for valid content
    // and return the content unchanged (since we're testing with plaintext content)
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
