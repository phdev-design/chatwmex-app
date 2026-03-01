import 'package:flutter/material.dart';
import '../../../services/chat_service.dart';

/// 管理 Widget 生命週期的 Mixin
mixin ChatLifecycleHandler<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  // 讓使用此 Mixin 的 State 實現這些 getter
  ChatService get chatService;
  String get chatRoomId;
  VoidCallback get onAppResumed;
  VoidCallback get onAppPaused;

  // 🔥 修正：改為提供初始化方法而非覆寫 initState
  void initializeLifecycleHandler() {
    WidgetsBinding.instance.addObserver(this);
    chatService.setCurrentActiveChatRoom(chatRoomId);
  }

  // 🔥 修正：改為提供清理方法而非覆寫 dispose
  void disposeLifecycleHandler() {
    WidgetsBinding.instance.removeObserver(this);
    chatService.unregisterMessageListener('chat_detail_page');
    chatService.unregisterConnectionListener('chat_detail_page');
    chatService.setCurrentActiveChatRoom(null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        chatService.setCurrentActiveChatRoom(chatRoomId);
        onAppResumed();
        break;
      case AppLifecycleState.paused:
        chatService.setCurrentActiveChatRoom(null);
        onAppPaused();
        break;
      default:
        break;
    }
  }
}
