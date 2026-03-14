import 'package:flutter/foundation.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/notification/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/backup/backup_manager.dart';

class AuthRepository {
  final NetworkService _networkService;
  final StorageService _storageService;
  final NotificationService _notificationService;
  final Ref _ref;

  AuthRepository(
    this._networkService,
    this._storageService,
    this._notificationService,
    this._ref,
  );

  Future<void> login(String username, String password) async {
    try {
      final response = await _networkService.client.post(
        '/users/login',
        data: {'username': username, 'password': password},
      );

      final data = response.data['data'];
      final token = data['token'];
      final userId = data['user_info']['id'];
      final usernameStr = data['user_info']['username'];
      final email = data['user_info']['email'] ?? '';
      final phoneNumber = data['user_info']['phone_number'] ?? '';
      final avatarUrl = data['user_info']['avatar_url'] ?? '';

      await _storageService.save('jwt_token', token);
      await _storageService.save('user_id', userId);
      await _storageService.save('username', usernameStr);
      await _storageService.save('email', email);
      await _storageService.save('phone_number', phoneNumber);
      await _storageService.save('avatar_url', avatarUrl);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> register(String username, String password, String email) async {
    await _networkService.client.post(
      '/users/register',
      data: {'username': username, 'password': password, 'email': email},
    );
  }

  Future<void> updatePublicKey(String publicKey) async {
    await _networkService.client.put(
      '/users/public_key',
      data: {'public_key': publicKey},
    );
  }

  /// 🔐 Key Recovery: 檢查伺服器端是否有金鑰備份
  /// 回傳 null 表示沒有備份，否則回傳 {encrypted_private_key, salt}
  Future<Map<String, String>?> getKeyBackup() async {
    try {
      final response = await _networkService.client.get('/users/key-backup');
      final data = response.data['data'];
      
      if (data == null || 
          data['encrypted_private_key'] == null || 
          data['salt'] == null) {
        return null;
      }
      
      return {
        'encrypted_private_key': data['encrypted_private_key'] as String,
        'salt': data['salt'] as String,
      };
    } catch (e) {
      debugPrint('Failed to get key backup: $e');
      return null;
    }
  }

  /// 🔐 Key Recovery: 上傳加密的私鑰備份到伺服器
  Future<void> uploadKeyBackup({
    required String encryptedPrivateKey,
    required String salt,
  }) async {
    await _networkService.client.post(
      '/users/key-backup',
      data: {
        'encrypted_private_key': encryptedPrivateKey,
        'salt': salt,
      },
    );
  }

  Future<void> logout() async {
    String? pendingDeviceId;
    try {
      // Unregister Device
      final deviceId = await _notificationService.getSubscriptionId();
      if (deviceId != null) {
        bool success = false;
        for (int i = 0; i < 3; i++) {
          try {
            await _networkService.client.delete('/devices/$deviceId');
            success = true;
            break;
          } catch (e) {
            debugPrint('Failed to unregister device (Attempt ${i + 1}): $e');
            if (i < 2) {
              await Future.delayed(const Duration(seconds: 1));
            }
          }
        }
        if (!success) {
          pendingDeviceId = deviceId;
        }
      }
    } catch (e) {
      debugPrint('Error during logout device unregistration: $e');
    } finally {
      // ✅ 只刪認證相關資料，不要 deleteAll()，避免清除 E2EE 私鑰
      await _storageService.delete('jwt_token');
      await _storageService.delete('user_id');
      await _storageService.delete('username');
      await _storageService.delete('email');
      await _storageService.delete('phone_number');
      await _storageService.delete('avatar_url');
      // Restore pending unregister if failed
      if (pendingDeviceId != null) {
        await _storageService.save(
          'pending_unregister_device_id',
          pendingDeviceId,
        );
      }
      // Detach Google Drive SignIn Session completely
      try {
        await _ref.read(backupManagerProvider.notifier).clearSession();
      } catch (e) {
        debugPrint('Error clearing Google Drive session on logout: $e');
      }
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  final notification = ref.watch(notificationServiceProvider);
  return AuthRepository(network, storage, notification, ref);
});