class AuthState {
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;
  final bool isRegistered;
  final bool needsKeyRecovery;
  final String? missingKeyUserId;
  final bool needsKeyBackup; // 🆕 提示用戶設定金鑰備份

  AuthState({
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
    this.isRegistered = false,
    this.needsKeyRecovery = false,
    this.missingKeyUserId,
    this.needsKeyBackup = false,
  });

  AuthState copyWith({
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
    bool? isRegistered,
    bool? needsKeyRecovery,
    Object? missingKeyUserId = const _Undefined(),
    bool? needsKeyBackup,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isRegistered: isRegistered ?? this.isRegistered,
      needsKeyRecovery: needsKeyRecovery ?? this.needsKeyRecovery,
      missingKeyUserId: missingKeyUserId is _Undefined 
          ? this.missingKeyUserId 
          : missingKeyUserId as String?,
      needsKeyBackup: needsKeyBackup ?? this.needsKeyBackup,
    );
  }
}

class _Undefined {
  const _Undefined();
}
