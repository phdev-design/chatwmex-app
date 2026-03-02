import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/auth/ui/login_page.dart';
import 'package:app/features/chat/ui/chat_detail_page.dart';
import 'package:app/features/chat/ui/room_list_page.dart';
import 'package:app/features/friend/ui/add_friend_page.dart';
import 'package:app/features/friend/ui/friend_requests_page.dart';
import 'package:app/features/friend/ui/new_chat_page.dart';
import 'package:app/features/profile/ui/profile_page.dart';
import 'package:app/core/storage/storage_service.dart';
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
      initialLocation: '/login',
      routes: [
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
            );
          },
        ),
      ],
      redirect: (context, state) async {
        // Simple auth check
        final storage = ref.read(storageServiceProvider);
        final token = await storage.read('jwt_token');

        final isLoggingIn = state.uri.toString() == '/login';

        if (token == null && !isLoggingIn) {
          return '/login';
        }
        if (token != null && isLoggingIn) {
          return '/chat-list';
        }

        return null;
      },
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
