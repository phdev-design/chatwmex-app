import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/profile/repositories/profile_repository.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

class ProfileState {
  final bool isLoading;
  final String? error;
  final String? successMessage;
  final String username;
  final String email;
  final String phoneNumber;
  final String firstName;
  final String lastName;
  final String bio;
  final String avatarUrl;

  const ProfileState({
    this.isLoading = false,
    this.error,
    this.successMessage,
    this.username = '',
    this.email = '',
    this.phoneNumber = '',
    this.firstName = '',
    this.lastName = '',
    this.bio = '',
    this.avatarUrl = '',
  });

  ProfileState copyWith({
    bool? isLoading,
    String? error,
    String? successMessage,
    String? username,
    String? email,
    String? phoneNumber,
    String? firstName,
    String? lastName,
    String? bio,
    String? avatarUrl,
    bool clearError = false,
    bool clearSuccessMessage = false,
  }) {
    return ProfileState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      successMessage: clearSuccessMessage
          ? null
          : (successMessage ?? this.successMessage),
      username: username ?? this.username,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

class ProfileViewModel extends Notifier<ProfileState> {
  late ProfileRepository _repository;
  late StorageService _storage;

  @override
  ProfileState build() {
    _repository = ref.watch(profileRepositoryProvider);
    _storage = ref.watch(storageServiceProvider);
    return const ProfileState();
  }

  Future<void> loadProfile() async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSuccessMessage: true,
    );
    try {
      final user = await _repository.getUserProfile();
      await _storage.save('user_id', user.id);
      await _storage.save('username', user.username);
      await _storage.save('email', user.email);
      await _storage.save('phone_number', user.phoneNumber ?? '');
      await _storage.save('first_name', user.firstName ?? '');
      await _storage.save('last_name', user.lastName ?? '');
      await _storage.save('bio', user.bio ?? '');
      await _storage.save('avatar_url', user.avatarUrl ?? '');
      state = state.copyWith(
        isLoading: false,
        username: user.username,
        email: user.email,
        phoneNumber: user.phoneNumber ?? '',
        firstName: user.firstName ?? '',
        lastName: user.lastName ?? '',
        bio: user.bio ?? '',
        avatarUrl: user.avatarUrl ?? '',
      );
    } catch (e) {
      String errorMessage = 'Failed to load profile';
      if (e is DioException && e.response?.data is Map) {
        errorMessage = e.response?.data['message'] ?? errorMessage;
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
    }
  }

  Future<void> updateProfile(
    String email,
    String phoneNumber,
    String firstName,
    String lastName,
    String bio,
  ) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSuccessMessage: true,
    );
    try {
      await _repository.updateProfile(
        email,
        phoneNumber,
        firstName,
        lastName,
        bio,
      );
      await _storage.save('email', email);
      await _storage.save('phone_number', phoneNumber);
      await _storage.save('first_name', firstName);
      await _storage.save('last_name', lastName);
      await _storage.save('bio', bio);
      state = state.copyWith(
        isLoading: false,
        email: email,
        phoneNumber: phoneNumber,
        firstName: firstName,
        lastName: lastName,
        bio: bio,
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

  Future<void> pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSuccessMessage: true,
    );
    try {
      final sourceFile = File(picked.path);
      final targetPath = p.join(
        Directory.systemTemp.path,
        'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final compressed = await FlutterImageCompress.compressAndGetFile(
        sourceFile.path,
        targetPath,
        quality: 70,
        minWidth: 800,
        minHeight: 800,
      );
      final uploadFile = File((compressed ?? XFile(sourceFile.path)).path);
      final avatarUrl = await _repository.uploadAvatar(uploadFile);
      await _storage.save('avatar_url', avatarUrl);
      state = state.copyWith(isLoading: false, avatarUrl: avatarUrl);
    } catch (e) {
      String errorMessage = 'Failed to upload avatar';
      if (e is DioException && e.response?.data is Map) {
        errorMessage = e.response?.data['message'] ?? errorMessage;
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
    }
  }

  void clearMessages() {
    state = state.copyWith(clearError: true, clearSuccessMessage: true);
  }
}

final profileViewModelProvider =
    NotifierProvider<ProfileViewModel, ProfileState>(ProfileViewModel.new);
