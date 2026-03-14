import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:app/features/auth/providers/auth_provider.dart';
import 'package:app/features/auth/repositories/auth_repository.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/notification/notification_service.dart';

@GenerateMocks([StorageService, NetworkService, AuthRepository, NotificationService])
import 'refresh_token_unit_test.mocks.dart';

/// Unit Tests for Task 6.1: refreshToken() method
/// **Validates: Requirements 2.1, 2.2, 2.3, 2.4**
/// 
/// Tests the refreshToken() method in AuthViewModel with various scenarios:
/// - Successful token refresh with mock backend response
/// - Token refresh failure (401, 403, network error)
/// - Concurrent refresh attempts (verify refresh lock works)
/// - Token storage update after successful refresh
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unit Tests - refreshToken() method', () {
    late MockStorageService mockStorage;
    late MockNetworkService mockNetwork;
    late MockAuthRepository mockAuthRepo;
    late MockNotificationService mockNotification;
    late ProviderContainer container;

    setUp(() {
      mockStorage = MockStorageService();
      mockNetwork = MockNetworkService();
      mockAuthRepo = MockAuthRepository();
      mockNotification = MockNotificationService();

      container = ProviderContainer(
        overrides: [
          storageServiceProvider.overrideWithValue(mockStorage),
          networkServiceProvider.overrideWithValue(mockNetwork),
          authRepositoryProvider.overrideWithValue(mockAuthRepo),
          notificationServiceProvider.overrideWithValue(mockNotification),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('6.1.1: Successful token refresh with mock backend response', () async {
      // Arrange
      const oldToken = 'old_jwt_token_123';
      const newToken = 'new_jwt_token_456';
      
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => oldToken);
      when(mockStorage.save('jwt_token', newToken)).thenAnswer((_) async {});
      
      final mockDio = MockDio();
      when(mockNetwork.client).thenReturn(mockDio);
      
      when(mockDio.post(
        '/auth/refresh',
        options: anyNamed('options'),
      )).thenAnswer((_) async => Response(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        statusCode: 200,
        data: {
          'data': {
            'token': newToken,
          },
        },
      ));

      // Act
      final viewModel = container.read(authViewModelProvider.notifier);
      final result = await viewModel.refreshToken();

      // Assert
      expect(result, isTrue, reason: 'Token refresh should succeed');
      verify(mockStorage.read('jwt_token')).called(1);
      verify(mockStorage.save('jwt_token', newToken)).called(1);
      verify(mockDio.post('/auth/refresh', options: anyNamed('options'))).called(1);
    });

    test('6.1.2: Token refresh failure - 401 Unauthorized', () async {
      // Arrange
      const oldToken = 'expired_token';
      
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => oldToken);
      
      final mockDio = MockDio();
      when(mockNetwork.client).thenReturn(mockDio);
      
      when(mockDio.post(
        '/auth/refresh',
        options: anyNamed('options'),
      )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          statusCode: 401,
        ),
      ));

      // Act
      final viewModel = container.read(authViewModelProvider.notifier);
      final result = await viewModel.refreshToken();

      // Assert
      expect(result, isFalse, reason: 'Token refresh should fail with 401');
      verify(mockStorage.read('jwt_token')).called(1);
      verifyNever(mockStorage.save(any, any));
    });

    test('6.1.3: Token refresh failure - 403 Forbidden', () async {
      // Arrange
      const oldToken = 'invalid_token';
      
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => oldToken);
      
      final mockDio = MockDio();
      when(mockNetwork.client).thenReturn(mockDio);
      
      when(mockDio.post(
        '/auth/refresh',
        options: anyNamed('options'),
      )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          statusCode: 403,
        ),
      ));

      // Act
      final viewModel = container.read(authViewModelProvider.notifier);
      final result = await viewModel.refreshToken();

      // Assert
      expect(result, isFalse, reason: 'Token refresh should fail with 403');
      verify(mockStorage.read('jwt_token')).called(1);
      verifyNever(mockStorage.save(any, any));
    });

    test('6.1.4: Token refresh failure - Network error', () async {
      // Arrange
      const oldToken = 'valid_token';
      
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => oldToken);
      
      final mockDio = MockDio();
      when(mockNetwork.client).thenReturn(mockDio);
      
      when(mockDio.post(
        '/auth/refresh',
        options: anyNamed('options'),
      )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timeout',
      ));

      // Act
      final viewModel = container.read(authViewModelProvider.notifier);
      final result = await viewModel.refreshToken();

      // Assert
      expect(result, isFalse, reason: 'Token refresh should fail with network error');
      verify(mockStorage.read('jwt_token')).called(1);
      verifyNever(mockStorage.save(any, any));
    });

    test('6.1.5: Token refresh failure - No token found', () async {
      // Arrange
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => null);

      // Act
      final viewModel = container.read(authViewModelProvider.notifier);
      final result = await viewModel.refreshToken();

      // Assert
      expect(result, isFalse, reason: 'Token refresh should fail when no token exists');
      verify(mockStorage.read('jwt_token')).called(1);
      verifyNever(mockStorage.save(any, any));
    });

    test('6.1.6: Token refresh failure - Empty token', () async {
      // Arrange
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => '');

      // Act
      final viewModel = container.read(authViewModelProvider.notifier);
      final result = await viewModel.refreshToken();

      // Assert
      expect(result, isFalse, reason: 'Token refresh should fail when token is empty');
      verify(mockStorage.read('jwt_token')).called(1);
      verifyNever(mockStorage.save(any, any));
    });

    test('6.1.7: Token storage update after successful refresh', () async {
      // Arrange
      const oldToken = 'old_token';
      const newToken = 'new_refreshed_token';
      
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => oldToken);
      when(mockStorage.save('jwt_token', newToken)).thenAnswer((_) async {});
      
      final mockDio = MockDio();
      when(mockNetwork.client).thenReturn(mockDio);
      
      when(mockDio.post(
        '/auth/refresh',
        options: anyNamed('options'),
      )).thenAnswer((_) async => Response(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        statusCode: 200,
        data: {
          'data': {
            'token': newToken,
          },
        },
      ));

      // Act
      final viewModel = container.read(authViewModelProvider.notifier);
      final result = await viewModel.refreshToken();

      // Assert
      expect(result, isTrue);
      verify(mockStorage.save('jwt_token', newToken)).called(1);
      
      // Verify the new token is saved correctly
      final capturedToken = verify(mockStorage.save('jwt_token', captureAny)).captured.single;
      expect(capturedToken, equals(newToken));
    });

    test('6.1.8: Concurrent refresh attempts - Refresh lock prevents multiple calls', () async {
      // Arrange
      const oldToken = 'token_for_concurrent_test';
      const newToken = 'new_token_concurrent';
      
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => oldToken);
      when(mockStorage.save('jwt_token', newToken)).thenAnswer((_) async {});
      
      final mockDio = MockDio();
      when(mockNetwork.client).thenReturn(mockDio);
      
      // Simulate slow refresh (500ms delay)
      when(mockDio.post(
        '/auth/refresh',
        options: anyNamed('options'),
      )).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 500));
        return Response(
          requestOptions: RequestOptions(path: '/auth/refresh'),
          statusCode: 200,
          data: {
            'data': {
              'token': newToken,
            },
          },
        );
      });

      // Act - Trigger 3 concurrent refresh attempts
      final viewModel = container.read(authViewModelProvider.notifier);
      final results = await Future.wait([
        viewModel.refreshToken(),
        viewModel.refreshToken(),
        viewModel.refreshToken(),
      ]);

      // Assert
      expect(results, everyElement(isTrue), reason: 'All refresh attempts should succeed');
      
      // Verify that only ONE actual refresh call was made (refresh lock worked)
      verify(mockDio.post('/auth/refresh', options: anyNamed('options'))).called(1);
      
      // Verify token was saved only once
      verify(mockStorage.save('jwt_token', newToken)).called(1);
    });

    test('6.1.9: Token refresh with invalid response format', () async {
      // Arrange
      const oldToken = 'valid_token';
      
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => oldToken);
      
      final mockDio = MockDio();
      when(mockNetwork.client).thenReturn(mockDio);
      
      // Response missing 'data.token' field
      when(mockDio.post(
        '/auth/refresh',
        options: anyNamed('options'),
      )).thenAnswer((_) async => Response(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        statusCode: 200,
        data: {
          'data': {
            // Missing 'token' field
          },
        },
      ));

      // Act
      final viewModel = container.read(authViewModelProvider.notifier);
      final result = await viewModel.refreshToken();

      // Assert
      expect(result, isFalse, reason: 'Token refresh should fail with invalid response format');
      verify(mockStorage.read('jwt_token')).called(1);
      verifyNever(mockStorage.save(any, any));
    });

    test('6.1.10: Token refresh with empty token in response', () async {
      // Arrange
      const oldToken = 'valid_token';
      
      when(mockStorage.read('jwt_token')).thenAnswer((_) async => oldToken);
      
      final mockDio = MockDio();
      when(mockNetwork.client).thenReturn(mockDio);
      
      when(mockDio.post(
        '/auth/refresh',
        options: anyNamed('options'),
      )).thenAnswer((_) async => Response(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        statusCode: 200,
        data: {
          'data': {
            'token': '', // Empty token
          },
        },
      ));

      // Act
      final viewModel = container.read(authViewModelProvider.notifier);
      final result = await viewModel.refreshToken();

      // Assert
      expect(result, isFalse, reason: 'Token refresh should fail when response token is empty');
      verify(mockStorage.read('jwt_token')).called(1);
      verifyNever(mockStorage.save(any, any));
    });
  });
}

// Mock Dio class for testing
class MockDio extends Mock implements Dio {}
