import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart'; // 用於 MultipartFile
import '../services/api_client_service.dart';

// 🔥 全域 ApiClientService 實例
final ApiClientService apiClient = ApiClientService();

class ProfileApiService {
  // 處理 Dio 錯誤的輔助函數
  static Map<String, dynamic> _handleDioError(
      dynamic e, String defaultMessage) {
    if (e is DioException) {
      print(
          'ProfileApiService: Dio 錯誤 - ${e.response?.statusCode}: ${e.response?.data}');
      // 嘗試從後端回應中解析錯誤訊息
      if (e.response?.data is Map<String, dynamic>) {
        return {
          'success': false,
          'message': e.response?.data['error'] ??
              e.response?.data['message'] ??
              defaultMessage,
        };
      }
      return {
        'success': false,
        'message': '$defaultMessage (狀態碼: ${e.response?.statusCode})',
      };
    }
    // 其他類型的錯誤
    print('ProfileApiService: 未知錯誤 - $e');
    return {
      'success': false,
      'message': '發生未知網路錯誤: $e',
    };
  }

  // 更新個人資料
  static Future<Map<String, dynamic>> updateProfile({
    String? username,
    String? email,
    String? currentPassword,
    String? newPassword,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      if (username != null) updateData['username'] = username;
      if (email != null) updateData['email'] = email;
      if (currentPassword != null)
        updateData['current_password'] = currentPassword;
      if (newPassword != null) updateData['new_password'] = newPassword;

      print('ProfileApiService: 發送更新請求 - $updateData');

      final response = await apiClient.dio.put(
        '/api/v1/profile',
        data: updateData,
      );

      print('ProfileApiService: 響應狀態碼 - ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = response.data;

        // 🔥 關鍵修正：使用 apiClient 統一保存用戶資料
        if (responseData['user'] != null) {
          await apiClient.saveUser(responseData['user']);
          print('ProfileApiService: 本地用戶資料已更新');
        }

        return {
          'success': true,
          'message': responseData['message'] ?? '更新成功',
          'user': responseData['user'],
        };
      } else {
        return {
          'success': false,
          'message': '更新失敗，狀態碼: ${response.statusCode}',
        };
      }
    } catch (e) {
      return _handleDioError(e, '更新失敗');
    }
  }

  // 獲取個人資料
  static Future<Map<String, dynamic>> getProfile() async {
    try {
      final response = await apiClient.dio.get('/api/v1/profile');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'user': response.data['user'],
        };
      } else {
        return {
          'success': false,
          'message': '獲取個人資料失敗',
        };
      }
    } catch (e) {
      return _handleDioError(e, '獲取個人資料失敗');
    }
  }

  // 驗證當前密碼
  static Future<Map<String, dynamic>> verifyPassword(String password) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/verify-password',
        data: {'password': password},
      );

      if (response.statusCode == 200) {
        return {'success': true, 'message': '密碼驗證成功'};
      } else {
        return {'success': false, 'message': '密碼錯誤'};
      }
    } catch (e) {
      return _handleDioError(e, '密碼錯誤');
    }
  }

  // 更新頭像 (Base64)
  static Future<Map<String, dynamic>> updateAvatar(String avatarData) async {
    try {
      final response = await apiClient.dio.put(
        '/api/v1/profile/avatar',
        data: {'avatar': avatarData},
      );

      if (response.statusCode == 200) {
        final responseData = response.data;
        // 🔥 關鍵修正：使用 apiClient 統一保存用戶資料
        if (responseData['user'] != null) {
          await apiClient.saveUser(responseData['user']);
        }
        return {
          'success': true,
          'message': '頭像更新成功',
          'avatar_url': responseData['avatar_url'],
        };
      } else {
        return {'success': false, 'message': '頭像更新失敗'};
      }
    } catch (e) {
      return _handleDioError(e, '頭像更新失敗');
    }
  }

  // 偽刪除帳戶
  static Future<Map<String, dynamic>> softDeleteAccount(String password) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/account/soft-delete',
        data: {'password': password},
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': response.data['message'] ?? '帳戶已成功停用',
        };
      } else {
        return {'success': false, 'message': '停用帳戶失敗'};
      }
    } catch (e) {
      return _handleDioError(e, '停用帳戶失敗');
    }
  }

  // 恢復帳戶
  static Future<Map<String, dynamic>> restoreAccount() async {
    try {
      final response = await apiClient.dio.post('/api/v1/account/restore');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': response.data['message'] ?? '帳戶已成功恢復',
        };
      } else {
        return {'success': false, 'message': '恢復帳戶失敗'};
      }
    } catch (e) {
      return _handleDioError(e, '恢復帳戶失敗');
    }
  }

  // 上傳頭像 (Multipart)
  static Future<Map<String, dynamic>> uploadAvatar(File imageFile) async {
    try {
      final fileExtension = imageFile.path.split('.').last.toLowerCase();
      String mimeType;
      String filename;

      switch (fileExtension) {
        case 'png':
          mimeType = 'image/png';
          filename = 'avatar.png';
          break;
        case 'gif':
          mimeType = 'image/gif';
          filename = 'avatar.gif';
          break;
        case 'webp':
          mimeType = 'image/webp';
          filename = 'avatar.webp';
          break;
        default:
          mimeType = 'image/jpeg';
          filename = 'avatar.jpg';
      }

      FormData formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(
          imageFile.path,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        ),
      });

      print('ProfileApiService: 嘗試使用 POST (multipart) 方法上傳頭像');
      final response = await apiClient.dio.post(
        '/api/v1/profile/avatar',
        data: formData,
      );

      if (response.statusCode == 200) {
        return {
          'success': true,
          'avatar_url': response.data['avatar_url'],
          'message': response.data['message'] ?? '頭像上傳成功',
        };
      } else {
        return {'success': false, 'message': '上傳頭像失敗'};
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        print('ProfileApiService: POST 方法失敗(404)，嘗試使用 PUT (base64)');
        return await _uploadAvatarAsBase64(imageFile);
      }
      return _handleDioError(e, '上傳頭像失敗');
    }
  }

  // 使用 base64 上傳頭像的備用方法
  static Future<Map<String, dynamic>> _uploadAvatarAsBase64(
      File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      return await updateAvatar(base64Image);
    } catch (e) {
      print('ProfileApiService: base64 上傳失敗: $e');
      return {
        'success': false,
        'message': 'base64 上傳也失敗: $e',
      };
    }
  }

  // 移除頭像
  static Future<Map<String, dynamic>> removeAvatar() async {
    try {
      final response = await apiClient.dio.delete('/api/v1/profile/avatar');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': response.data['message'] ?? '頭像已移除',
        };
      } else {
        return {'success': false, 'message': '移除頭像失敗'};
      }
    } catch (e) {
      return _handleDioError(e, '移除頭像失敗');
    }
  }
}

