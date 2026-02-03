// lib/services/api_client_service.dart
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../main.dart'; // 🔥 引入 main.dart 以使用 navigatorKey
import 'message_cache_service.dart'; // 🔥 引入 MessageCacheService
import 'dart:convert';
import 'dart:async';
import 'dart:io';

// ==================== SharedPreferences Keys ====================
const String _accessTokenKey = 'auth_token';
const String _refreshTokenKey = 'refresh_token';
const String _userKey = 'current_user';

// ==================== ApiClientService Singleton ====================
class ApiClientService {
  static final ApiClientService _instance = ApiClientService._internal();
  late Dio dio;
  SharedPreferences? _prefs;
  Timer? _tokenRefreshTimer; // 🔥 用於主動刷新 Token 的定時器

  bool _isRefreshing = false;
  bool _isLoggingOut = false;
  List<Map<String, dynamic>> _requestQueue = [];

  // Stream to notify the UI about authentication events
  final StreamController<String?> _authEventController =
      StreamController.broadcast();
  Stream<String?> get onAuthEvent => _authEventController.stream;

  factory ApiClientService() => _instance;

  ApiClientService._internal() {
    BaseOptions options = BaseOptions(
      baseUrl: ApiConfig.currentUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 90),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    dio = Dio(options);
    dio.interceptors.add(_AuthInterceptor(this));
    print("ℹ️ [ApiClientService] Dio instance created with interceptor.");
  }

  // ... existing code ...

  // 🔥 新增：上傳圖片
  Future<String?> uploadImage(File image) async {
    try {
      String fileName = image.path.split('/').last;
      FormData formData = FormData.fromMap({
        "image": await MultipartFile.fromFile(image.path, filename: fileName),
      });

      Response response = await dio.post(
        '/api/v1/rooms/upload/image',
        data: formData,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.data['url'];
      }
      return null;
    } catch (e) {
      print("Error uploading image: $e");
      return null;
    }
  }

  // 🔥 新增：上傳视频
  Future<String?> uploadVideo(File video) async {
    try {
      String fileName = video.path.split('/').last;
      FormData formData = FormData.fromMap({
        "video": await MultipartFile.fromFile(video.path, filename: fileName),
      });

      Response response = await dio.post(
        '/api/v1/rooms/upload/video',
        data: formData,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return response.data['url'];
      }
      return null;
    } catch (e) {
      print("Error uploading video: $e");
      return null;
    }
  }

  // 🔥 新增：發送消息 (HTTP Fallback)
  Future<Map<String, dynamic>?> sendMessage(
      String roomId, String content, String type,
      {String? fileUrl, int? duration, int? fileSize}) async {
    try {
      final Map<String, dynamic> data = {
        'content': content,
        'type': type,
      };

      if (fileUrl != null) data['file_url'] = fileUrl;
      if (duration != null) data['duration'] = duration;
      if (fileSize != null) data['file_size'] = fileSize;

      Response response = await dio.post(
        '/api/v1/rooms/$roomId/messages',
        data: data,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data['message'];
      }
      return null;
    } catch (e) {
      print("Error sending message via API: $e");
      return null;
    }
  }

  // ==================== Initialization ====================
  static Future<void> initialize() async {
    try {
      _instance._prefs = await SharedPreferences.getInstance();

      // 🔥 Startup Token Check
      final token = _instance.getAccessToken();
      if (token != null) {
        if (!_instance._isTokenValid(token)) {
          print(
              "🚀 [ApiClientService] Startup: Token invalid or expired. Clearing cache.");
          await _instance._prefs!.remove(_accessTokenKey);
          await _instance._prefs!.remove(_refreshTokenKey);
          await _instance._prefs!.remove(_userKey);
          await MessageCacheService().clearAllData();
        } else {
          _instance._startTokenRefreshTimer();
        }
      }

      print("✅ [ApiClientService] SharedPreferences initialized.");
    } catch (e) {
      throw Exception("Failed to initialize SharedPreferences");
    }
  }

  bool _checkPrefsInitialized() {
    if (_prefs == null) {
      print("❌ [ApiClientService] SharedPreferences not initialized!");
      return false;
    }
    return true;
  }

  // ==================== Proactive Token Refresh Logic (新增) ====================

  /// 啟動一個定時器，定期檢查 token 是否即將過期。
  void _startTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel(); // 先取消已有的定時器，避免重複執行
    print("🔄 [ApiClientService] Starting proactive token refresh timer...");

    // 每 5 分鐘執行一次檢查
    _tokenRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (timer) async {
        // 檢查 token 是否在 15 分鐘內過期
        final isExpiringSoon = await _isTokenExpiringSoon();

        // 🔥 修正邏輯：如果 isExpiringSoon 為 true，才執行刷新
        if (isExpiringSoon) {
          print(
              'ℹ️ [ApiClientService] Token is expiring soon, attempting proactive refresh...');
          // 只有在沒有其他刷新操作時才執行，避免衝突
          if (!_isRefreshing) {
            _isRefreshing = true; // 🔥 Set flag to true
            try {
              await attemptTokenRefresh();
            } finally {
              _isRefreshing = false; // 🔥 Reset flag
            }
          } else {
            print(
                'ℹ️ [ApiClientService] Token refresh is already in progress, skipping proactive refresh.');
          }
        } else {
          print(
              'ℹ️ [ApiClientService] Token check: still valid, no proactive refresh needed.');
        }
      },
    );
  }

  /// 檢查 Access Token 是否即將過期（預設：在 15 分鐘內）。
  Future<bool> _isTokenExpiringSoon() async {
    try {
      final token = getAccessToken();
      if (token == null || token.isEmpty) return false;

      if (!_isTokenValid(token)) {
        print("❌ [ApiClientService] Token invalid during expiration check.");
        return true; // Treat invalid token as expired so we try to refresh or logout
      }

      final parts = token.split('.');
      // 解碼 JWT 的 payload 部分
      final payload = base64Decode(_normalizeBase64(parts[1]));
      final decoded = jsonDecode(utf8.decode(payload));
      final exp = decoded['exp'] as int?;

      if (exp == null) return false;

      // 將 'exp' (seconds since epoch) 轉換為 DateTime
      final expirationTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      final now = DateTime.now();

      // 🔥 如果在 15 分鐘內過期，就返回 true
      final isExpiring = expirationTime.difference(now).inMinutes < 15;
      if (isExpiring) {
        print(
            "⚠️ [ApiClientService] Token will expire in less than 15 minutes.");
      }
      return isExpiring;
    } catch (e) {
      print("❌ [ApiClientService] Error checking token expiration: $e");
      return false; // 發生任何錯誤都視為不過期，讓 401 被動機制處理
    }
  }

  /// Check if token is structurally valid and not expired
  bool _isTokenValid(String token) {
    if (token.isEmpty) return false;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;

      final payload = base64Decode(_normalizeBase64(parts[1]));
      final decoded = jsonDecode(utf8.decode(payload));
      final exp = decoded['exp'] as int?;

      if (exp == null) return false;

      final expirationTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isBefore(expirationTime);
    } catch (e) {
      return false;
    }
  }

  /// 標準化 Base64 字符串，以正確解碼 Base64Url。
  String _normalizeBase64(String str) {
    String res = str.replaceAll('-', '+').replaceAll('_', '/');
    final padding = (4 - res.length % 4) % 4;
    return res + '=' * padding;
  }

  // ==================== Token Management ====================
  String? getAccessToken() {
    if (!_checkPrefsInitialized()) return null;
    return _prefs!.getString(_accessTokenKey);
  }

  String? getRefreshToken() {
    if (!_checkPrefsInitialized()) return null;
    return _prefs!.getString(_refreshTokenKey);
  }

  Future<void> saveTokens(String accessToken, {String? refreshToken}) async {
    if (!_checkPrefsInitialized()) return;
    await _prefs!.setString(_accessTokenKey, accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _prefs!.setString(_refreshTokenKey, refreshToken);
    }
    print("✅ [ApiClientService] Tokens saved.");
    _authEventController.add(accessToken);
    _startTokenRefreshTimer(); // 🔥 儲存新 Token 後，重置並啟動定時器
  }

  Future<void> clearTokensAndLogout() async {
    if (_isLoggingOut) {
      print("⚠️ [ApiClientService] Logout already in progress, skipping.");
      return;
    }
    _isLoggingOut = true;

    print("🚨 [ApiClientService] Executing FORCE LOGOUT...");

    try {
      if (!_checkPrefsInitialized()) return;

      // 1. 停止定時器
      _tokenRefreshTimer?.cancel();

      // 2. 取消所有排隊的請求
      _cancelQueue();

      // 3. 清除 SharedPreferences (Tokens & User)
      await _prefs!.remove(_accessTokenKey);
      await _prefs!.remove(_refreshTokenKey);
      await _prefs!.remove(_userKey);

      // 4. 清除 SQLite 緩存
      try {
        print("🧹 [ApiClientService] Clearing MessageCacheService...");
        await MessageCacheService().clearAllData();
      } catch (e) {
        print("❌ [ApiClientService] Error clearing MessageCache: $e");
      }

      print("🚪 [ApiClientService] All local data cleared.");
      _authEventController.add(null);

      // 5. 強制跳轉回登入頁面
      // 使用 Future.microtask 確保在當前調用堆棧完成後執行導航
      Future.microtask(() {
        if (navigatorKey.currentState != null) {
          print(
              "🚪 [ApiClientService] Navigating to login page via GlobalKey...");
          navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/login',
            (route) => false,
          );
        } else {
          print(
              "⚠️ [ApiClientService] NavigatorState is null, cannot navigate.");
        }
      });
    } finally {
      _isLoggingOut = false;
    }
  }

  // 🔥 新增：取消所有排隊的請求
  void _cancelQueue() {
    if (_requestQueue.isNotEmpty) {
      print(
          "🛑 [ApiClientService] Canceling ${_requestQueue.length} queued requests.");
      for (var item in _requestQueue) {
        final completer = item['completer'] as Completer<Response<dynamic>>;
        if (!completer.isCompleted) {
          completer.completeError(DioException(
            requestOptions: item['options'] as RequestOptions,
            error: "Request cancelled due to forced logout",
            type: DioExceptionType.cancel,
          ));
        }
      }
      _requestQueue.clear();
    }
  }

  // ==================== User Data Management ====================
  Future<void> saveUser(Map<String, dynamic> userData) async {
    if (!_checkPrefsInitialized()) return;
    await _prefs!.setString(_userKey, jsonEncode(userData));
    print("✅ [ApiClientService] User data saved.");
  }

  Future<Map<String, dynamic>?> getUser() async {
    if (!_checkPrefsInitialized()) return null;
    final userJson = _prefs!.getString(_userKey);
    if (userJson != null) {
      return jsonDecode(userJson) as Map<String, dynamic>;
    }
    return null;
  }

  // ==================== Token Refresh Core Logic ====================
  Future<String?> attemptTokenRefresh() async {
    final refreshToken = getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      print("❌ [ApiClientService] No refresh token found.");
      await clearTokensAndLogout();
      return null;
    }

    print("🔄 [ApiClientService] Attempting to refresh token...");
    try {
      // 使用新的 Dio 實例避免攔截器循環
      final refreshDio = Dio(BaseOptions(
        baseUrl: ApiConfig.currentUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 90),
      ));

      final response = await refreshDio.post(
        '/api/v1/refresh-token',
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );

      if (response.statusCode == 200) {
        final responseBody = response.data;

        final newAccessToken = responseBody['access_token'] as String?;
        final newRefreshToken = responseBody['refresh_token'] as String?;

        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          await saveTokens(
            newAccessToken,
            refreshToken: newRefreshToken ?? refreshToken,
          );
          print("✅ [ApiClientService] Token refreshed successfully.");
          return newAccessToken;
        } else {
          print("❌ [ApiClientService] No access_token in refresh response.");
          await clearTokensAndLogout();
          return null;
        }
      } else {
        print(
            "❌ [ApiClientService] Refresh failed with status: ${response.statusCode}");
        await clearTokensAndLogout();
        return null;
      }
    } on DioException catch (e) {
      print("❌ [ApiClientService] Token refresh error: ${e.message}");

      // 🔥 Catch 401, 403, 404 explicitly
      if (e.response?.statusCode == 401 ||
          e.response?.statusCode == 403 ||
          e.response?.statusCode == 404) {
        print(
            "❌ [ApiClientService] Critical auth error (${e.response?.statusCode}), forcing logout.");
        await clearTokensAndLogout();
      }
      return null;
    } catch (e) {
      print("❌ [ApiClientService] Unexpected error during token refresh: $e");
      return null;
    }
  }

  // ==================== Request Queue Processing ====================
  void _processQueue(String newAccessToken) {
    if (_requestQueue.isEmpty) {
      print("ℹ️ [ApiClientService] Request queue is empty.");
      return;
    }

    print(
        "🔄 [ApiClientService] Processing ${_requestQueue.length} queued requests.");

    Future.wait(_requestQueue.map((queuedRequest) {
      final requestOptions = queuedRequest['options'] as RequestOptions;
      final completer =
          queuedRequest['completer'] as Completer<Response<dynamic>>;

      requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';

      return dio.fetch(requestOptions).then((response) {
        completer.complete(response);
      }).catchError((error) {
        completer.completeError(error);
      });
    })).whenComplete(() {
      _requestQueue.clear();
      print("✅ [ApiClientService] Request queue processed.");
    });
  }

  Future<Response<dynamic>> _queueRequest(RequestOptions options) {
    final completer = Completer<Response<dynamic>>();
    _requestQueue.add({'options': options, 'completer': completer});
    print("📝 [ApiClientService] Request ${options.path} queued.");
    return completer.future;
  }
}

// ==================== Authentication Interceptor ====================
class _AuthInterceptor extends Interceptor {
  final ApiClientService apiClient;

  _AuthInterceptor(this.apiClient);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path.toLowerCase();
    if (path.contains('/refresh-token') ||
        path.contains('/login') ||
        path.contains('/register')) {
      return handler.next(options);
    }

    final accessToken = apiClient.getAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    return handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    print(
        "❌ [Interceptor] Error: ${err.requestOptions.path} - ${err.response?.statusCode}");

    if (err.response?.statusCode == 401) {
      if (err.requestOptions.path.contains('/refresh-token')) {
        print("❌ [Interceptor] Refresh token itself is invalid, logging out.");
        await apiClient.clearTokensAndLogout();
        return handler.reject(err);
      }

      // 🔥 Check if the token was already refreshed by another request
      final currentToken = apiClient.getAccessToken();
      final requestTokenHeader =
          err.requestOptions.headers['Authorization'] as String?;
      final requestToken = requestTokenHeader?.replaceFirst('Bearer ', '');

      if (currentToken != null &&
          currentToken.isNotEmpty &&
          requestToken != null &&
          requestToken != currentToken) {
        print(
            "ℹ️ [Interceptor] Token already refreshed by another request. Retrying immediately.");
        final options = err.requestOptions;
        options.headers['Authorization'] = 'Bearer $currentToken';
        try {
          final response = await apiClient.dio.fetch(options);
          return handler.resolve(response);
        } catch (retryError) {
          return handler.reject(
            retryError is DioException
                ? retryError
                : DioException(
                    requestOptions: err.requestOptions, error: retryError),
          );
        }
      }

      print("⚠️ [Interceptor] 401 detected, attempting token refresh...");

      if (!apiClient._isRefreshing) {
        apiClient._isRefreshing = true;

        try {
          String? newAccessToken = await apiClient.attemptTokenRefresh();

          if (newAccessToken != null && newAccessToken.isNotEmpty) {
            print(
                "✅ [Interceptor] Token refreshed, processing queue and retrying original request.");

            apiClient._processQueue(newAccessToken);

            final options = err.requestOptions;
            options.headers['Authorization'] = 'Bearer $newAccessToken';

            try {
              final response = await apiClient.dio.fetch(options);
              return handler.resolve(response);
            } catch (retryError) {
              print("❌ [Interceptor] Retry failed after refresh: $retryError");
              return handler.reject(
                retryError is DioException
                    ? retryError
                    : DioException(
                        requestOptions: err.requestOptions, error: retryError),
              );
            }
          } else {
            print(
                "❌ [Interceptor] Token refresh failed, clearing queue and logging out.");
            // Queue clearing is now handled inside clearTokensAndLogout
            await apiClient.clearTokensAndLogout();
            return handler.reject(err);
          }
        } finally {
          apiClient._isRefreshing = false;
        }
      } else {
        print("🔄 [Interceptor] Token refresh in progress, queueing request.");
        try {
          final response = await apiClient._queueRequest(err.requestOptions);
          return handler.resolve(response);
        } catch (queuedError) {
          return handler.reject(
            queuedError is DioException
                ? queuedError
                : DioException(
                    requestOptions: err.requestOptions, error: queuedError),
          );
        }
      }
    }

    return handler.next(err);
  }
}
