import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/network/network_service.dart';
import 'package:dio/dio.dart';
class NotificationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static String? currentActiveRoomId;

  final StorageService _storageService;
  final NetworkService _networkService;

  NotificationService(this._storageService, this._networkService);

  Future<void> initOneSignal(String appId) async {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(appId);
    OneSignal.Notifications.requestPermission(true);

    OneSignal.Notifications.addClickListener((event) {
      _handleNotificationClick(event);
    });

    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      _handleForegroundNotification(event);
      _handleMessageDelivered(event.notification.additionalData);
    });

    // 👇 刪除或註解掉以下這段程式碼 👇
    // OneSignal.Notifications.addBackgroundWillDisplayListener((event) {
    //   _handleMessageDelivered(event.notification.additionalData);
    // });

    await handlePendingNavigation();
  }

  Future<String?> getSubscriptionId() async {
    return OneSignal.User.pushSubscription.id;
  }

  Future<void> handlePendingNavigation() async {
    final pendingRoomId = await _storageService.read('pending_room_id');
    if (pendingRoomId == null || pendingRoomId.isEmpty) {
      return;
    }
    await _storageService.delete('pending_room_id');
    await _navigateToRoom(
      roomId: pendingRoomId,
      title: await _storageService.read('pending_room_title') ?? pendingRoomId,
      isRoom: (await _storageService.read('pending_is_room')) == 'true',
    );
    await _storageService.delete('pending_room_title');
    await _storageService.delete('pending_is_room');
  }

  void _handleForegroundNotification(OSNotificationWillDisplayEvent event) {
    final data = event.notification.additionalData;
    if (data == null) return;

    final roomId = data['room_id']?.toString() ?? '';
    if (roomId.isNotEmpty && roomId == currentActiveRoomId) {
      event
          .preventDefault(); // Suspend the banner if user is in this active room
    }
  }

Future<void> _handleMessageDelivered(Map<String, dynamic>? data) async {
    if (data == null) return;

    final messageId = data['message_id']?.toString() ?? '';
    if (messageId.isEmpty) return;

    try {
      await _networkService.client.post(
        '/messages/delivered',
        data: {
          'message_ids': [messageId],
        },
      );
      debugPrint('Background delivered report sent for $messageId');
      
    } on DioException catch (e) {
      // 專門捕捉 Dio 的網路錯誤
      if (e.type == DioExceptionType.receiveTimeout || 
          e.type == DioExceptionType.connectionTimeout) {
        // 系統在背景限制了網路連線，這是正常現象，我們只印出 Log 忽略它
        debugPrint('系統限制背景連線 (Timeout)，略過回報訊息 $messageId');
      } else {
        // 其他的 API 錯誤（例如 404, 500 等）
        debugPrint('Dio API 錯誤 (回報訊息狀態): ${e.message}');
      }
      
    } catch (e) {
      // 捕捉其他非網路相關的例外錯誤
      debugPrint('Failed to report delivered: $e');
    }
  }

  Future<void> _handleNotificationClick(OSNotificationClickEvent event) async {
    final data = event.notification.additionalData;
    if (data == null) return;
    final roomId = data['room_id']?.toString() ?? '';
    if (roomId.isEmpty) return;

    final title =
        data['room_name']?.toString() ?? data['title']?.toString() ?? roomId;

    bool isRoom = false;
    final isRoomRaw = data['is_room'];
    if (isRoomRaw is bool) {
      isRoom = isRoomRaw;
    } else if (isRoomRaw is String) {
      isRoom = isRoomRaw.toLowerCase() == 'true';
    }

    await _navigateToRoom(roomId: roomId, title: title, isRoom: isRoom);
  }

  Future<void> _navigateToRoom({
    required String roomId,
    required String title,
    required bool isRoom,
  }) async {
    final currentUserId = await _storageService.read('user_id');
    final token = await _storageService.read('jwt_token');
    if (currentUserId == null || token == null) {
      await _storageService.save('pending_room_id', roomId);
      await _storageService.save('pending_room_title', title);
      await _storageService.save('pending_is_room', isRoom.toString());
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      await _storageService.save('pending_room_id', roomId);
      await _storageService.save('pending_room_title', title);
      await _storageService.save('pending_is_room', isRoom.toString());
      return;
    }

    GoRouter.of(context).go(
      '/chat',
      extra: {
        'roomId': roomId,
        'title': title,
        'isRoom': isRoom,
        'currentUserId': currentUserId,
        'token': token,
      },
    );
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final network = ref.read(networkServiceProvider);
  return NotificationService(storage, network);
});
