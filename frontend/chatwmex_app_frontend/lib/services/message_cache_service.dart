import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart' as chat_msg;
import '../models/chat_room.dart';

/// 消息緩存服務
/// 負責本地存儲和讀取聊天消息，提升用戶體驗
class MessageCacheService {
  static final MessageCacheService _instance = MessageCacheService._internal();
  factory MessageCacheService() => _instance;
  MessageCacheService._internal();

  static const String _messagesPrefix = 'cached_messages_';
  static const String _roomsPrefix = 'cached_rooms';
  static const String _lastSyncPrefix = 'last_sync_';
  static const String _cacheVersion = 'cache_version';
  static const String _currentVersion = '1.0.0';

  /// 初始化緩存服務
  Future<void> initialize() async {
    try {
      print('MessageCacheService: 初始化消息緩存服務');

      // 檢查緩存版本，必要時清理舊緩存
      await _checkCacheVersion();

      print('MessageCacheService: 緩存服務初始化完成');
    } catch (e) {
      print('MessageCacheService: 初始化失敗: $e');
    }
  }

  /// 檢查緩存版本
  Future<void> _checkCacheVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCacheVersion = prefs.getString(_cacheVersion);

      if (currentCacheVersion != _currentVersion) {
        print('MessageCacheService: 緩存版本不匹配，清理舊緩存');
        await clearAllCache();
        await prefs.setString(_cacheVersion, _currentVersion);
      }
    } catch (e) {
      print('MessageCacheService: 檢查緩存版本失敗: $e');
    }
  }

  // 🔥 修復：改進緩存消息的去重邏輯
  Future<void> cacheRoomMessages(
      String roomId, List<chat_msg.Message> messages) async {
    try {
      print('MessageCacheService: 緩存房間 $roomId 的 ${messages.length} 條消息');

      // 🔥 關鍵修復：多層去重機制
      final uniqueMessages = <String, chat_msg.Message>{};
      final contentTimeIndex = <String, chat_msg.Message>{};
      
      for (final message in messages) {
        // 跳過無效消息
        if (message.id.isEmpty) {
          print('MessageCacheService: 警告 - 發現空 ID 消息: ${message.content}');
          continue;
        }

        // 跳過臨時消息
        if (message.id.startsWith('temp_')) {
          print('MessageCacheService: 跳過臨時消息: ${message.id}');
          continue;
        }

        // 第一層：ID 去重
        if (uniqueMessages.containsKey(message.id)) {
          print('MessageCacheService: 發現重複ID消息: ${message.id}');
          continue;
        }

        // 第二層：內容+時間去重（處理不同ID但內容相同的情況）
        final contentTimeKey = '${message.senderId}_${message.content}_${message.timestamp.millisecondsSinceEpoch ~/ 1000}';
        if (contentTimeIndex.containsKey(contentTimeKey)) {
          print('MessageCacheService: 發現重複內容消息: ${message.content} at ${message.timestamp}');
          continue;
        }

        uniqueMessages[message.id] = message;
        contentTimeIndex[contentTimeKey] = message;
      }

      final finalMessages = uniqueMessages.values.toList();
      finalMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      print('MessageCacheService: 去重前: ${messages.length}, 去重後: ${finalMessages.length}');

      final prefs = await SharedPreferences.getInstance();
      final messagesJson = finalMessages.map((msg) => msg.toJson()).toList();
      final messagesString = jsonEncode(messagesJson);

      await prefs.setString('$_messagesPrefix$roomId', messagesString);
      await prefs.setString(
          '$_lastSyncPrefix$roomId', DateTime.now().toIso8601String());

      print('MessageCacheService: 房間 $roomId 消息緩存完成');
      print('MessageCacheService: 緩存詳情 - 總計: ${finalMessages.length}, 語音: ${finalMessages.where((m) => m.type == chat_msg.MessageType.voice).length}');
    } catch (e) {
      print('MessageCacheService: 緩存消息失敗: $e');
    }
  }

  // 🔥 修改：改進讀取緩存消息的方法
  Future<List<chat_msg.Message>> getCachedRoomMessages(String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesString = prefs.getString('$_messagesPrefix$roomId');

      if (messagesString == null) {
        print('MessageCacheService: 房間 $roomId 沒有緩存消息');
        return [];
      }

      final messagesJson = jsonDecode(messagesString) as List;
      final messages = <chat_msg.Message>[];

      print('MessageCacheService: 開始解析緩存中的 ${messagesJson.length} 條消息');

      for (int i = 0; i < messagesJson.length; i++) {
        try {
          final message = chat_msg.Message.fromJson(messagesJson[i]);
          messages.add(message);
        } catch (e) {
          print('MessageCacheService: 解析緩存消息 $i 失敗: $e');
          // 繼續處理其他消息
        }
      }

      print('MessageCacheService: 從緩存成功讀取房間 $roomId 的 ${messages.length} 條消息');
      return messages;
    } catch (e) {
      print('MessageCacheService: 讀取緩存消息失敗: $e');
      return [];
    }
  }

  // 🔥 修復：改進添加單條消息到緩存的方法
  Future<void> addMessageToCache(
      String roomId, chat_msg.Message message) async {
    try {
      // 跳過臨時消息
      if (message.id.startsWith('temp_')) {
        print('MessageCacheService: 跳過緩存臨時消息: ${message.id}');
        return;
      }

      final existingMessages = await getCachedRoomMessages(roomId);

      // 🔥 關鍵修復：多重檢查避免重複
      // 檢查ID重複
      if (existingMessages.any((msg) => msg.id == message.id)) {
        print('MessageCacheService: 消息 ${message.id} 已存在於緩存中（ID重複）');
        return;
      }

      // 檢查內容重複（同一發送者在3秒內的相同內容）
      final isDuplicate = existingMessages.any((msg) => 
        msg.senderId == message.senderId &&
        msg.content == message.content &&
        msg.timestamp.difference(message.timestamp).abs().inSeconds < 3
      );

      if (isDuplicate) {
        print('MessageCacheService: 消息 ${message.id} 內容重複，跳過緩存');
        return;
      }

      // 添加新消息到列表開頭
      existingMessages.insert(0, message);

      // 限制緩存消息數量
      const maxCachedMessages = 100;
      if (existingMessages.length > maxCachedMessages) {
        existingMessages.removeRange(
            maxCachedMessages, existingMessages.length);
      }

      await cacheRoomMessages(roomId, existingMessages);
      print('MessageCacheService: 消息 ${message.id} 已添加到緩存');
    } catch (e) {
      print('MessageCacheService: 添加消息到緩存失敗: $e');
    }
  }

  /// 緩存聊天室列表
  Future<void> cacheChatRooms(List<ChatRoom> rooms) async {
    try {
      print('MessageCacheService: 緩存 ${rooms.length} 個聊天室');

      final prefs = await SharedPreferences.getInstance();
      final roomsJson = rooms.map((room) => room.toJson()).toList();
      final roomsString = jsonEncode(roomsJson);

      await prefs.setString(_roomsPrefix, roomsString);
      await prefs.setString(
          '${_lastSyncPrefix}rooms', DateTime.now().toIso8601String());

      print('MessageCacheService: 聊天室列表緩存完成');
    } catch (e) {
      print('MessageCacheService: 緩存聊天室列表失敗: $e');
    }
  }

  /// 讀取緩存的聊天室列表
  Future<List<ChatRoom>> getCachedChatRooms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final roomsString = prefs.getString(_roomsPrefix);

      if (roomsString == null) {
        print('MessageCacheService: 沒有緩存的聊天室列表');
        return [];
      }

      final roomsJson = jsonDecode(roomsString) as List;
      final rooms = roomsJson.map((json) => ChatRoom.fromJson(json)).toList();

      print('MessageCacheService: 從緩存讀取 ${rooms.length} 個聊天室');
      return rooms;
    } catch (e) {
      print('MessageCacheService: 讀取緩存聊天室列表失敗: $e');
      return [];
    }
  }

  /// 獲取最後同步時間
  Future<DateTime?> getLastSyncTime(String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final syncTimeString = prefs.getString('$_lastSyncPrefix$roomId');

      if (syncTimeString == null) return null;

      return DateTime.parse(syncTimeString);
    } catch (e) {
      print('MessageCacheService: 獲取最後同步時間失敗: $e');
      return null;
    }
  }

  /// 設置最後同步時間
  Future<void> setLastSyncTime(String roomId, DateTime syncTime) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '$_lastSyncPrefix$roomId', syncTime.toIso8601String());
      print('MessageCacheService: 設置最後同步時間成功: $roomId -> $syncTime');
    } catch (e) {
      print('MessageCacheService: 設置最後同步時間失敗: $e');
    }
  }

  /// 檢查緩存是否過期
  Future<bool> isCacheExpired(String roomId,
      {Duration maxAge = const Duration(hours: 1)}) async {
    try {
      final lastSync = await getLastSyncTime(roomId);
      if (lastSync == null) return true;

      final now = DateTime.now();
      final age = now.difference(lastSync);

      return age > maxAge;
    } catch (e) {
      print('MessageCacheService: 檢查緩存過期失敗: $e');
      return true;
    }
  }

  /// 智能獲取消息（先讀取緩存，再決定是否同步服務器）
  Future<List<chat_msg.Message>> getSmartMessages(String roomId) async {
    try {
      print('MessageCacheService: 智能獲取房間 $roomId 的消息');

      // 先讀取緩存
      final cachedMessages = await getCachedRoomMessages(roomId);

      // 檢查緩存是否過期
      final isExpired = await isCacheExpired(roomId);

      if (cachedMessages.isNotEmpty && !isExpired) {
        print('MessageCacheService: 使用緩存消息，共 ${cachedMessages.length} 條');
        return cachedMessages;
      } else {
        print('MessageCacheService: 緩存過期或為空，需要從服務器同步');
        return [];
      }
    } catch (e) {
      print('MessageCacheService: 智能獲取消息失敗: $e');
      return [];
    }
  }

  /// 增量同步消息
  Future<List<chat_msg.Message>> syncIncrementalMessages(
      String roomId, List<chat_msg.Message> newMessages) async {
    try {
      print('MessageCacheService: 增量同步房間 $roomId 的 ${newMessages.length} 條新消息');

      final cachedMessages = await getCachedRoomMessages(roomId);
      final cachedMessageIds = cachedMessages.map((msg) => msg.id).toSet();

      // 過濾出真正的新消息
      final trulyNewMessages = newMessages
          .where((msg) => !cachedMessageIds.contains(msg.id))
          .toList();

      if (trulyNewMessages.isNotEmpty) {
        // 將新消息添加到緩存
        for (final message in trulyNewMessages) {
          await addMessageToCache(roomId, message);
        }

        print('MessageCacheService: 增量同步完成，新增 ${trulyNewMessages.length} 條消息');
      } else {
        print('MessageCacheService: 沒有新消息需要同步');
      }

      return await getCachedRoomMessages(roomId);
    } catch (e) {
      print('MessageCacheService: 增量同步失敗: $e');
      return await getCachedRoomMessages(roomId);
    }
  }

  // 🔥 新增：檢查消息是否已在緩存中
  Future<bool> isMessageCached(String roomId, String messageId) async {
    try {
      if (messageId.startsWith('temp_')) return false;
      
      final cachedMessages = await getCachedRoomMessages(roomId);
      return cachedMessages.any((msg) => msg.id == messageId);
    } catch (e) {
      print('MessageCacheService: 檢查消息緩存狀態失敗: $e');
      return false;
    }
  }

  // 🔥 新增：清理重複消息的方法
  Future<void> deduplicateRoomMessages(String roomId) async {
    try {
      print('MessageCacheService: 開始去重房間 $roomId 的消息');
      
      final messages = await getCachedRoomMessages(roomId);
      if (messages.isEmpty) return;

      // 使用改進的緩存方法，它會自動去重
      await cacheRoomMessages(roomId, messages);
      
      print('MessageCacheService: 房間 $roomId 消息去重完成');
    } catch (e) {
      print('MessageCacheService: 消息去重失敗: $e');
    }
  }

  // 🔥 新增：檢查緩存數據完整性
  Future<Map<String, dynamic>> checkCacheIntegrity(String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesString = prefs.getString('$_messagesPrefix$roomId');

      if (messagesString == null) {
        return {
          'has_cache': false,
          'message_count': 0,
          'voice_count': 0,
          'text_count': 0,
          'cache_size': 0,
        };
      }

      final messagesJson = jsonDecode(messagesString) as List;
      final voiceCount =
          messagesJson.where((json) => json['type'] == 'voice').length;
      final textCount =
          messagesJson.where((json) => json['type'] == 'text').length;

      return {
        'has_cache': true,
        'message_count': messagesJson.length,
        'voice_count': voiceCount,
        'text_count': textCount,
        'cache_size': messagesString.length,
        'last_sync': prefs.getString('$_lastSyncPrefix$roomId'),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // 🔥 強制清除特定房間緩存
  Future<void> clearRoomCache(String roomId) async {
    try {
      print('MessageCacheService: 清除房間 $roomId 的緩存');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_messagesPrefix$roomId');
      await prefs.remove('$_lastSyncPrefix$roomId');
      print('MessageCacheService: 房間 $roomId 緩存清除完成');
    } catch (e) {
      print('MessageCacheService: 清除緩存失敗: $e');
    }
  }

  /// 清理所有緩存
  Future<void> clearAllCache() async {
    try {
      print('MessageCacheService: 清理所有緩存');

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith(_messagesPrefix) ||
            key.startsWith(_lastSyncPrefix) ||
            key == _roomsPrefix) {
          await prefs.remove(key);
        }
      }

      print('MessageCacheService: 所有緩存已清理');
    } catch (e) {
      print('MessageCacheService: 清理所有緩存失敗: $e');
    }
  }

  /// 獲取緩存統計信息
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      int messageCacheCount = 0;
      int roomCacheCount = 0;
      int totalCacheSize = 0;

      for (final key in keys) {
        if (key.startsWith(_messagesPrefix)) {
          messageCacheCount++;
          final value = prefs.getString(key);
          if (value != null) totalCacheSize += value.length;
        } else if (key == _roomsPrefix) {
          roomCacheCount++;
          final value = prefs.getString(key);
          if (value != null) totalCacheSize += value.length;
        }
      }

      return {
        'messageCacheCount': messageCacheCount,
        'roomCacheCount': roomCacheCount,
        'totalCacheSize': totalCacheSize,
        'cacheVersion': _currentVersion,
      };
    } catch (e) {
      print('MessageCacheService: 獲取緩存統計失敗: $e');
      return {};
    }
  }

  /// 優化緩存（清理舊數據）
  Future<void> optimizeCache() async {
    try {
      print('MessageCacheService: 開始優化緩存');

      final stats = await getCacheStats();
      final totalSize = stats['totalCacheSize'] as int;

      // 如果緩存大小超過 5MB，清理最舊的緩存
      if (totalSize > 5 * 1024 * 1024) {
        print('MessageCacheService: 緩存大小過大，開始清理');
        await _cleanOldCache();
      }

      print('MessageCacheService: 緩存優化完成');
    } catch (e) {
      print('MessageCacheService: 緩存優化失敗: $e');
    }
  }

  /// 清理舊緩存
  Future<void> _cleanOldCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final syncTimes = <String, DateTime>{};

      // 收集所有同步時間
      for (final key in keys) {
        if (key.startsWith(_lastSyncPrefix)) {
          final roomId = key.substring(_lastSyncPrefix.length);
          final syncTimeString = prefs.getString(key);
          if (syncTimeString != null) {
            syncTimes[roomId] = DateTime.parse(syncTimeString);
          }
        }
      }

      // 按時間排序，清理最舊的 50%
      final sortedRooms = syncTimes.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final roomsToClean =
          sortedRooms.take(sortedRooms.length ~/ 2).map((e) => e.key).toList();

      for (final roomId in roomsToClean) {
        await clearRoomCache(roomId);
      }

      print('MessageCacheService: 已清理 ${roomsToClean.length} 個房間的緩存');
    } catch (e) {
      print('MessageCacheService: 清理舊緩存失敗: $e');
    }
  }

  // 🔥 新增：診斷緩存問題的方法
  Future<void> diagnoseCacheIssues(String roomId) async {
    try {
      print('MessageCacheService: 開始診斷房間 $roomId 的緩存問題');

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      print('  所有緩存鍵: ${keys.where((k) => k.contains(roomId)).toList()}');

      final messagesString = prefs.getString('$_messagesPrefix$roomId');
      if (messagesString != null) {
        print('  緩存大小: ${messagesString.length} 字符');
        try {
          final messagesJson = jsonDecode(messagesString) as List;
          print('  緩存消息數量: ${messagesJson.length}');

          for (int i = 0; i < messagesJson.length; i++) {
            final json = messagesJson[i];
            print(
                '    消息 $i: ID=${json['id']}, Type=${json['type']}, Time=${json['timestamp']}');
          }
        } catch (e) {
          print('  緩存數據格式錯誤: $e');
        }
      } else {
        print('  沒有找到緩存數據');
      }

      final lastSync = prefs.getString('$_lastSyncPrefix$roomId');
      print('  最後同步時間: $lastSync');

    } catch (e) {
      print('MessageCacheService: 診斷失敗: $e');
    }
  }
}
