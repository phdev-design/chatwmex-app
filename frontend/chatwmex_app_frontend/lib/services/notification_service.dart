import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/message.dart' as app_models;
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool _notificationsEnabled = true;

  String? _currentActiveChatRoom;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      await requestNotificationPermission();

      _isInitialized = true;
      print('NotificationService: 初始化完成');
    } catch (e) {
      print('NotificationService: 初始化失敗: $e');
    }
  }

  // 🔥 新增：模仿 YouTube 教學的簡易通知方法
  // 這個方法可以讓你快速測試一個帶有標題和內容的通知
  Future<void> showSimpleNotification({
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) {
      print('NotificationService: 未初始化，無法顯示通知');
      return;
    }

    // 1. 設定 Android 通知的詳細資訊
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'your_channel_id', // 頻道 ID，必須提供
      'Your Channel Name', // 頻道名稱
      channelDescription: 'Your channel description', // 頻道描述
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    // 2. 設定 iOS 通知的詳細資訊
    const DarwinNotificationDetails darwinNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    // 3. 組合兩個平台的設定
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: darwinNotificationDetails,
    );

    // 4. 顯示通知
    await _notificationsPlugin.show(
      0, // 通知 ID，每個通知應該是唯一的
      title,
      body,
      notificationDetails,
      payload: 'simple_notification_payload', // 點擊通知後可以收到的資料
    );
    print('NotificationService: 已顯示簡易通知');
  }

  void _onNotificationTapped(NotificationResponse notificationResponse) {
    final String? payload = notificationResponse.payload;
    if (payload != null) {
      print('NotificationService: 通知被點擊，payload: $payload');
    }
  }

  void setCurrentActiveChatRoom(String? roomId) {
    _currentActiveChatRoom = roomId;
    print('NotificationService: 設置活躍聊天室: $roomId');
  }

// 🔥 新增：添加 getter 方法，讓外部可以訪問當前活躍聊天室
  String? get currentActiveChatRoom => _currentActiveChatRoom;
  Future<bool> requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      _notificationsEnabled = status.isGranted;
      print('NotificationService: 權限請求結果: $status');
      return _notificationsEnabled;
    } catch (e) {
      print('NotificationService: 手動權限請求失敗: $e');
      return false;
    }
  }

  Future<bool> checkNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      print('NotificationService: 通知權限狀態: $status');
      return status.isGranted;
    } catch (e) {
      print('NotificationService: 檢查權限失敗: $e');
      return false;
    }
  }

  Future<void> showChatNotification({
    required app_models.Message message,
    required String chatRoomName,
  }) async {
    print('=== NotificationService 調試 ===');
    print('初始化狀態: $_isInitialized');
    print('通知啟用狀態: $_notificationsEnabled');
    print('當前活躍聊天室: $_currentActiveChatRoom');
    print('消息房間ID: ${message.roomId}');
    print('聊天室名稱: $chatRoomName');
    print('消息內容: ${message.content}');
    print('發送者: ${message.senderName}');

    if (!_isInitialized || !_notificationsEnabled) {
      print('NotificationService: 通知未初始化或被禁用');
      return;
    }

    if (_currentActiveChatRoom == message.roomId) {
      print('NotificationService: 用戶正在當前聊天室，不顯示通知');
      return;
    }

    print('NotificationService: 準備顯示通知...');

    try {
      if (kDebugMode && Platform.isIOS) {
        print('NotificationService: iOS 模擬器環境，通知可能受限');
      }

      final int notificationId = message.roomId.hashCode;

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'chat_messages',
        '聊天消息',
        channelDescription: '接收聊天室的新消息通知',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(
          message.content,
          contentTitle: '${message.senderName}',
          summaryText: chatRoomName,
        ),
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        notificationId,
        '${message.senderName}',
        message.content,
        notificationDetails,
        payload: message.roomId,
      );

      print(
          'NotificationService: 顯示通知 - ${message.senderName}: ${message.content}');
    } catch (e) {
      print('NotificationService: 顯示通知失敗: $e');

      if (kDebugMode && Platform.isIOS) {
        print('NotificationService: iOS 模擬器通知測試受限，建議在真實設備上測試');
      }
    }
    print('NotificationService: 通知顯示完成');
    print('================================');
  }

  Future<void> clearChatNotifications(String roomId) async {
    try {
      final int notificationId = roomId.hashCode;
      await _notificationsPlugin.cancel(notificationId);
      print('NotificationService: 清除聊天室 $roomId 的通知');
    } catch (e) {
      print('NotificationService: 清除通知失敗: $e');
    }
  }

  Future<void> clearAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      print('NotificationService: 清除所有通知');
    } catch (e) {
      print('NotificationService: 清除所有通知失敗: $e');
    }
  }

  void setNotificationsEnabled(bool enabled) {
    _notificationsEnabled = enabled;
    print('NotificationService: 通知狀態設置為: $enabled');
  }

  bool get isNotificationsEnabled => _notificationsEnabled;

  Future<void> openAppSettings() async {
    try {
      await openAppSettings();

      final status = await Permission.notification.status;
      _notificationsEnabled = status.isGranted;
      print('NotificationService: 用戶從設置返回，權限狀態: $status');
    } catch (e) {
      print('NotificationService: 開啟設置失敗: $e');
    }
  }

  Future<void> showTestNotification() async {
    if (!_isInitialized || !_notificationsEnabled) {
      print('NotificationService: 通知未初始化或被禁用，無法發送測試通知');
      return;
    }

    try {
      if (kDebugMode && Platform.isIOS) {
        print('NotificationService: iOS 模擬器環境，測試通知可能受限');
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'test_notifications',
        '測試通知',
        channelDescription: '用於測試通知功能',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        999,
        'Chat2MeX 測試通知',
        '如果您看到此通知，說明通知功能正常工作',
        notificationDetails,
        payload: 'test',
      );

      print('NotificationService: 測試通知已發送');
    } catch (e) {
      print('NotificationService: 發送測試通知失敗: $e');

      if (kDebugMode && Platform.isIOS) {
        print('NotificationService: iOS 模擬器通知測試受限，建議在真實設備上測試');
      }
    }
  }

  // 在 notification_service.dart 中添加一個臨時的聊天通知方法
Future<void> showChatNotificationSimple({
  required app_models.Message message,
  required String chatRoomName,
}) async {
  print('=== 簡化聊天通知調試 ===');
  
  if (!_isInitialized) {
    print('NotificationService: 服務未初始化');
    return;
  }

  if (_currentActiveChatRoom == message.roomId) {
    print('NotificationService: 用戶正在當前聊天室，不顯示通知');
    return;
  }

  // 🔥 使用與測試通知完全相同的邏輯
  try {
    await showSimpleNotification(
      title: '${message.senderName}',
      body: message.content,
    );
    print('NotificationService: 簡化聊天通知發送成功');
  } catch (e) {
    print('NotificationService: 簡化聊天通知發送失敗: $e');
  }
  
  print('=== 簡化聊天通知結束 ===');
}
}