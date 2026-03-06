import 'package:app/core/network/network_service.dart';
import 'package:app/features/chat/models/room.dart'; // User model
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'dart:io';

class ProfileRepository {
  final NetworkService _networkService;

  ProfileRepository(this._networkService);

  Future<User> getUserProfile() async {
    try {
      final response = await _networkService.client.get('/users/profile');
      final data = response.data['data'];
      if (data is Map<String, dynamic>) {
        return User.fromJson(data);
      }
      if (data is Map) {
        return User.fromJson(Map<String, dynamic>.from(data));
      }
      throw Exception('Invalid profile response format');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateProfile(
    String email,
    String phoneNumber,
    String firstName,
    String lastName,
    String bio,
  ) async {
    await _networkService.client.put(
      '/users/profile',
      data: {
        'email': email,
        'phone_number': phoneNumber,
        'first_name': firstName,
        'last_name': lastName,
        'bio': bio,
      },
    );
  }

  Future<String> uploadAvatar(File file) async {
    final fileName = file.path.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });
    final response = await _networkService.client.put(
      '/users/avatar',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    final data = response.data['data'];
    if (data is Map<String, dynamic> && data['avatar_url'] is String) {
      return data['avatar_url'] as String;
    }
    if (data is Map && data['avatar_url'] is String) {
      return data['avatar_url'] as String;
    }
    throw Exception('Invalid avatar upload response format');
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return ProfileRepository(network);
});
