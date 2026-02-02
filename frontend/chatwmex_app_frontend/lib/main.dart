import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chat2mex_app_frontend/screens/login_page.dart';
import 'package:chat2mex_app_frontend/screens/chat_rooms_page.dart';
import 'package:chat2mex_app_frontend/theme/app_theme.dart';
import 'package:chat2mex_app_frontend/providers/theme_provider.dart';
import 'package:chat2mex_app_frontend/utils/token_storage.dart';
import 'package:chat2mex_app_frontend/config/version_config.dart';
import 'package:chat2mex_app_frontend/services/network_monitor_service.dart';
import 'package:chat2mex_app_frontend/services/message_cache_service.dart';
import 'package:chat2mex_app_frontend/services/background_sync_service.dart';
import 'package:chat2mex_app_frontend/services/audio_session_service.dart';
import 'package:chat2mex_app_frontend/services/notification_service.dart';
import 'package:chat2mex_app_frontend/services/app_lifecycle_service.dart';
import 'package:chat2mex_app_frontend/services/api_client_service.dart';

// 程式進入點
void main() async {
  // 確保 Flutter 引擎已初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化應用
  final appInitialized = await _initializeApp();
  
  // 運行應用，傳遞初始化狀態
  runApp(MyApp(initializationSuccess: appInitialized));
}

// 改進的初始化函數，包含更好的錯誤處理
Future<bool> _initializeApp() async {
  print('main.dart: 開始初始化應用...');
  
  try {
    // 階段 1: 核心服務初始化
    await _initializeCoreServices();
    
    // 階段 2: 網絡相關服務初始化
    await _initializeNetworkServices();
    
    // 階段 3: 用戶體驗服務初始化
    await _initializeUserExperienceServices();
    
    print('✅ main.dart: 所有服務初始化完成');
    return true;
    
  } catch (e) {
    print('❌ main.dart: 應用初始化失敗: $e');
    return false;
  }
}

// 核心服務初始化
Future<void> _initializeCoreServices() async {
  print('main.dart: 初始化核心服務...');
  
  // 最重要：先初始化 API 客戶端
  await ApiClientService.initialize();
  print('✅ ApiClientService 初始化完成');
  
  // 應用生命週期服務
  await AppLifecycleService().initialize();
  print('✅ AppLifecycleService 初始化完成');
}

// 網絡相關服務初始化
Future<void> _initializeNetworkServices() async {
  print('main.dart: 初始化網絡服務...');
  
  try {
    // 網絡監控
    await NetworkMonitorService().initialize();
    print('✅ NetworkMonitorService 初始化完成');
    
    // 消息緩存
    await MessageCacheService().initialize();
    print('✅ MessageCacheService 初始化完成');
    
    // 背景同步
    await BackgroundSyncService().initialize();
    print('✅ BackgroundSyncService 初始化完成');
    
  } catch (e) {
    print('⚠️ 網絡服務初始化失敗，將在離線模式下運行: $e');
    // 不拋出錯誤，允許應用在離線模式下運行
  }
}

// 用戶體驗服務初始化
Future<void> _initializeUserExperienceServices() async {
  print('main.dart: 初始化用戶體驗服務...');
  
  try {
    // 通知服務
    await NotificationService().initialize();
    print('✅ NotificationService 初始化完成');
    
    // 音頻會話
    await AudioSessionService().initialize();
    print('✅ AudioSessionService 初始化完成');
    
  } catch (e) {
    print('⚠️ 用戶體驗服務初始化失敗，功能可能受限: $e');
    // 不拋出錯誤，允許應用繼續運行
  }
}

class MyApp extends StatelessWidget {
  final bool initializationSuccess;
  
  const MyApp({super.key, required this.initializationSuccess});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: VersionConfig.appName,
            debugShowCheckedModeBanner: false,

            // 主題配置
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,

            // 啟動頁面
            home: SplashScreen(initializationSuccess: initializationSuccess),

            // 全局路由
            routes: {
              '/login': (context) => const LoginPage(),
              '/chat-rooms': (context) => const ChatRoomsPage(),
            },
          );
        },
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final bool initializationSuccess;
  
  const SplashScreen({super.key, required this.initializationSuccess});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _animationController.forward();
    _checkAuthStatus();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthStatus() async {
    // 等待動畫完成
    await Future.delayed(const Duration(milliseconds: 2500));

    if (!mounted) return;

    // 檢查初始化狀態
    if (!widget.initializationSuccess) {
      _showInitializationError();
      return;
    }

    try {
      print('SplashScreen: 檢查登入狀態...');

      // 清除過期 Token
      await TokenStorage.clearExpiredToken();

      final isLoggedIn = await TokenStorage.isLoggedIn();
      print('SplashScreen: 登入狀態: $isLoggedIn');

      if (isLoggedIn) {
        _navigateToChatRooms();
      } else {
        _navigateToLogin();
      }
    } catch (e) {
      print('SplashScreen: 檢查登入狀態錯誤: $e');
      _navigateToLogin();
    }
  }

  void _showInitializationError() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('初始化失敗'),
        content: const Text('應用無法正常初始化，請檢查網絡連接後重新啟動應用。'),
        actions: [
          TextButton(
            onPressed: () {
              // 重新嘗試初始化或退出應用
              _navigateToLogin(); // 暫時導航到登入頁面
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _navigateToChatRooms() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ChatRoomsPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.chat_bubble,
                    size: 60,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  VersionConfig.appName,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '連接世界，分享想法',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  VersionConfig.shortVersion,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 40),
                // 顯示初始化狀態
                if (!widget.initializationSuccess) ...[
                  Icon(
                    Icons.error_outline,
                    color: Colors.white.withOpacity(0.8),
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '初始化失敗',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withOpacity(0.8),
                      ),
                      strokeWidth: 3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}