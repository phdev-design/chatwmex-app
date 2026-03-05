import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/auth/ui/login_page.dart';
import 'package:app/features/chat/ui/chat_detail_page.dart';
import 'package:app/features/chat/ui/room_list_page.dart';
import 'package:app/features/chat/ui/contact_info_page.dart'; // <--- 匯入新的聯絡人頁面
import 'package:app/features/splash/ui/splash_screen.dart';
import 'package:app/features/friend/ui/add_friend_page.dart';
import 'package:app/features/friend/ui/friend_requests_page.dart';
import 'package:app/features/friend/ui/new_chat_page.dart';
import 'package:app/features/profile/ui/profile_page.dart';
import 'package:app/core/theme/theme.dart';
import 'package:app/core/notification/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      navigatorKey: NotificationService.navigatorKey,
      initialLocation: '/splash',
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        GoRoute(
          path: '/chat-list',
          builder: (context, state) => const RoomListPage(),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfilePage(),
        ),
        GoRoute(
          path: '/new-chat',
          builder: (context, state) => const NewChatPage(),
        ),
        GoRoute(
          path: '/add-friend',
          builder: (context, state) => const AddFriendPage(),
        ),
        GoRoute(
          path: '/friend-requests',
          builder: (context, state) => const FriendRequestsPage(),
        ),
        GoRoute(
          path: '/chat',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            if (extra == null) {
              return const Scaffold(
                body: Center(child: Text('Error: No params')),
              );
            }
            return ChatDetailPage(
              roomId: extra['roomId'],
              title: extra['title'],
              isRoom: extra['isRoom'],
              currentUserId: extra['currentUserId'],
              token: extra['token'],
              avatarUrl: extra['avatarUrl'],
            );
          },
        ),
        // 新增的聯絡人資料路由
        GoRoute(
          path: '/contact-info',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return ContactInfoPage(
              roomId: extra['roomId'] ?? '',
              title: extra['title'] ?? 'Unknown',
              isRoom: extra['isRoom'] ?? false,
              avatarUrl: extra['avatarUrl'],
              mediaCount: extra['mediaCount'] ?? 0,
            );
          },
        ),
      ],
    );

    return MaterialApp.router(
      title: 'ChatWmex',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
