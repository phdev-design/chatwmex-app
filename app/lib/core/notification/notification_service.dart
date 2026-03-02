import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/storage/storage_service.dart';

class NotificationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final StorageService _storageService;

  NotificationService(this._storageService);

  Future<void> initOneSignal(String appId) async {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(appId);
    OneSignal.Notifications.requestPermission(true);
    OneSignal.Notifications.addClickListener((event) {
      _handleNotificationClick(event);
    });
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
  return NotificationService(storage);
});
