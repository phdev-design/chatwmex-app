class AuthState {
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;
  final bool isRegistered;

  AuthState({
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
    this.isRegistered = false,
  });

  AuthState copyWith({
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
    bool? isRegistered,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isRegistered: isRegistered ?? this.isRegistered,
    );
  }
}
