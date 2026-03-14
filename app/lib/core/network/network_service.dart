import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/features/auth/providers/auth_provider.dart';

class NetworkService {
  late final Dio _dio;
  final StorageService _storageService;
  final Ref _ref;
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static String get baseUrl {
    // 如果是 Debug 模式，強制使用本地環境（無視 .env 的正是機設定）
    if (kDebugMode) {
      if (Platform.isAndroid) return 'http://10.0.2.2:8080';
      if (Platform.isIOS) return 'http://127.0.0.1:8080';
      return 'http://localhost:8080';
    }

    // 非 Debug 模式才讀取 .env 或編譯參數
    final envUrl = dotenv.env['API_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }

    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }

    return 'http://localhost:8080';
  }

  static String resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '${NetworkService.baseUrl}$path';
  }

  NetworkService(this._storageService, this._ref) {
    // Detect Platform to set correct localhost
    final apiBaseUrl = '${NetworkService.baseUrl}/api/v1';
    _dio = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storageService.read('jwt_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (options.data is FormData) {
            options.headers['Content-Type'] = 'multipart/form-data';
          } else if (options.headers['Content-Type'] == null) {
            options.headers['Content-Type'] = 'application/json';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          // Handle token expiration with automatic refresh
          if (e.response?.statusCode == 401) {
            debugPrint('🔒 Received 401 error, attempting token refresh...');
            
            // Attempt to refresh the token
            final authViewModel = _ref.read(authViewModelProvider.notifier);
            final refreshSuccess = await authViewModel.refreshToken();
            
            if (refreshSuccess) {
              debugPrint('✅ Token refresh successful, retrying original request...');
              
              // Get the new token
              final newToken = await _storageService.read('jwt_token');
              
              if (newToken != null) {
                // Clone the original request with the new token
                final options = e.requestOptions;
                options.headers['Authorization'] = 'Bearer $newToken';
                
                try {
                  // Retry the request with the new token
                  final response = await _dio.fetch(options);
                  return handler.resolve(response);
                } catch (retryError) {
                  debugPrint('❌ Retry failed after token refresh: $retryError');
                  return handler.next(e);
                }
              }
            } else {
              debugPrint('❌ Token refresh failed, proceeding with error');
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  Future<String> uploadFile(File file, String type) async {
    final fileName = file.path.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      'type': type, // 'image' or 'voice'
    });

    try {
      final response = await _dio.post('/media/upload', data: formData);
      final data = response.data['data'];
      if (data is Map<String, dynamic> && data['url'] is String) {
        return data['url'] as String;
      }
      if (response.data is Map && response.data['url'] is String) {
        return response.data['url'] as String;
      }
      throw Exception('Invalid upload response format');
    } catch (e) {
      throw Exception('Upload failed: $e');
    }
  }

  Future<String> uploadAvatar(File file) async {
    final fileName = file.path.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });

    try {
      final response = await _dio.put('/users/avatar', data: formData);
      final data = response.data['data'];
      if (data is Map<String, dynamic> && data['avatar_url'] is String) {
        return data['avatar_url'] as String;
      }
      if (response.data is Map && response.data['avatar_url'] is String) {
        return response.data['avatar_url'] as String;
      }
      throw Exception('Invalid upload avatar response format');
    } catch (e) {
      throw Exception('Upload avatar failed: $e');
    }
  }

  Future<void> confirmQrLogin(String qrToken) async {
    try {
      await _dio.post('/auth/qr/confirm', data: {'qr_token': qrToken});
    } catch (e) {
      throw Exception('QR Login failed: $e');
    }
  }

  Dio get client => _dio;
}

final networkServiceProvider = Provider<NetworkService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return NetworkService(storage, ref);
});
