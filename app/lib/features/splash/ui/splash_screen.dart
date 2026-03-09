import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/notification/notification_service.dart';
import 'package:app/features/auth/repositories/auth_repository.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'dart:io';

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
    // 1. 同時執行「等待 2 秒」和「輕量的 Token 檢查」
    // 這樣可以保證畫面最少、也最多只會卡 2 秒鐘
    final results = await Future.wait([
      Future.delayed(const Duration(seconds: 2)),
      _checkToken(),
    ]);

    final hasToken = results[1] as bool;

    if (!mounted) return;

    if (hasToken) {
      // 2. Token 存在，啟動背景耗時任務 (不加 await，讓它異步執行！)
      _loadHeavyDataInBackground();
      
      // 3. 2秒一到立即跳轉，不被背景 API 請求卡住
      context.go('/chat-list');
    } else {
      context.go('/login');
    }
  }

  /// 極速檢查本地 Token
  Future<bool> _checkToken() async {
    try {
      final token = await ref.read(storageServiceProvider).read('jwt_token');
      return token != null;
    } catch (e) {
      return false;
    }
  }

  /// 放置所有不影響畫面跳轉的「重度」與「網路」任務
  Future<void> _loadHeavyDataInBackground() async {
    try {
      final storage = ref.read(storageServiceProvider);
      final userId = await storage.read('user_id') ?? '';
      final crypto = ref.read(cryptoServiceProvider);
      
      // 初始化金鑰
      final pubKey = await crypto.initialize(userId: userId);
      await ref.read(authRepositoryProvider).updatePublicKey(pubKey);

      // 確保 public key 快取是最新的
      await ref.read(publicKeyCacheServiceProvider).clearAllCache();

      // Security logic: Cleanup pending unregistration
      final pendingDeviceId = await storage.read(
        'pending_unregister_device_id',
      );
      final networkService = ref.read(networkServiceProvider);

      if (pendingDeviceId != null) {
        try {
          await networkService.client.delete('/devices/$pendingDeviceId');
        } catch (e) {
          debugPrint('Failed to clear pending device unregister on splash: $e');
        } finally {
          await storage.delete('pending_unregister_device_id');
        }
      }

      // Re-register active device session for push
      await ref
          .read(notificationServiceProvider)
          .initOneSignal("88247551-a540-4ffc-89aa-e6ea9478b7be");
          
      final subscriptionId = await ref
          .read(notificationServiceProvider)
          .getSubscriptionId();
          
      if (subscriptionId != null) {
        try {
          await networkService.client.post(
            '/devices/register',
            data: {
              'device_id': subscriptionId,
              'platform': Platform.isAndroid ? 'android' : 'ios',
            },
          );
        } catch (e) {
          debugPrint('Splash device register warning: $e');
        }
      }
    } catch (e) {
      debugPrint('Init sequence failed on splash: $e');
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