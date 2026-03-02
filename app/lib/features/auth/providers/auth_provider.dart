import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:app/features/auth/repositories/auth_repository.dart';
import 'package:app/features/auth/models/auth_state.dart';
import 'package:app/core/notification/notification_service.dart';
import 'package:app/core/network/network_service.dart';

class AuthViewModel extends Notifier<AuthState> {
  late final AuthRepository _repository;
  late final NotificationService _notificationService;
  late final NetworkService _networkService;

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
      state = state.copyWith(isLoading: false, error: _parseError(e));
    }
  }

  Future<void> register(String username, String password, String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.register(username, password, email);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
    }
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
