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
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/features/chat/providers/room_list_provider.dart';
import 'package:shared_preference_app_group/shared_preference_app_group.dart';

class AuthViewModel extends Notifier<AuthState> {
  late AuthRepository _repository;
  late NotificationService _notificationService;
  late NetworkService _networkService;

  // ⚠️ 替換成你在 Xcode 中設定的 App Group ID
  static const String _appGroupId = 'group.com.phdev.chat2mex';

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

      final pubKey = await crypto.initialize(userId: userId);
      await _repository.updatePublicKey(pubKey);

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