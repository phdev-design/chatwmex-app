import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/profile/repositories/profile_repository.dart';
import 'package:dio/dio.dart';

class ProfileState {
  final bool isLoading;
  final String? error;
  final String? successMessage;

  const ProfileState({this.isLoading = false, this.error, this.successMessage});

  ProfileState copyWith({
    bool? isLoading,
    String? error,
    String? successMessage,
  }) {
    return ProfileState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
    );
  }
}

class ProfileViewModel extends Notifier<ProfileState> {
  late final ProfileRepository _repository;

  @override
  ProfileState build() {
    _repository = ref.watch(profileRepositoryProvider);
    return const ProfileState();
  }

  Future<void> updateProfile(String email, String phoneNumber) async {
    state = state.copyWith(isLoading: true, error: null, successMessage: null);
    try {
      await _repository.updateProfile(email, phoneNumber);
      state = state.copyWith(
        isLoading: false,
        successMessage: "Profile updated successfully",
      );
    } catch (e) {
      String errorMessage = "Failed to update profile";
      if (e is DioException && e.response?.data is Map) {
        errorMessage = e.response?.data['message'] ?? errorMessage;
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
    }
  }

  void clearMessages() {
    state = state.copyWith(error: null, successMessage: null);
  }
}

final profileViewModelProvider =
    NotifierProvider<ProfileViewModel, ProfileState>(ProfileViewModel.new);
