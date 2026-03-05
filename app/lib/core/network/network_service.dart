import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/storage/storage_service.dart';

class NetworkService {
  late final Dio _dio;
  final StorageService _storageService;
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080';
    }
    if (Platform.isIOS) {
      return 'http://127.0.0.1:8080';
    }
    return 'http://localhost:8080';
  }

  static String resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '${NetworkService.baseUrl}$path';
  }

  NetworkService(this._storageService) {
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
        onError: (DioException e, handler) {
          // Handle token expiration, etc.
          if (e.response?.statusCode == 401) {
            // Trigger logout or refresh
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

  Dio get client => _dio;
}

final networkServiceProvider = Provider<NetworkService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return NetworkService(storage);
});
