import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/auth/ui/login_page.dart';
import 'package:app/features/chat/ui/chat_detail_page.dart';
import 'package:app/features/chat/ui/room_list_page.dart';
import 'package:app/core/notification/notification_service.dart';
import 'package:app/core/storage/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize OneSignal
    ref.read(notificationServiceProvider).init();
  }

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/chat-list',
          builder: (context, state) => const RoomListPage(),
        ),
        GoRoute(
          path: '/chat',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            if (extra == null) return const Scaffold(body: Center(child: Text('Error: No params')));
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
        
        if (token == null && !isLoggingIn) return '/login';
        if (token != null && isLoggingIn) return '/chat-list';
        
        return null;
      },
    );

    return MaterialApp.router(
      title: 'ChatWmex',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
