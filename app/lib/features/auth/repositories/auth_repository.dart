import 'package:app/core/network/network_service.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthRepository {
  final NetworkService _networkService;
  final StorageService _storageService;

  AuthRepository(this._networkService, this._storageService);

  Future<void> login(String username, String password) async {
    try {
      final response = await _networkService.client.post('/users/login', data: {
        'username': username,
        'password': password,
      });
      
      final token = response.data['token'];
      final userId = response.data['user_id'];
      
      await _storageService.save('jwt_token', token);
      await _storageService.save('user_id', userId);
    } catch (e) {
      throw e;
    }
  }

  Future<void> register(String username, String password, String email) async {
    await _networkService.client.post('/users/register', data: {
      'username': username,
      'password': password,
      'email': email,
    });
  }

  Future<void> logout() async {
    await _storageService.deleteAll();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  return AuthRepository(network, storage);
});
