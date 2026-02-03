import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // 🔥 生產環境配置
  static const String _productionUrl =
      'https://api.myapp.com'; // TODO: Replace with your actual production domain

  // 開發環境 URL (Fallback if .env is missing)
  static const String _baseUrlLocalhost = 'http://localhost:8080';

  // 🔥 關鍵修正：動態獲取當前平台的正確 URL
  static String get currentUrl {
    // 🔥 生產環境：使用 HTTPS 生產 URL，忽略 .env 中的開發設定
    if (kReleaseMode) {
      return _productionUrl;
    }

    // 🔥 開發環境：優先使用 .env 中的配置
    final envUrl = dotenv.env['API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }

    // 如果 .env 未配置，回退到 localhost (這在模擬器上可能會失敗，但在桌面端可行)
    // 建議開發者務必配置 .env
    print(
        '⚠️ Warning: API_BASE_URL not found in .env, falling back to localhost');
    return _baseUrlLocalhost;
  }

  // 為了向後相容，保留 baseUrl getter
  static String get baseUrl => effectiveUrl;

  // 獲取音訊檔案的完整 URL
  static String getAudioFileUrl(String relativeUrl) {
    if (relativeUrl.startsWith('http')) {
      return relativeUrl;
    }
    final cleanUrl =
        relativeUrl.startsWith('/') ? relativeUrl.substring(1) : relativeUrl;
    return '$effectiveUrl/$cleanUrl';
  }

  // WebSocket URL
  static String get socketUrl {
    final url = effectiveUrl;
    if (url.startsWith('https://')) {
      return url.replaceFirst('https://', 'wss://');
    } else if (url.startsWith('http://')) {
      return url.replaceFirst('http://', 'ws://');
    }
    return url; // Fallback
  }

  // API 版本
  static const String apiVersion = 'v1';

  // 常用 API 端點
  static String get roomsUrl => '$effectiveUrl/api/$apiVersion/rooms';
  static String getRoomMessagesUrl(String roomId) =>
      '$effectiveUrl/api/$apiVersion/rooms/$roomId/messages';
  static String getVoiceUploadUrl(String roomId) =>
      '$effectiveUrl/api/$apiVersion/rooms/$roomId/voice';
  static String getVoiceMessageUrl(String messageId) =>
      '$effectiveUrl/api/$apiVersion/voice/$messageId';
  static String getVoiceDebugUrl(String messageId) =>
      '$effectiveUrl/api/$apiVersion/voice/$messageId/debug';

  // 連線超時設定
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);

  // 🔥 新增：環境檢測和調試信息
  static bool get isProduction => kReleaseMode;
  static bool get isDevelopment => !kReleaseMode;

  // 🔥 新增：獲取當前環境信息（用於調試）
  static String get environmentInfo {
    if (isProduction) {
      return 'Production: $_productionUrl';
    } else {
      return 'Development: $currentUrl';
    }
  }

  // 🔥 新增：手動切換環境（用於測試）
  static String? _overrideUrl;
  static void setOverrideUrl(String? url) {
    _overrideUrl = url;
  }

  static String get effectiveUrl {
    if (_overrideUrl != null) {
      return _overrideUrl!;
    }
    return currentUrl;
  }
}
