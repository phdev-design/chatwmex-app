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

class AuthViewModel extends Notifier<AuthState> {
  late AuthRepository _repository;
  late NotificationService _notificationService;
  late NetworkService _networkService;

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
      final pubKey = await crypto.initialize(userId: userId);
      await _repository.updatePublicKey(pubKey);

      // 登入後清除舊的 public key 快取，避免用錯誤的 key 解密訊息
      await ref.read(publicKeyCacheServiceProvider).clearAllCache();

      // ✅ 新增：確保 room list 是全新的（防止切換帳號時看到舊對話）
      ref.invalidate(roomListViewModelProvider);

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
        print('Post-login device registration warning: $e');
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

  void resetRegistered() {
    state = state.copyWith(isRegistered: false);
  }

  String _parseError(Object e) {
    if (e is DioException) {
      if (e.response != null && e.response?.data is Map) {
        // Assuming backend returns { "message": "error message" } or similar
        // Based on backend implementation: response.Error(c, code, message)
        // Usually returns { "code": ..., "message": ... }
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
