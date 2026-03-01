import 'dart:io';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/notification/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthRepository {
  final NetworkService _networkService;
  final StorageService _storageService;
  final NotificationService _notificationService;

  AuthRepository(this._networkService, this._storageService, this._notificationService);

  Future<void> login(String username, String password) async {
    try {
      final response = await _networkService.client.post('/users/login', data: {
        'username': username,
        'password': password,
      });
      
      final data = response.data['data'];
      final token = data['token'];
      final userId = data['user_info']['id'];
      final usernameStr = data['user_info']['username'];
      
      await _storageService.save('jwt_token', token);
      await _storageService.save('user_id', userId);
      await _storageService.save('username', usernameStr);

      // Register Device for Push Notifications
      final deviceId = await _notificationService.getSubscriptionId();
      if (deviceId != null) {
        await _registerDevice(deviceId);
      }
    } catch (e) {
      throw e;
    }
  }

  Future<void> _registerDevice(String deviceId) async {
    try {
      await _networkService.client.post('/devices/register', data: {
        'device_id': deviceId,
        'platform': Platform.isAndroid ? 'android' : 'ios',
      });
    } catch (e) {
      print('Failed to register device: $e');
    }
  }

  Future<void> register(String username, String password, String email) async {
    await _networkService.client.post('/users/register', data: {
      'username': username,
      'password': password,
      'email': email,
    });
  }

  Future<void> logout() async {
    try {
      // Unregister Device
      final deviceId = await _notificationService.getSubscriptionId();
      if (deviceId != null) {
        await _networkService.client.delete('/devices/$deviceId');
      }
    } catch (e) {
      print('Failed to unregister device: $e');
    } finally {
      await _storageService.deleteAll();
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  final notification = ref.watch(notificationServiceProvider);
  return AuthRepository(network, storage, notification);
});
