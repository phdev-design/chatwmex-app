import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../utils/token_storage.dart';
import 'chat_api_service.dart' as api_service;
import 'message_cache_service.dart';
import 'notification_service.dart';

/// 背景同步服務
class BackgroundSyncService {
  static final BackgroundSyncService _instance =
      BackgroundSyncService._internal();
  factory BackgroundSyncService() => _instance;
  BackgroundSyncService._internal();

  static const String _taskName = 'backgroundSync';
  static const String _taskId = 'chat_sync_task';

  bool _isInitialized = false;
  Timer? _syncTimer;

  /// 初始化背景同步服務
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 初始化 WorkManager
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );

      // 註冊背景任務
      await _registerBackgroundTask();

      _isInitialized = true;
      print('BackgroundSyncService: 背景同步服務初始化完成');
    } catch (e) {
      print('BackgroundSyncService: 背景同步服務初始化失敗: $e');
    }
  }

  /// 註冊背景任務
  Future<void> _registerBackgroundTask() async {
    try {
      // 註冊定期同步任務
      await Workmanager().registerPeriodicTask(
        _taskId,
        _taskName,
        frequency: const Duration(minutes: 15), // 每15分鐘同步一次
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
      );

      print('BackgroundSyncService: 背景任務註冊成功');
    } catch (e) {
      print('BackgroundSyncService: 背景任務註冊失敗: $e');
    }
  }

  /// 啟動背景同步
  Future<void> startBackgroundSync() async {
    try {
      print('BackgroundSyncService: 啟動背景同步');

      // 立即執行一次同步
      await _performSync();

      // 設置定期同步
      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(
        const Duration(minutes: 5), // 每5分鐘同步一次
        (timer) => _performSync(),
      );
    } catch (e) {
      print('BackgroundSyncService: 啟動背景同步失敗: $e');
    }
  }

  /// 停止背景同步
  void stopBackgroundSync() {
    try {
      print('BackgroundSyncService: 停止背景同步');
      _syncTimer?.cancel();
      _syncTimer = null;
    } catch (e) {
      print('BackgroundSyncService: 停止背景同步失敗: $e');
    }
  }

  /// 執行同步
  Future<void> _performSync() async {
    try {
      print('BackgroundSyncService: 開始背景同步');

      // 檢查是否已登入
      final isLoggedIn = await TokenStorage.isLoggedIn();
      if (!isLoggedIn) {
        print('BackgroundSyncService: 用戶未登入，跳過同步');
        return;
      }

      // 同步聊天室列表
      await _syncChatRooms();

      // 同步未讀消息
      await _syncUnreadMessages();

      print('BackgroundSyncService: 背景同步完成');
    } catch (e) {
      print('BackgroundSyncService: 背景同步失敗: $e');
    }
  }

  /// 同步聊天室列表
  Future<void> _syncChatRooms() async {
    try {
      print('BackgroundSyncService: 同步聊天室列表');

      final chatRooms = await api_service.ChatApiService.getChatRooms();
      await MessageCacheService().cacheChatRooms(chatRooms);

      print('BackgroundSyncService: 聊天室列表同步完成，${chatRooms.length} 個聊天室');
    } catch (e) {
      print('BackgroundSyncService: 聊天室列表同步失敗: $e');
    }
  }

  /// 同步未讀消息
  Future<void> _syncUnreadMessages() async {
    try {
      print('BackgroundSyncService: 同步未讀消息');

      final cacheService = MessageCacheService();
      final chatRooms = await cacheService.getCachedChatRooms();

      for (final room in chatRooms) {
        try {
          // 獲取最新消息
          final messages = await api_service.ChatApiService.getChatHistory(
            room.id,
            page: 1,
            limit: 10,
          );

          if (messages.isNotEmpty) {
            // 更新緩存
            await cacheService.cacheRoomMessages(room.id, messages);

            // 檢查是否有新消息需要通知
            await _checkForNewMessages(room, messages);
          }
        } catch (e) {
          print('BackgroundSyncService: 同步房間 ${room.id} 消息失敗: $e');
        }
      }

      print('BackgroundSyncService: 未讀消息同步完成');
    } catch (e) {
      print('BackgroundSyncService: 未讀消息同步失敗: $e');
    }
  }

  /// 檢查新消息並發送通知
  Future<void> _checkForNewMessages(room, messages) async {
    try {
      final notificationService = NotificationService();

      // 獲取最後已知的消息時間
      final lastSyncTime = await MessageCacheService().getLastSyncTime(room.id);

      for (final message in messages) {
        // 如果是新消息（時間晚於最後同步時間）
        if (lastSyncTime == null || message.timestamp.isAfter(lastSyncTime)) {
          // 檢查是否為語音消息
          if (message.type.toString() == 'MessageType.voice') {
            await notificationService.showChatNotification(
              message: message,
              chatRoomName: room.name,
            );
          } else {
            await notificationService.showChatNotification(
              message: message,
              chatRoomName: room.name,
            );
          }
        }
      }

      // 更新最後同步時間
      if (messages.isNotEmpty) {
        final latestMessage = messages.last;
        await MessageCacheService()
            .setLastSyncTime(room.id, latestMessage.timestamp);
      }
    } catch (e) {
      print('BackgroundSyncService: 檢查新消息失敗: $e');
    }
  }

  /// 手動觸發同步
  Future<void> triggerSync() async {
    try {
      print('BackgroundSyncService: 手動觸發同步');
      await _performSync();
    } catch (e) {
      print('BackgroundSyncService: 手動同步失敗: $e');
    }
  }

  /// 清理資源
  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _isInitialized = false;
  }
}

/// 背景任務回調函數
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      print('BackgroundSyncService: 執行背景任務: $task');

      switch (task) {
        case 'backgroundSync':
          await _executeBackgroundSync();
          break;
        default:
          print('BackgroundSyncService: 未知的背景任務: $task');
      }

      return Future.value(true);
    } catch (e) {
      print('BackgroundSyncService: 背景任務執行失敗: $e');
      return Future.value(false);
    }
  });
}

/// 執行背景同步
Future<void> _executeBackgroundSync() async {
  try {
    print('BackgroundSyncService: 執行背景同步');

    // 檢查是否已登入
    final isLoggedIn = await TokenStorage.isLoggedIn();
    if (!isLoggedIn) {
      print('BackgroundSyncService: 用戶未登入，跳過背景同步');
      return;
    }

    // 同步聊天室列表
    final chatRooms = await api_service.ChatApiService.getChatRooms();
    await MessageCacheService().cacheChatRooms(chatRooms);

    // 同步每個聊天室的最新消息
    for (final room in chatRooms) {
      try {
        final messages = await api_service.ChatApiService.getChatHistory(
          room.id,
          page: 1,
          limit: 5,
        );

        if (messages.isNotEmpty) {
          await MessageCacheService().cacheRoomMessages(room.id, messages);
        }
      } catch (e) {
        print('BackgroundSyncService: 同步房間 ${room.id} 失敗: $e');
      }
    }

    print('BackgroundSyncService: 背景同步完成');
  } catch (e) {
    print('BackgroundSyncService: 背景同步執行失敗: $e');
  }
}
