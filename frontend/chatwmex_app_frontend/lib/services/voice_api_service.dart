import 'dart:io';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../models/voice_message.dart';
import '../models/message.dart' as chat_msg;
import '../utils/token_storage.dart';

class VoiceApiService {
  static final Dio _dio = Dio();

  static Future<Map<String, String>> _getHeaders() async {
    final token = await TokenStorage.getToken();
    return {
      'Authorization': 'Bearer ${token ?? ''}',
    };
  }

  // 🔥 修正：上传语音消息 - 配合後端統一架構
  static Future<VoiceMessage> uploadVoiceMessage({
    required String roomId,
    required String filePath,
    required int duration,
  }) async {
    try {
      final headers = await _getHeaders();
      final file = File(filePath);
      
      if (!await file.exists()) {
        throw Exception('语音文件不存在');
      }

      final formData = FormData.fromMap({
        'voice': await MultipartFile.fromFile(
          filePath,
          filename: 'voice_message.m4a',
        ),
        'duration': duration.toString(),
      });

      print('VoiceApiService: 上传语音到房间 $roomId, 时长: ${duration}s');

      // 🔥 修正：使用正確的後端路由
      final response = await _dio.post(
        ApiConfig.getVoiceUploadUrl(roomId),
        data: formData,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
        onSendProgress: (sent, total) {
          final progress = (sent / total * 100).toStringAsFixed(1);
          print('VoiceApiService: 上传进度: $progress%');
        },
      );

      if (response.statusCode == 201) {
        final data = response.data;
        print('VoiceApiService: 语音上传成功 - ${data}');
        
        // 🔥 修正：從響應中提取語音消息數據
        final voiceMessageData = data['voice_message'];
        if (voiceMessageData == null) {
          throw Exception('服务器响应格式错误：缺少语音消息数据');
        }
        
        return VoiceMessage.fromJson(voiceMessageData);
      } else {
        throw Exception('上传失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('VoiceApiService: 上传语音消息失败: $e');
      rethrow;
    }
  }

  // 🔥 新增：直接通過統一消息API發送語音消息
  static Future<chat_msg.Message> sendVoiceMessageDirect({
    required String roomId,
    required String fileUrl,
    required int duration,
    required int fileSize,
  }) async {
    try {
      final headers = await _getHeaders();
      headers['Content-Type'] = 'application/json';

      final requestData = {
        'content': '[语音消息]',
        'type': 'voice',
        'file_url': fileUrl,
        'duration': duration,
        'file_size': fileSize,
      };

      print('VoiceApiService: 發送語音消息到房間 $roomId - $requestData');

      // 使用統一的消息端點
      final response = await _dio.post(
        ApiConfig.getRoomMessagesUrl(roomId),
        data: requestData,
        options: Options(headers: headers),
      );

      if (response.statusCode == 201) {
        final data = response.data;
        print('VoiceApiService: 語音消息發送成功 - ${data}');
        
        final messageData = data['message'];
        if (messageData == null) {
          throw Exception('服务器响应格式错误：缺少消息数据');
        }
        
        return chat_msg.Message.fromJson(messageData);
      } else {
        throw Exception('發送失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('VoiceApiService: 發送語音消息失败: $e');
      rethrow;
    }
  }

  // 🔥 修正：获取语音消息播放URL
  static Future<String> getVoiceMessageUrl(String messageId) async {
    try {
      final headers = await _getHeaders();
      
      final response = await _dio.get(
        ApiConfig.getVoiceMessageUrl(messageId),
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final url = data['url'] as String?;
        if (url == null || url.isEmpty) {
          throw Exception('服务器返回的URL为空');
        }
        return url;
      } else {
        throw Exception('获取语音URL失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('VoiceApiService: 获取语音URL失败: $e');
      rethrow;
    }
  }

  // 🔥 新增：調試語音消息
  static Future<Map<String, dynamic>> debugVoiceMessage(String messageId) async {
    try {
      final headers = await _getHeaders();
      
      final response = await _dio.get(
        ApiConfig.getVoiceDebugUrl(messageId),
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('调试请求失败: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('VoiceApiService: 调试语音消息失败: $e');
      return {
        'error': e.toString(),
        'message_exists': false,
      };
    }
  }

  // 🔥 新增：檢驗語音文件
  static Future<bool> validateVoiceFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('VoiceApiService: 文件不存在: $filePath');
        return false;
      }

      final fileSize = await file.length();
      const maxSize = 10 * 1024 * 1024; // 10MB 限制

      if (fileSize > maxSize) {
        print('VoiceApiService: 文件過大: ${fileSize}bytes');
        return false;
      }

      if (fileSize == 0) {
        print('VoiceApiService: 文件為空');
        return false;
      }

      return true;
    } catch (e) {
      print('VoiceApiService: 驗證文件失敗: $e');
      return false;
    }
  }

  // 🔥 新增：重試機制的上傳方法
  static Future<VoiceMessage> uploadVoiceMessageWithRetry({
    required String roomId,
    required String filePath,
    required int duration,
    int maxRetries = 3,
  }) async {
    Exception? lastException;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('VoiceApiService: 語音上傳嘗試 $attempt/$maxRetries');
        return await uploadVoiceMessage(
          roomId: roomId,
          filePath: filePath,
          duration: duration,
        );
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        print('VoiceApiService: 上傳嘗試 $attempt 失敗: $e');
        
        if (attempt < maxRetries) {
          // 等待後重試
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }
    
    throw lastException ?? Exception('上傳失敗，已重試 $maxRetries 次');
  }

  // 🔥 新增：檢查服務器語音功能狀態
  static Future<bool> checkVoiceServiceStatus() async {
    try {
      final headers = await _getHeaders();
      
      final response = await _dio.get(
        '${ApiConfig.currentUrl}/api/v1/voice/status',
        options: Options(headers: headers),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('VoiceApiService: 檢查服務狀態失敗: $e');
      return false;
    }
  }
}