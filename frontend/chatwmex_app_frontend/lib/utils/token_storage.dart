// 方法一：在應用啟動時檢查並清除過期 token
// 修改 lib/utils/token_storage.dart

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class TokenStorage {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'current_user';

  // 🔥 新增：檢查 Token 是否過期
  static Future<bool> isTokenValid() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return false;

      // 解析 JWT payload
      final parts = token.split('.');
      if (parts.length != 3) {
        print('Token 格式錯誤: 不是3部分');
        return false;
      }

      final payload = parts[1];
      // print('原始 payload: $payload');

      // 🔥 修正：更安全的 Base64 padding 處理
      String normalizedPayload = payload;

      // 移除可能存在的多餘 padding
      normalizedPayload = normalizedPayload.replaceAll('=', '');

      // 根據長度添加正確的 padding
      final paddingLength = (4 - (normalizedPayload.length % 4)) % 4;
      normalizedPayload += '=' * paddingLength;

      // print('標準化後的 payload: $normalizedPayload');

      try {
        final decodedBytes = base64Decode(normalizedPayload);
        final decodedString = utf8.decode(decodedBytes);
        // print('解碼後的字符串: $decodedString');

        final decoded = json.decode(decodedString);
        // print('解析後的 JSON: $decoded');

        final exp = decoded['exp'];
        if (exp == null) {
          print('Token 中沒有 exp 字段');
          return false;
        }

        final expirationTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        final now = DateTime.now();

        // print('Token 過期時間: $expirationTime');
        // print('當前時間: $now');
        final isValid = expirationTime.isAfter(now);
        // print('Token 是否有效: $isValid');

        return isValid;
      } catch (decodeError) {
        print('Base64 解碼失敗: $decodeError');
        return false;
      }
    } catch (e) {
      print('檢查 Token 有效性時出錯: $e');
      return false;
    }
  }

  // 🔥 修改：改進 isLoggedIn 方法，包含過期檢查
  static Future<bool> isLoggedIn() async {
    try {
      // 🔥 檢查是否有 refresh_token
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');

      // 有 refresh_token 就視為已登入
      if (refreshToken != null && refreshToken.isNotEmpty) {
        // print('有 refresh_token，視為已登入');
        return true;
      }

      // 沒有 refresh_token，檢查 access_token
      final hasValidToken = await isTokenValid();
      if (!hasValidToken) {
        await clearAll();
        return false;
      }
      return true;
    } catch (e) {
      print('Error checking login status: $e');
      return false;
    }
  }

  // 🔥 新增：清除過期 Token 的方法
  static Future<void> clearExpiredToken() async {
    final isValid = await isTokenValid();
    if (!isValid) {
      await clearAll();
      // print('已清除過期的 Token');
    }
  }

  // 保存 Token
  static Future<bool> saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_tokenKey, token);
    } catch (e) {
      print('Error saving token: $e');
      return false;
    }
  }

  // 獲取 Token
  static Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      print('Error getting token: $e');
      return null;
    }
  }

  // 保存用戶信息
  static Future<bool> saveUser(Map<String, dynamic> user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = jsonEncode(user);
      return await prefs.setString(_userKey, userJson);
    } catch (e) {
      print('Error saving user: $e');
      return false;
    }
  }

  // 獲取用戶信息
  static Future<Map<String, dynamic>?> getUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      if (userJson != null) {
        return jsonDecode(userJson) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Error getting user: $e');
      return null;
    }
  }

  // 清除所有存儲的數據
  static Future<bool> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
      // print('已清除所有本地存儲數據');
      return true;
    } catch (e) {
      print('Error clearing storage: $e');
      return false;
    }
  }

  // 清除 Token
  static Future<bool> clearToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_tokenKey);
    } catch (e) {
      print('Error clearing token: $e');
      return false;
    }
  }

  // 更新 Token
  static Future<bool> updateToken(String newToken) async {
    return await saveToken(newToken);
  }

  // 獲取用戶ID
  static Future<String?> getUserId() async {
    try {
      final user = await getUser();
      return user?['user_id'] ?? user?['id'];
    } catch (e) {
      print('Error getting user ID: $e');
      return null;
    }
  }

  // 獲取用戶名
  static Future<String?> getUsername() async {
    try {
      final user = await getUser();
      return user?['username'];
    } catch (e) {
      print('Error getting username: $e');
      return null;
    }
  }
}
