import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationService {
  Future<void> init() async {
    OneSignal.initialize("88247551-a540-4ffc-89aa-e6ea9478b7be");

    // The promptForPushNotificationsWithUserResponse function will show the iOS or Android push notification prompt. We recommend removing the following code and instead using an In-App Message to prompt for notification permission
    OneSignal.Notifications.requestPermission(true);
    
    // Listen for click
    OneSignal.Notifications.addClickListener((event) {
      print('NOTIFICATION CLICK LISTENER CALLED WITH EVENT: $event');
      // Navigate to chat?
    });
  }

  Future<String?> getSubscriptionId() async {
    return OneSignal.User.pushSubscription.id;
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});
