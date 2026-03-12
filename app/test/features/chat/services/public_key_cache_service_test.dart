import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/core/storage/local_db_service.dart';

/// Unit tests for PublicKeyCacheService.getPublicKeys batch method
/// 
/// These tests verify the following properties:
/// - Batch fetching returns map of user IDs to public keys
/// - Null values for unavailable keys
/// - Leverages existing getPublicKey caching
/// - Handles edge cases (empty list, single user, duplicates)
/// 
/// **Validates: Requirements 4.1, 4.2, 4.3**

// Mock implementations for testing
class MockChatRepository implements ChatRepository {
  final Map<String, String?> _mockKeys;
  final Map<String, int> _callCounts = {};

  MockChatRepository(this._mockKeys);

  @override
  Future<String?> getUserPublicKey(String userId) async {
    _callCounts[userId] = (_callCounts[userId] ?? 0) + 1;
    await Future.delayed(Duration(milliseconds: 10)); // Simulate network delay
    return _mockKeys[userId];
  }

  int getCallCount(String userId) => _callCounts[userId] ?? 0;

  // Implement other required methods with no-op
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLocalDbService implements LocalDbService {
  final Map<String, String?> _cache = {};

  @override
  Future<String?> getPublicKey(String userId) async {
    return _cache[userId];
  }

  @override
  Future<void> savePublicKey(String userId, String publicKey) async {
    _cache[userId] = publicKey;
  }

  @override
  Future<void> clearAllPublicKeys() async {
    _cache.clear();
  }

  // Implement other required methods with no-op
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PublicKeyCacheService.getPublicKeys -', () {

    test('**Validates: Requirements 4.1, 4.2** - should fetch all keys in parallel and return map', () async {
      // Arrange
      final mockRepo = MockChatRepository({
        'user1': 'key1',
        'user2': 'key2',
        'user3': 'key3',
      });
      final mockDb = MockLocalDbService();
      final service = PublicKeyCacheService(mockRepo, mockDb);
      final userIds = ['user1', 'user2', 'user3'];

      // Act
      final result = await service.getPublicKeys(userIds);

      // Assert
      expect(result, {
        'user1': 'key1',
        'user2': 'key2',
        'user3': 'key3',
      });
    });

    test('**Validates: Requirements 4.3, 4.4** - should return null for unavailable keys', () async {
      // Arrange
      final mockRepo = MockChatRepository({
        'user1': 'key1',
        'user2': null, // Unavailable
        'user3': 'key3',
      });
      final mockDb = MockLocalDbService();
      final service = PublicKeyCacheService(mockRepo, mockDb);
      final userIds = ['user1', 'user2', 'user3'];

      // Act
      final result = await service.getPublicKeys(userIds);

      // Assert
      expect(result, {
        'user1': 'key1',
        'user2': null,
        'user3': 'key3',
      });
    });

    test('**Validates: Requirements 4.2** - should leverage caching from getPublicKey', () async {
      // Arrange
      final mockRepo = MockChatRepository({
        'user1': 'key1',
        'user2': 'key2',
      });
      final mockDb = MockLocalDbService();
      final service = PublicKeyCacheService(mockRepo, mockDb);
      final userIds = ['user1', 'user2'];

      // First call - should fetch from API
      await service.getPublicKeys(userIds);

      // Second call - should use cache
      final result = await service.getPublicKeys(userIds);

      // Assert
      expect(result, {
        'user1': 'key1',
        'user2': 'key2',
      });
      // Verify API was called only once per user
      expect(mockRepo.getCallCount('user1'), 1);
      expect(mockRepo.getCallCount('user2'), 1);
    });

    test('should handle empty user list', () async {
      // Arrange
      final mockRepo = MockChatRepository({});
      final mockDb = MockLocalDbService();
      final service = PublicKeyCacheService(mockRepo, mockDb);

      // Act
      final result = await service.getPublicKeys([]);

      // Assert
      expect(result, {});
    });

    test('should handle single user', () async {
      // Arrange
      final mockRepo = MockChatRepository({'user1': 'key1'});
      final mockDb = MockLocalDbService();
      final service = PublicKeyCacheService(mockRepo, mockDb);
      final userIds = ['user1'];

      // Act
      final result = await service.getPublicKeys(userIds);

      // Assert
      expect(result, {'user1': 'key1'});
    });

    test('should handle all unavailable keys', () async {
      // Arrange
      final mockRepo = MockChatRepository({
        'user1': null,
        'user2': null,
        'user3': null,
      });
      final mockDb = MockLocalDbService();
      final service = PublicKeyCacheService(mockRepo, mockDb);
      final userIds = ['user1', 'user2', 'user3'];

      // Act
      final result = await service.getPublicKeys(userIds);

      // Assert
      expect(result, {
        'user1': null,
        'user2': null,
        'user3': null,
      });
    });

    test('should deduplicate concurrent requests', () async {
      // Arrange
      final mockRepo = MockChatRepository({
        'user1': 'key1',
        'user2': 'key2',
      });
      final mockDb = MockLocalDbService();
      final service = PublicKeyCacheService(mockRepo, mockDb);
      final userIds = ['user1', 'user1', 'user2']; // user1 appears twice

      // Act
      final result = await service.getPublicKeys(userIds);

      // Assert
      expect(result, {
        'user1': 'key1',
        'user2': 'key2',
      });
      // Verify API was called only once for user1 despite appearing twice
      expect(mockRepo.getCallCount('user1'), 1);
    });
  });
}
