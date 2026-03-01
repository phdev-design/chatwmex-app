import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/auth/repositories/auth_repository.dart';
import 'package:app/features/auth/models/auth_state.dart';

class AuthViewModel extends Notifier<AuthState> {
  late final AuthRepository _repository;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    return AuthState();
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.login(username, password);
      state = state.copyWith(isLoading: false, isAuthenticated: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> register(String username, String password, String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _repository.register(username, password, email);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final authViewModelProvider = NotifierProvider<AuthViewModel, AuthState>(AuthViewModel.new);
