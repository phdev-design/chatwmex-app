import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/auth/repositories/auth_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    final token = await ref.read(storageServiceProvider).read('jwt_token');
    if (!mounted) return;
    if (!mounted) return;
    if (token != null) {
      try {
        final crypto = ref.read(cryptoServiceProvider);
        final pubKey = await crypto.initialize();
        await ref.read(authRepositoryProvider).updatePublicKey(pubKey);
      } catch (e) {
        print('Crypto init failed on splash: $e');
      }
      if (!mounted) return;
      context.go('/chat-list');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              'Chat2MeX',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
