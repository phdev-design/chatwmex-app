import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart' as chat_msg;
import '../models/chat_room.dart';
import 'database_helper.dart';

/// 消息緩存服務 (Refactored to use SQLite via DatabaseHelper)
/// 負責本地存儲和讀取聊天消息，提升用戶體驗
class MessageCacheService {
  static final MessageCacheService _instance = MessageCacheService._internal();
  factory MessageCacheService() => _instance;
  MessageCacheService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  static const String _lastSyncPrefix = 'last_sync_';

  /// 初始化緩存服務
  Future<void> initialize() async {
    try {
      print('MessageCacheService: 初始化消息緩存服務 (SQLite)');
      // DB is initialized on first access
      await _dbHelper.database; 
      print('MessageCacheService: 緩存服務初始化完成');
    } catch (e) {
      print('MessageCacheService: 初始化失敗: $e');
    }
  }

  // 🔥 緩存消息
  Future<void> cacheRoomMessages(
      String roomId, List<chat_msg.Message> messages) async {
    try {
      print('MessageCacheService: 緩存房間 $roomId 的 ${messages.length} 條消息');
      if (messages.isEmpty) return;
      
      await _dbHelper.insertMessages(messages);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          '$_lastSyncPrefix$roomId', DateTime.now().toIso8601String());
          
      print('MessageCacheService: 消息已寫入 SQLite');
    } catch (e) {
      print('MessageCacheService: 緩存消息失敗: $e');
    }
  }

  // 🔥 添加單條消息到緩存
  Future<void> addMessageToCache(
      String roomId, chat_msg.Message message) async {
    try {
      print('MessageCacheService: 添加單條消息到緩存');
      await _dbHelper.insertMessage(message);
    } catch (e) {
      print('MessageCacheService: 添加消息緩存失敗: $e');
    }
  }

  // 🔥 獲取緩存消息
  Future<List<chat_msg.Message>> getCachedRoomMessages(String roomId) async {
    try {
      print('MessageCacheService: 從 SQLite 讀取消息');
      final messages = await _dbHelper.getMessages(roomId);
      print('MessageCacheService: 讀取到 ${messages.length} 條緩存消息');
      return messages;
    } catch (e) {
      print('MessageCacheService: 讀取緩存消息失敗: $e');
      return [];
    }
  }

  // 🔥 緩存聊天室列表
  Future<void> cacheChatRooms(List<ChatRoom> rooms) async {
    try {
      print('MessageCacheService: 緩存 ${rooms.length} 個聊天室');
      await _dbHelper.insertChatRooms(rooms);
    } catch (e) {
      print('MessageCacheService: 緩存聊天室失敗: $e');
    }
  }

  // 🔥 獲取緩存聊天室列表
  Future<List<ChatRoom>> getCachedChatRooms() async {
    try {
      print('MessageCacheService: 從 SQLite 讀取聊天室列表');
      return await _dbHelper.getChatRooms();
    } catch (e) {
      print('MessageCacheService: 讀取緩存聊天室失敗: $e');
      return [];
    }
  }

  Future<void> clearAllCache() async {
    // Ideally drop tables or delete all rows.
    // For now we might not need this often.
    // We can implement delete all in DB helper if needed.
    print('MessageCacheService: Clear cache requested but not fully implemented for SQLite yet.');
  }
}
