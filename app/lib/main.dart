import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/auth/ui/login_page.dart';
import 'package:app/features/chat/ui/chat_detail_page.dart';
import 'package:app/core/storage/storage_service.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/chat',
          builder: (context, state) {
            // Mocking data for now as we don't have a chat list page yet
            return const ChatDetailPage(
              roomId: 'room1',
              title: 'Test Chat',
              isRoom: true,
              currentUserId: 'user1',
              token: 'dev_token', // Should be retrieved from storage/provider
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
        if (token != null && isLoggingIn) return '/chat';
        
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
