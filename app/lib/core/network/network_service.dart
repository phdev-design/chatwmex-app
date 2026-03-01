import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/storage/storage_service.dart';

class NetworkService {
  late final Dio _dio;
  final StorageService _storageService;

  NetworkService(this._storageService) {
    _dio = Dio(BaseOptions(
      baseUrl: 'http://localhost:8080/api/v1', // TODO: Use env config
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storageService.read('jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
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
    ));
  }

  Dio get client => _dio;
}

final networkServiceProvider = Provider<NetworkService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return NetworkService(storage);
});
