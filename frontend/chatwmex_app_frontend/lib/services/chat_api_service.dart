import 'dart:convert';
import 'dart:io';
import '../services/api_client_service.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'message_cache_service.dart';

// 🔥 使用全域 ApiClientService 實例
final ApiClientService apiClient = ApiClientService();

class ChatApiService {
  // ==================== 錯誤處理 ====================
  static Map<String, dynamic> _handleError(dynamic e, String defaultMessage) {
    print('ChatApiService: 錯誤 - $e');
    return {
      'success': false,
      'message': defaultMessage,
      'error': e.toString(),
    };
  }

  // ==================== 聊天室管理 ====================

  /// 智能獲取聊天室列表（先讀取緩存，再同步服務器）
  static Future<List<ChatRoom>> getChatRooms() async {
    try {
      print('ChatApiService: 智能獲取聊天室列表');

      // 先嘗試從緩存讀取
      final cachedRooms = await MessageCacheService().getCachedChatRooms();
      if (cachedRooms.isNotEmpty) {
        print('ChatApiService: 從緩存讀取 ${cachedRooms.length} 個聊天室');
        // 在後台同步服務器數據
        _syncChatRoomsInBackground();
        return cachedRooms;
      }

      // 緩存為空，從服務器獲取
      print('ChatApiService: 緩存為空，從服務器獲取聊天室列表');
      return await _fetchChatRoomsFromServer();
    } catch (e) {
      print('ChatApiService: 獲取聊天室列表失敗: $e');

      // 如果服務器請求失敗，嘗試返回緩存數據
      final cachedRooms = await MessageCacheService().getCachedChatRooms();
      if (cachedRooms.isNotEmpty) {
        print('ChatApiService: 服務器請求失敗，使用緩存數據');
        return cachedRooms;
      }

      // 🔥 如果是 401，返回空列表，避免崩潰
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        return [];
      }

      throw e;
    }
  }

  /// 從服務器獲取聊天室列表
  static Future<List<ChatRoom>> _fetchChatRoomsFromServer() async {
    try {
      final response = await apiClient.dio.get('/api/v1/rooms');

      if (response.statusCode == 200) {
        final List<dynamic> roomsJson = response.data['rooms'] ?? [];
        final rooms = roomsJson.map((json) => ChatRoom.fromJson(json)).toList();

        // 緩存聊天室列表
        await MessageCacheService().cacheChatRooms(rooms);
        print('ChatApiService: 聊天室列表已緩存');

        return rooms;
      } else {
        throw Exception('Failed to load chat rooms: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 從服務器獲取聊天室列表失敗: $e');
      throw e;
    }
  }

  /// 後台同步聊天室列表
  static Future<void> _syncChatRoomsInBackground() async {
    try {
      print('ChatApiService: 後台同步聊天室列表');
      final rooms = await _fetchChatRoomsFromServer();
      print('ChatApiService: 後台同步完成，更新了 ${rooms.length} 個聊天室');
    } catch (e) {
      print('ChatApiService: 後台同步失敗: $e');
    }
  }

  /// 創建聊天室
  static Future<ChatRoom> createChatRoom({
    required String name,
    List<String> participants = const [],
    bool isGroup = false,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/rooms',
        data: {
          'name': name,
          'participants': participants,
          'is_group': isGroup,
        },
      );

      if (response.statusCode == 201) {
        return ChatRoom.fromJson(response.data['room']);
      } else {
        throw Exception('Failed to create chat room: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 創建聊天室失敗: $e');
      throw e;
    }
  }

  /// 獲取聊天室詳情
  static Future<ChatRoom> getRoomDetails(String roomId) async {
    try {
      final response = await apiClient.dio.get('/api/v1/rooms/$roomId');

      if (response.statusCode == 200) {
        return ChatRoom.fromJson(response.data['room']);
      } else {
        throw Exception('Failed to get room details: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 獲取聊天室詳情失敗: $e');
      throw e;
    }
  }

  // ==================== 消息管理 ====================

  static Future<String?> uploadImage(File image) async {
    return await apiClient.uploadImage(image);
  }

  // 🔥 新增：上傳視頻
  static Future<String?> uploadVideo(File video) async {
    return await apiClient.uploadVideo(video);
  }

  /// 獲取聊天歷史（默認直接從服務器獲取，確保數據最新）
  static Future<List<Message>> getChatHistory(
    String roomId, {
    int page = 1,
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    try {
      // print(
      //    'ChatApiService: 獲取聊天歷史 - 房間: $roomId, 頁碼: $page, 強制刷新: $forceRefresh');

      if (forceRefresh) {
        // 強制刷新：清除緩存並從服務器獲取
        await MessageCacheService().clearRoomCache(roomId);
      }

      // 默認直接從服務器獲取，確保數據最新
      return await _fetchMessagesFromServer(roomId, page: page, limit: limit);
    } catch (e) {
      print('ChatApiService: 獲取聊天歷史失敗: $e');

      // 只有在服務器請求完全失敗時才使用緩存
      try {
        print('ChatApiService: 嘗試使用緩存數據');
        final cachedMessages =
            await MessageCacheService().getCachedRoomMessages(roomId);

        if (cachedMessages.isNotEmpty) {
          print('ChatApiService: 使用緩存數據，共 ${cachedMessages.length} 條消息');
          return cachedMessages;
        }
      } catch (cacheError) {
        print('ChatApiService: 緩存讀取也失敗: $cacheError');
      }

      // 🔥 如果是 401，返回空列表
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        return [];
      }

      throw e;
    }
  }

  /// 從服務器獲取消息（改進錯誤處理）
  static Future<List<Message>> _fetchMessagesFromServer(
    String roomId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await apiClient.dio.get(
        '/api/v1/rooms/$roomId/messages',
        queryParameters: {
          'page': page,
          'limit': limit,
          'include_voice': true,
          'sort': 'desc',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> messagesJson = response.data['messages'] ?? [];
        print('ChatApiService: 從服務器獲取到 ${messagesJson.length} 條消息 (頁碼: $page)');

        final messages = <Message>[];

        // 逐個解析消息，確保錯誤處理
        for (int i = 0; i < messagesJson.length; i++) {
          try {
            final json = messagesJson[i];
            if (json['type'] == 'voice') {
              print('ChatApiService: 解析語音消息 - ID: ${json['id']}');
            }

            final message = Message.fromJson(json);
            messages.add(message);
          } catch (parseError) {
            print('ChatApiService: 解析第 $i 條消息失敗: $parseError');
            print('ChatApiService: 原始消息數據: ${messagesJson[i]}');
            // 繼續處理其他消息，不因單個消息解析失敗而中斷
          }
        }

        print(
            'ChatApiService: 成功解析 ${messages.length}/${messagesJson.length} 條消息');

        // 緩存成功解析的消息
        if (messages.isNotEmpty && page == 1) {
          await MessageCacheService().cacheRoomMessages(roomId, messages);
        }

        return messages;
      } else {
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 從服務器獲取消息失敗: $e');
      throw e;
    }
  }

  /// 獲取房間的所有消息（不使用緩存）
  static Future<List<Message>> getAllRoomMessages(String roomId) async {
    try {
      print('ChatApiService: 獲取房間 $roomId 的所有消息');

      final allMessages = <Message>[];
      int currentPage = 1;
      const int pageSize = 100;
      bool hasMoreMessages = true;

      while (hasMoreMessages && currentPage <= 20) {
        try {
          final messages = await _fetchMessagesFromServer(
            roomId,
            page: currentPage,
            limit: pageSize,
          );

          if (messages.isEmpty) {
            hasMoreMessages = false;
            break;
          }

          // 去重添加消息
          for (final message in messages) {
            if (!allMessages.any((m) => m.id == message.id)) {
              allMessages.add(message);
            }
          }

          print('ChatApiService: 第 $currentPage 頁獲取 ${messages.length} 條消息');

          if (messages.length < pageSize) {
            hasMoreMessages = false;
          }

          currentPage++;
        } catch (pageError) {
          print('ChatApiService: 獲取第 $currentPage 頁失敗: $pageError');
          hasMoreMessages = false;
        }
      }

      // 按時間戳排序
      allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      print('ChatApiService: 總共獲取 ${allMessages.length} 條消息');

      // 更新緩存
      await MessageCacheService().cacheRoomMessages(roomId, allMessages);

      return allMessages;
    } catch (e) {
      print('ChatApiService: 獲取所有消息失敗: $e');
      throw e;
    }
  }

  /// 強制刷新房間消息
  static Future<List<Message>> forceRefreshMessages(String roomId) async {
    try {
      print('ChatApiService: 強制刷新房間 $roomId 的消息');
      await MessageCacheService().clearRoomCache(roomId);
      return await getAllRoomMessages(roomId);
    } catch (e) {
      print('ChatApiService: 強制刷新失敗: $e');
      throw e;
    }
  }

  /// 發送消息
  static Future<Message> sendMessage(
    String roomId,
    String content, {
    MessageType type = MessageType.text,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/rooms/$roomId/messages',
        data: {
          'content': content,
          'type': type.toString().split('.').last,
        },
      );

      if (response.statusCode == 201) {
        return Message.fromJson(response.data['message']);
      } else {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 發送消息失敗: $e');
      throw e;
    }
  }

  /// 發送圖片消息
  static Future<Message> sendImageMessage(
    String roomId,
    String fileUrl,
  ) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/rooms/$roomId/messages',
        data: {
          'content': '[图片]',
          'type': 'image',
          'file_url': fileUrl,
        },
      );

      if (response.statusCode == 201) {
        return Message.fromJson(response.data['message']);
      } else {
        throw Exception('Failed to send image message: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 發送圖片消息失敗: $e');
      throw e;
    }
  }

  /// 發送視頻消息
  static Future<Message> sendVideoMessage(
    String roomId,
    String fileUrl,
  ) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/rooms/$roomId/messages',
        data: {
          'content': '[视频]',
          'type': 'video',
          'file_url': fileUrl,
        },
      );

      if (response.statusCode == 201) {
        return Message.fromJson(response.data['message']);
      } else {
        throw Exception('Failed to send video message: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 發送視頻消息失敗: $e');
      throw e;
    }
  }

  /// 發送語音消息
  static Future<Message> sendVoiceMessage(
    String roomId,
    String fileUrl,
    int duration,
    int fileSize,
  ) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/rooms/$roomId/messages',
        data: {
          'content': '[語音消息]',
          'type': 'voice',
          'file_url': fileUrl,
          'duration': duration,
          'file_size': fileSize,
        },
      );

      if (response.statusCode == 201) {
        return Message.fromJson(response.data['message']);
      } else {
        throw Exception('Failed to send voice message: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 發送語音消息失敗: $e');
      throw e;
    }
  }

  /// 獲取語音消息列表
  static Future<List<Message>> getVoiceMessages(
    String roomId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await apiClient.dio.get(
        '/api/v1/rooms/$roomId/messages',
        queryParameters: {
          'type': 'voice',
          'page': page,
          'limit': limit,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> messagesJson = response.data['messages'] ?? [];
        return messagesJson.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception(
            'Failed to load voice messages: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 獲取語音消息失敗: $e');
      throw e;
    }
  }

  // ==================== 用戶操作 ====================

  /// 搜索用戶
  static Future<List<User>> searchUsers(String query) async {
    try {
      final response = await apiClient.dio.get(
        '/api/v1/users/search',
        queryParameters: {'q': query},
      );

      if (response.statusCode == 200) {
        final List<dynamic> usersJson = response.data['users'] ?? [];
        return usersJson.map((json) => User.fromJson(json)).toList();
      } else {
        throw Exception('Failed to search users: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 搜索用戶失敗: $e');
      throw e;
    }
  }

  /// 封鎖用戶
  static Future<void> blockUser(String userId) async {
    try {
      await apiClient.dio.post('/api/v1/users/$userId/block');
    } catch (e) {
      print('ChatApiService: 封鎖用戶失敗: $e');
      throw e;
    }
  }

  /// 解除封鎖用戶
  static Future<void> unblockUser(String userId) async {
    try {
      await apiClient.dio.post('/api/v1/users/$userId/unblock');
    } catch (e) {
      print('ChatApiService: 解除封鎖用戶失敗: $e');
      throw e;
    }
  }

  /// 獲取封鎖用戶列表
  static Future<List<String>> getBlockedUsers() async {
    try {
      final response = await apiClient.dio.get('/api/v1/users/blocked');
      if (response.statusCode == 200) {
        final List<dynamic> usersJson = response.data['users'] ?? [];
        return usersJson.map((id) => id.toString()).toList();
      } else {
        throw Exception('Failed to get blocked users: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 獲取封鎖用戶列表失敗: $e');
      // 🔥 如果是 401 錯誤，返回空列表，避免 UI 異常
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        return [];
      }
      throw e;
    }
  }

  /// 邀請用戶加入聊天室
  static Future<void> inviteUserToRoom(String roomId, String userId) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/rooms/$roomId/invite',
        data: {'user_id': userId},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to invite user: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 邀請用戶失敗: $e');
      throw e;
    }
  }

  /// 離開聊天室
  static Future<void> leaveRoom(String roomId) async {
    try {
      final response = await apiClient.dio.post('/api/v1/rooms/$roomId/leave');

      if (response.statusCode != 200) {
        throw Exception('Failed to leave room: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 離開聊天室失敗: $e');
      throw e;
    }
  }

  /// 標記消息為已讀
  static Future<void> markAsRead(String roomId) async {
    try {
      final response = await apiClient.dio.post('/api/v1/rooms/$roomId/read');

      if (response.statusCode != 200) {
        throw Exception('Failed to mark as read: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 標記已讀失敗: $e');
      // 🔥 不再重新拋出異常，避免因 401 或網絡問題導致 App 崩潰
      // 401 錯誤已由攔截器處理
    }
  }

  // ==================== 消息同步 ====================

  /// 同步聊天歷史記錄（改進錯誤處理）
  static Future<List<Message>> syncChatHistory(
    String roomId, {
    DateTime? lastSync,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (lastSync != null) {
        queryParams['since'] = lastSync.toIso8601String();
      }

      print('ChatApiService: 嘗試同步端點，參數: $queryParams');

      final response = await apiClient.dio.get(
        '/api/v1/rooms/$roomId/sync',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> messagesJson = response.data['messages'] ?? [];
        final messages =
            messagesJson.map((json) => Message.fromJson(json)).toList();

        // 按時間排序
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        print('ChatApiService: 同步成功，獲取 ${messages.length} 條消息');
        return messages;
      } else if (response.statusCode == 404) {
        print('ChatApiService: 同步端點不存在 (404)，返回空列表');
        return [];
      } else {
        throw Exception('Failed to sync: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 同步聊天歷史失敗: $e');

      // 如果是 404 錯誤，返回空列表而不是拋出異常
      if (e.toString().contains('404')) {
        print('ChatApiService: 同步端點不可用，返回空列表');
        return [];
      }

      throw e;
    }
  }

  /// 後台同步消息（改進錯誤處理）
  static Future<void> _syncMessagesInBackground(String roomId) async {
    try {
      print('ChatApiService: 後台同步房間 $roomId 的消息');

      final lastSync = await MessageCacheService().getLastSyncTime(roomId);
      final newMessages = await syncChatHistory(roomId, lastSync: lastSync);

      if (newMessages.isNotEmpty) {
        await MessageCacheService()
            .syncIncrementalMessages(roomId, newMessages);
        print('ChatApiService: 後台同步完成，新增 ${newMessages.length} 條消息');
      } else {
        print('ChatApiService: 沒有新消息需要同步');
      }
    } catch (e) {
      print('ChatApiService: 後台同步失敗: $e');

      if (e.toString().contains('404') || e.toString().contains('sync')) {
        print('ChatApiService: 同步端點不可用，跳過後台同步');
      } else {
        print('ChatApiService: 其他同步錯誤，但不影響正常使用');
      }
    }
  }

  // ==================== 調試工具 ====================

  /// 獲取消息統計信息（用於調試）
  static Future<Map<String, dynamic>> getMessageStats(String roomId) async {
    try {
      final response = await apiClient.dio.get('/api/v1/rooms/$roomId/stats');

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        return {
          'error': 'HTTP ${response.statusCode}',
          'total_messages': 0,
          'voice_messages': 0,
          'text_messages': 0,
        };
      }
    } catch (e) {
      print('ChatApiService: 獲取消息統計失敗: $e');
      return {
        'error': e.toString(),
        'total_messages': 0,
        'voice_messages': 0,
        'text_messages': 0,
      };
    }
  }

  /// 檢查消息是否存在
  static Future<bool> messageExists(String messageId) async {
    try {
      final response = await apiClient.dio.head('/api/v1/messages/$messageId');
      return response.statusCode == 200;
    } catch (e) {
      print('ChatApiService: 檢查消息存在失敗: $e');
      return false;
    }
  }

  /// 獲取單個消息詳情
  static Future<Message?> getMessage(String messageId) async {
    try {
      final response = await apiClient.dio.get('/api/v1/messages/$messageId');

      if (response.statusCode == 200) {
        return Message.fromJson(response.data['message']);
      } else {
        return null;
      }
    } catch (e) {
      print('ChatApiService: 獲取消息失敗: $e');
      return null;
    }
  }

  /// 批量獲取消息
  static Future<List<Message>> getMessagesByIds(List<String> messageIds) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/messages/batch',
        data: {'message_ids': messageIds},
      );

      if (response.statusCode == 200) {
        final List<dynamic> messagesJson = response.data['messages'] ?? [];
        return messagesJson.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception('Failed to get messages: ${response.statusCode}');
      }
    } catch (e) {
      print('ChatApiService: 批量獲取消息失敗: $e');
      return [];
    }
  }

  // ==================== Reactions API (完善後) ====================

  /// 添加或移除消息 Reaction
  static Future<void> addReaction(String messageId, String emoji) async {
    try {
      final response = await apiClient.dio.post(
        '/api/v1/messages/$messageId/reactions',
        data: {'emoji': emoji},
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('添加 reaction 失敗: ${response.data}');
      }

      print('ChatApiService: 成功添加 reaction: $emoji 到消息 $messageId');
    } catch (e) {
      print('ChatApiService: 添加 reaction 失敗: $e');
      rethrow;
    }
  }

  /// 獲取消息的所有 Reactions
  static Future<Map<String, List<String>>> getMessageReactions(
      String messageId) async {
    try {
      final response = await apiClient.dio.get(
        '/api/v1/messages/$messageId/reactions',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final reactions = <String, List<String>>{};

        if (data != null && data['reactions'] is Map) {
          (data['reactions'] as Map<String, dynamic>).forEach((key, value) {
            if (value is List) {
              reactions[key] = value.map((e) => e.toString()).toList();
            }
          });
        }

        return reactions;
      } else {
        throw Exception('獲取 reactions 失敗: ${response.data}');
      }
    } catch (e) {
      print('ChatApiService: 獲取 reactions 失敗: $e');
      // 在失敗時返回空 map，避免 UI 層出錯
      return {};
    }
  }
}
