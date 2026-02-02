import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'chat_service.dart';
import 'network_monitor_service.dart';
import 'ios_network_monitor_service.dart';
import 'background_sync_service.dart';
import 'message_cache_service.dart';
import '../utils/token_storage.dart';

/// 應用生命週期管理服務
/// 負責監聽應用狀態變化並執行相應的操作
class AppLifecycleService with WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  final ChatService _chatService = ChatService();
  final NetworkMonitorService _networkMonitor = NetworkMonitorService();
  final IOSNetworkMonitorService _iosNetworkMonitor = IOSNetworkMonitorService();
  final BackgroundSyncService _backgroundSync = BackgroundSyncService();
  final MessageCacheService _messageCache = MessageCacheService();

  Timer? _reconnectTimer;
  Timer? _healthCheckTimer;
  DateTime? _lastActiveTime;
  bool _isInitialized = false;
  AppLifecycleState? _lastLifecycleState;

  /// 初始化生命週期服務
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('AppLifecycleService: 初始化應用生命週期服務');
      
      // 註冊生命週期觀察者
      WidgetsBinding.instance.addObserver(this);
      
      // 記錄初始活躍時間
      _lastActiveTime = DateTime.now();
      
      // 啟動健康檢查定時器
      _startHealthCheckTimer();
      
      _isInitialized = true;
      print('AppLifecycleService: 初始化完成');
    } catch (e) {
      print('AppLifecycleService: 初始化失敗: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('AppLifecycleService: 應用狀態變更: $_lastLifecycleState -> $state');
    
    _lastLifecycleState = state;
    
    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
        break;
      case AppLifecycleState.inactive:
        _onAppInactive();
        break;
      case AppLifecycleState.paused:
        _onAppPaused();
        break;
      case AppLifecycleState.detached:
        _onAppDetached();
        break;
      case AppLifecycleState.hidden:
        // Flutter 3.13+ 新增狀態
        print('AppLifecycleService: 應用進入隱藏狀態');
        break;
    }
  }

  /// 應用恢復到前台
  Future<void> _onAppResumed() async {
    print('AppLifecycleService: 應用恢復到前台');
    
    try {
      // 計算應用在後台的時間
      final inactiveTime = _lastActiveTime != null 
          ? DateTime.now().difference(_lastActiveTime!)
          : Duration.zero;
      
      print('AppLifecycleService: 應用在後台時間: ${inactiveTime.inSeconds} 秒');
      
      // 更新活躍時間
      _lastActiveTime = DateTime.now();
      
      // 重啟健康檢查
      _startHealthCheckTimer();
      
      // 檢查Token有效性
      final isTokenValid = await TokenStorage.isTokenValid();
      if (!isTokenValid) {
        print('AppLifecycleService: Token已過期，需要重新登入');
        // 可以在這裡觸發登出邏輯
        return;
      }
      
      // 如果閒置超過5分鐘，執行完整恢復流程
      if (inactiveTime.inMinutes >= 5) {
        await _performFullRecovery();
      } else {
        // 短時間閒置，只需檢查連接
        await _performQuickCheck();
      }
    } catch (e) {
      print('AppLifecycleService: 恢復流程失敗: $e');
    }
  }

  /// 應用進入非活躍狀態
  void _onAppInactive() {
    print('AppLifecycleService: 應用進入非活躍狀態');
    _lastActiveTime = DateTime.now();
  }

  /// 應用進入後台
  void _onAppPaused() {
    print('AppLifecycleService: 應用進入後台');
    _lastActiveTime = DateTime.now();
    
    // 停止健康檢查定時器以節省資源
    _stopHealthCheckTimer();
    
    // 啟動背景同步
    _backgroundSync.startBackgroundSync();
  }

  /// 應用即將終止
  void _onAppDetached() {
    print('AppLifecycleService: 應用即將終止');
    dispose();
  }

  /// 執行完整恢復流程（長時間閒置後）
  Future<void> _performFullRecovery() async {
    print('AppLifecycleService: 執行完整恢復流程');
    
    try {
      // 1. 檢查網路連接
      print('AppLifecycleService: 檢查網路連接...');
      final hasNetwork = Platform.isIOS
          ? await _iosNetworkMonitor.checkConnection()
          : await _networkMonitor.checkConnection();
      
      if (!hasNetwork) {
        print('AppLifecycleService: 網路不可用');
        return;
      }
      
      // 2. 強制重新檢查網路狀態（針對iOS）
      if (Platform.isIOS) {
        await _iosNetworkMonitor.forceRecheck();
      }
      
      // 3. 重連WebSocket
      if (!_chatService.isConnected) {
        print('AppLifecycleService: 嘗試重連WebSocket...');
        try {
          await _chatService.forceReconnect();
          print('AppLifecycleService: WebSocket重連成功');
        } catch (e) {
          print('AppLifecycleService: WebSocket重連失敗: $e');
        }
      }
      
      // 4. 執行背景數據同步
      print('AppLifecycleService: 執行數據同步...');
      await _backgroundSync.triggerSync();
      
      // 5. 優化緩存
      await _messageCache.optimizeCache();
      
      print('AppLifecycleService: 完整恢復流程完成');
    } catch (e) {
      print('AppLifecycleService: 完整恢復流程失敗: $e');
    }
  }

  /// 執行快速檢查（短時間閒置後）
  Future<void> _performQuickCheck() async {
    print('AppLifecycleService: 執行快速檢查');
    
    try {
      // 檢查連接狀態
      if (!_chatService.isConnected) {
        print('AppLifecycleService: 檢測到連接斷開，嘗試重連');
        await _chatService.reconnect();
      }
      
      // 觸發一次同步
      await _backgroundSync.triggerSync();
      
      print('AppLifecycleService: 快速檢查完成');
    } catch (e) {
      print('AppLifecycleService: 快速檢查失敗: $e');
    }
  }

  /// 啟動健康檢查定時器
  void _startHealthCheckTimer() {
    _stopHealthCheckTimer();
    
    // 每30秒檢查一次連接狀態
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) => _performHealthCheck(),
    );
    
    print('AppLifecycleService: 健康檢查定時器已啟動');
  }

  /// 停止健康檢查定時器
  void _stopHealthCheckTimer() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  /// 執行健康檢查
  Future<void> _performHealthCheck() async {
    try {
      print('AppLifecycleService: 執行健康檢查...');
      
      // 檢查Token是否仍然有效
      final isTokenValid = await TokenStorage.isTokenValid();
      if (!isTokenValid) {
        print('AppLifecycleService: Token已過期');
        _stopHealthCheckTimer();
        return;
      }
      
      // 檢查網路連接
      final hasNetwork = Platform.isIOS
          ? _iosNetworkMonitor.isOnline
          : _networkMonitor.isOnline;
      
      if (!hasNetwork) {
        print('AppLifecycleService: 網路離線');
        return;
      }
      
      // 檢查WebSocket連接
      if (!_chatService.isConnected && !_chatService.isConnecting) {
        print('AppLifecycleService: WebSocket未連接，嘗試重連');
        await _chatService.reconnect().catchError((e) {
          print('AppLifecycleService: 自動重連失敗: $e');
        });
      }
    } catch (e) {
      print('AppLifecycleService: 健康檢查失敗: $e');
    }
  }

  /// 手動觸發恢復流程
  Future<void> manualRecover() async {
    print('AppLifecycleService: 手動觸發恢復流程');
    await _performFullRecovery();
  }

  /// 獲取應用狀態信息
  Map<String, dynamic> getAppStatus() {
    return {
      'isInitialized': _isInitialized,
      'lastActiveTime': _lastActiveTime?.toIso8601String(),
      'currentState': _lastLifecycleState?.toString(),
      'inactiveDuration': _lastActiveTime != null
          ? DateTime.now().difference(_lastActiveTime!).inSeconds
          : 0,
      'hasHealthCheck': _healthCheckTimer != null,
      'chatServiceConnected': _chatService.isConnected,
    };
  }

  /// 清理資源
  void dispose() {
    print('AppLifecycleService: 清理資源');
    
    WidgetsBinding.instance.removeObserver(this);
    _stopHealthCheckTimer();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    _isInitialized = false;
  }
}