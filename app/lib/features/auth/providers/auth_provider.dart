import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:app/features/auth/repositories/auth_repository.dart';
import 'package:app/features/auth/models/auth_state.dart';
import 'package:app/core/notification/notification_service.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/features/chat/providers/room_list_provider.dart';
import 'package:shared_preference_app_group/shared_preference_app_group.dart';

class AuthViewModel extends Notifier<AuthState> {
  late AuthRepository _repository;
  late NotificationService _notificationService;
  late NetworkService _networkService;

  // ⚠️ 替換成你在 Xcode 中設定的 App Group ID
  static const String _appGroupId = 'group.com.phdev.chat2mex';

  // 🔒 Mutex to prevent concurrent token refresh attempts
  bool _isRefreshing = false;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    _notificationService = ref.watch(notificationServiceProvider);
    _networkService = ref.watch(networkServiceProvider);
    return AuthState();
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.login(username, password);
      final crypto = ref.read(cryptoServiceProvider);
      final storage = ref.read(storageServiceProvider);
      
      final userId = await storage.read('user_id') ?? '';
      
      // ✅ 讀取 Token
      final token = await storage.read('jwt_token') ?? ''; 

      // 🔐 E2EE Key Recovery: 攔截私鑰遺失異常
      try {
        final pubKey = await crypto.initialize(userId: userId);
        await _repository.updatePublicKey(pubKey);
      } on PrivateKeyNotFoundException catch (e) {
        // 私鑰遺失，設定狀態以觸發 UI 流程
        state = state.copyWith(
          isLoading: false,
          needsKeyRecovery: true,
          missingKeyUserId: e.userId,
        );
        return;
      }

      // 登入後清除舊的 public key 快取，避免用錯誤的 key 解密訊息
      await ref.read(publicKeyCacheServiceProvider).clearAllCache();

      // ✅ 確保 room list 是全新的（防止切換帳號時看到舊對話）
      ref.invalidate(roomListViewModelProvider);

      // ✅ 新增：將 Token 同步到 App Group 供 iOS Notification Extension 讀取
      if (Platform.isIOS && token.isNotEmpty) {
        try {
          await SharedPreferenceAppGroup.setAppGroup(_appGroupId);
          await SharedPreferenceAppGroup.setString('jwt_token', token);
          debugPrint('✅ App Group token synced successfully');
        } catch (e) {
          debugPrint('❌ App Group token sync failed: $e');
        }
      }

      try {
        await _notificationService.initOneSignal(
          "88247551-a540-4ffc-89aa-e6ea9478b7be",
        );
        final subscriptionId = await _notificationService.getSubscriptionId();
        if (subscriptionId != null) {
          await _networkService.client.post(
            '/devices/register',
            data: {
              'device_id': subscriptionId,
              'platform': Platform.isAndroid ? 'android' : 'ios',
            },
          );
        }
        await _notificationService.handlePendingNavigation();
        state = state.copyWith(isLoading: false, isAuthenticated: true);
      } catch (e) {
        debugPrint('Post-login device registration warning: $e');
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          error: '登入成功，但推播通知註冊失敗，可能無法收到通知：${_parseError(e)}',
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
    }
  }

  Future<void> register(String username, String password, String email) async {
    state = state.copyWith(isLoading: true, error: null, isRegistered: false);
    try {
      await _repository.register(username, password, email);
      state = state.copyWith(isLoading: false, isRegistered: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
    }
  }

  // ✅ 新增：登出方法，負責清除狀態與 App Group 內的 Token
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      // 若 AuthRepository 有實作 logout()，請取消下方註解：
      // await _repository.logout();
      
      final storage = ref.read(storageServiceProvider);
      await storage.delete('jwt_token');
      await storage.delete('user_id');

      // ✅ 清除 iOS App Group 的 Token，避免登出後 Extension 還能打 API
      if (Platform.isIOS) {
        try {
          await SharedPreferenceAppGroup.setAppGroup(_appGroupId);
          await SharedPreferenceAppGroup.remove('jwt_token');
          debugPrint('✅ App Group token cleared successfully');
        } catch (e) {
          debugPrint('❌ App Group token clear failed: $e');
        }
      }

      state = AuthState(); // 重置為未登入狀態
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
    }
  }

  /// Refreshes the JWT token when it expires
  /// Returns true if refresh succeeds, false otherwise
  /// Uses a lock to prevent concurrent refresh attempts
  Future<bool> refreshToken() async {
    // 🔒 Prevent concurrent refresh attempts
    if (_isRefreshing) {
      debugPrint('⏳ Token refresh already in progress, waiting...');
      // Wait for the ongoing refresh to complete
      while (_isRefreshing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      // Check if we now have a valid token
      final storage = ref.read(storageServiceProvider);
      final token = await storage.read('jwt_token');
      return token != null && token.isNotEmpty;
    }

    _isRefreshing = true;
    try {
      debugPrint('🔄 Attempting to refresh JWT token...');
      
      final storage = ref.read(storageServiceProvider);
      final currentToken = await storage.read('jwt_token');
      
      if (currentToken == null || currentToken.isEmpty) {
        debugPrint('❌ No token found to refresh');
        return false;
      }

      // Make POST request to refresh endpoint with current token in body
      final response = await _networkService.client.post(
        '/auth/refresh',
        data: {
          'token': currentToken,
        },
      );

      // Extract new token from response
      final data = response.data['data'];
      final newToken = data['token'] as String?;
      
      if (newToken == null || newToken.isEmpty) {
        debugPrint('❌ Token refresh failed: no token in response');
        return false;
      }

      // Save new token to storage
      await storage.save('jwt_token', newToken);
      
      // ✅ Update App Group token for iOS notification extension
      if (Platform.isIOS) {
        try {
          await SharedPreferenceAppGroup.setAppGroup(_appGroupId);
          await SharedPreferenceAppGroup.setString('jwt_token', newToken);
          debugPrint('✅ App Group token updated after refresh');
        } catch (e) {
          debugPrint('❌ App Group token update failed: $e');
        }
      }

      debugPrint('✅ Token refresh successful');
      return true;
    } catch (e) {
      debugPrint('❌ Token refresh failed: $e');
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  // 🔐 E2EE Key Recovery: 從雲端還原金鑰
  Future<void> recoverKeyFromBackup(String password) async {
    if (state.missingKeyUserId == null) {
      state = state.copyWith(error: '無法識別用戶 ID');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final crypto = ref.read(cryptoServiceProvider);
      final storage = ref.read(storageServiceProvider);
      
      // 1. 從後端取得加密的私鑰
      final keyBackup = await _repository.getKeyBackup();
      
      if (keyBackup == null) {
        state = state.copyWith(
          isLoading: false,
          error: '伺服器上沒有金鑰備份，請選擇「生成新金鑰」',
        );
        return;
      }
      
      final encryptedKeyBase64 = keyBackup['encrypted_private_key']!;
      final saltBase64 = keyBackup['salt']!;
      
      // 2. 使用密碼解密私鑰
      final decryptedKey = await crypto.decryptPrivateKeyFromBackup(
        encryptedKeyBase64,
        saltBase64,
        password,
      );
      
      // 3. 還原私鑰到本地儲存
      await crypto.restorePrivateKey(decryptedKey);
      
      // 4. 重新初始化並繼續登入流程
      final pubKey = await crypto.initialize(userId: state.missingKeyUserId!);
      await _repository.updatePublicKey(pubKey);

      // 5. 清除舊的 public key 快取
      await ref.read(publicKeyCacheServiceProvider).clearAllCache();

      // 6. 確保 room list 是全新的
      ref.invalidate(roomListViewModelProvider);

      // 7. 同步 Token 到 App Group
      final token = await storage.read('jwt_token') ?? '';
      if (Platform.isIOS && token.isNotEmpty) {
        try {
          await SharedPreferenceAppGroup.setAppGroup(_appGroupId);
          await SharedPreferenceAppGroup.setString('jwt_token', token);
          debugPrint('✅ App Group token synced successfully');
        } catch (e) {
          debugPrint('❌ App Group token sync failed: $e');
        }
      }

      // 8. 註冊推播通知
      try {
        await _notificationService.initOneSignal(
          "88247551-a540-4ffc-89aa-e6ea9478b7be",
        );
        final subscriptionId = await _notificationService.getSubscriptionId();
        if (subscriptionId != null) {
          await _networkService.client.post(
            '/devices/register',
            data: {
              'device_id': subscriptionId,
              'platform': Platform.isAndroid ? 'android' : 'ios',
            },
          );
        }
        await _notificationService.handlePendingNavigation();
      } catch (e) {
        debugPrint('Post-login device registration warning: $e');
      }
      
      state = state.copyWith(
        isLoading: false,
        needsKeyRecovery: false,
        missingKeyUserId: null,
        isAuthenticated: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString().contains('incorrect') || e.toString().contains('corrupted')
            ? '密碼錯誤或備份檔案損壞，請重試'
            : _parseError(e),
      );
    }
  }

  // 🔐 E2EE Key Recovery: 強制生成新金鑰
  Future<void> forceGenerateNewKey() async {
    if (state.missingKeyUserId == null) {
      state = state.copyWith(error: '無法識別用戶 ID');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final crypto = ref.read(cryptoServiceProvider);
      final storage = ref.read(storageServiceProvider);
      
      // 1. 標記所有未解密訊息為永久無法復原
      await LocalDbService().markAllUndecryptedAsUnrecoverable();
      
      // 2. 強制生成新金鑰
      final pubKey = await crypto.initialize(
        userId: state.missingKeyUserId!,
        forceGenerate: true,
      );
      await _repository.updatePublicKey(pubKey);

      // 3. 登入後清除舊的 public key 快取
      await ref.read(publicKeyCacheServiceProvider).clearAllCache();

      // 4. 確保 room list 是全新的
      ref.invalidate(roomListViewModelProvider);

      // 5. 同步 Token 到 App Group
      final token = await storage.read('jwt_token') ?? '';
      if (Platform.isIOS && token.isNotEmpty) {
        try {
          await SharedPreferenceAppGroup.setAppGroup(_appGroupId);
          await SharedPreferenceAppGroup.setString('jwt_token', token);
          debugPrint('✅ App Group token synced successfully');
        } catch (e) {
          debugPrint('❌ App Group token sync failed: $e');
        }
      }

      // 6. 註冊推播通知
      try {
        await _notificationService.initOneSignal(
          "88247551-a540-4ffc-89aa-e6ea9478b7be",
        );
        final subscriptionId = await _notificationService.getSubscriptionId();
        if (subscriptionId != null) {
          await _networkService.client.post(
            '/devices/register',
            data: {
              'device_id': subscriptionId,
              'platform': Platform.isAndroid ? 'android' : 'ios',
            },
          );
        }
        await _notificationService.handlePendingNavigation();
      } catch (e) {
        debugPrint('Post-login device registration warning: $e');
      }

      state = state.copyWith(
        isLoading: false,
        needsKeyRecovery: false,
        needsKeyBackup: true, // 🆕 提示用戶設定金鑰備份
        missingKeyUserId: null,
        isAuthenticated: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _parseError(e),
      );
    }
  }

  void resetRegistered() {
    state = state.copyWith(isRegistered: false);
  }

  String _parseError(Object e) {
    if (e is DioException) {
      if (e.response != null && e.response?.data is Map) {
        return e.response?.data['message'] ?? 'An error occurred';
      }
      return e.message ?? 'Network error';
    }
    return e.toString();
  }
}

final authViewModelProvider = NotifierProvider<AuthViewModel, AuthState>(
  AuthViewModel.new,
);