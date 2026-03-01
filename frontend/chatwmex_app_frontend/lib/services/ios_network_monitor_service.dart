import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// iOS 專用網路監控服務
/// 針對 iOS 實機的離線問題進行優化
class IOSNetworkMonitorService {
  static final IOSNetworkMonitorService _instance =
      IOSNetworkMonitorService._internal();
  factory IOSNetworkMonitorService() => _instance;
  IOSNetworkMonitorService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = true;
  bool _isInitialized = false;
  Timer? _connectivityCheckTimer;
  Timer? _reconnectTimer;

  // 監聽器列表
  final List<Function(bool)> _connectionListeners = [];

  /// 是否在線
  bool get isOnline => _isOnline;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化網路監控
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // print('IOSNetworkMonitorService: 初始化 iOS 網路監控服務');

      // 檢查初始網路狀態
      await _checkInitialConnectivity();

      // 開始監聽網路狀態變化
      _startConnectivityMonitoring();

      // 🔥 新增：定期檢查實際網路連接（針對 iOS）
      _startPeriodicConnectivityCheck();

      _isInitialized = true;
      // print(
      //     'IOSNetworkMonitorService: iOS 網路監控服務初始化完成，當前狀態: ${_isOnline ? "在線" : "離線"}');
    } catch (e) {
      print('IOSNetworkMonitorService: 初始化失敗: $e');
      _isOnline = false;
    }
  }

  /// 檢查初始網路連接狀態
  Future<void> _checkInitialConnectivity() async {
    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      await _updateConnectionStatus(connectivityResults);
    } catch (e) {
      print('IOSNetworkMonitorService: 檢查初始連接狀態失敗: $e');
      _isOnline = false;
    }
  }

  /// 開始監聽網路狀態變化
  void _startConnectivityMonitoring() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
      onError: (error) {
        print('IOSNetworkMonitorService: 網路狀態監聽錯誤: $error');
        _isOnline = false;
        _notifyConnectionListeners(false);
      },
    );
  }

// 修改 _startPeriodicConnectivityCheck 的間隔
  void _startPeriodicConnectivityCheck() {
    _connectivityCheckTimer?.cancel();
    _connectivityCheckTimer = Timer.periodic(
      const Duration(seconds: 15), // 從30秒改為15秒
      (timer) {
        _verifyActualConnectivity();
      },
    );
  }

  /// 更新連接狀態
  Future<void> _updateConnectionStatus(List<ConnectivityResult> results) async {
    final wasOnline = _isOnline;

    // 檢查是否有任何有效的連接
    final hasConnectivity = results.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);

    if (hasConnectivity) {
      // 🔥 新增：即使顯示有連接，也要驗證實際網路可用性
      await _verifyActualConnectivity();
    } else {
      _isOnline = false;
    }

    // 如果狀態發生變化，通知監聽器
    if (wasOnline != _isOnline) {
      // print('IOSNetworkMonitorService: 網路狀態變化: ${_isOnline ? "在線" : "離線"}');
      _notifyConnectionListeners(_isOnline);
    }
  }

  /// 🔥 新增：驗證實際網路連接
  Future<void> _verifyActualConnectivity() async {
    try {
      // print('IOSNetworkMonitorService: 驗證實際網路連接...');

      // 嘗試多個測試端點
      final testUrls = [
        'https://www.google.com',
        'https://www.apple.com',
        'https://httpbin.org/get',
      ];

      bool connectionVerified = false;

      for (final url in testUrls) {
        try {
          final client = http.Client();
          final response = await client
              .get(
                Uri.parse(url),
              )
              .timeout(const Duration(seconds: 5));

          client.close();

          if (response.statusCode == 200) {
            connectionVerified = true;
            // print('IOSNetworkMonitorService: 實際網路連接驗證成功 (${url})');
            break;
          }
        } catch (e) {
          // print('IOSNetworkMonitorService: 測試 ${url} 失敗: $e');
          continue;
        }
      }

      if (!connectionVerified) {
        print('IOSNetworkMonitorService: 實際網路連接驗證失敗');
        if (_isOnline) {
          _isOnline = false;
          _notifyConnectionListeners(false);
        }
      } else {
        if (!_isOnline) {
          _isOnline = true;
          _notifyConnectionListeners(true);
        }
      }
    } catch (e) {
      print('IOSNetworkMonitorService: 實際網路連接驗證失敗: $e');
      if (_isOnline) {
        _isOnline = false;
        _notifyConnectionListeners(false);
      }
    }
  }

  /// 註冊連接狀態監聽器
  void addConnectionListener(Function(bool) listener) {
    _connectionListeners.add(listener);
    // print(
    //     'IOSNetworkMonitorService: 註冊連接監聽器，當前總數: ${_connectionListeners.length}');
  }

  /// 移除連接狀態監聽器
  void removeConnectionListener(Function(bool) listener) {
    _connectionListeners.remove(listener);
    // print(
    //     'IOSNetworkMonitorService: 移除連接監聽器，當前總數: ${_connectionListeners.length}');
  }

  /// 通知所有監聽器
  void _notifyConnectionListeners(bool isOnline) {
    for (final listener in _connectionListeners) {
      try {
        listener(isOnline);
      } catch (e) {
        print('IOSNetworkMonitorService: 通知監聽器時出錯: $e');
      }
    }
  }

  /// 手動檢查網路連接
  Future<bool> checkConnection() async {
    try {
      // print('IOSNetworkMonitorService: 手動檢查網路連接...');

      // 先檢查基本連接狀態
      final connectivityResults = await _connectivity.checkConnectivity();
      final hasBasicConnectivity = connectivityResults.any((result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet);

      if (!hasBasicConnectivity) {
        _isOnline = false;
        _notifyConnectionListeners(false);
        return false;
      }

      // 驗證實際網路連接
      await _verifyActualConnectivity();

      return _isOnline;
    } catch (e) {
      print('IOSNetworkMonitorService: 手動檢查連接失敗: $e');
      _isOnline = false;
      _notifyConnectionListeners(false);
      return false;
    }
  }

  /// 🔥 新增：強制重新檢查網路狀態
  Future<void> forceRecheck() async {
    // print('IOSNetworkMonitorService: 強制重新檢查網路狀態');
    await checkConnection();
  }

  /// 🔥 新增：啟動自動重連機制
  void startAutoReconnect(Function() onReconnect) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_isOnline) {
        // print('IOSNetworkMonitorService: 嘗試自動重連...');
        onReconnect();
      }
    });
  }

  /// 🔥 新增：停止自動重連機制
  void stopAutoReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// 獲取詳細的連接信息
  Future<Map<String, dynamic>> getConnectionInfo() async {
    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      return {
        'isOnline': _isOnline,
        'connectivityResults':
            connectivityResults.map((e) => e.toString()).toList(),
        'hasWifi': connectivityResults.contains(ConnectivityResult.wifi),
        'hasMobile': connectivityResults.contains(ConnectivityResult.mobile),
        'hasEthernet':
            connectivityResults.contains(ConnectivityResult.ethernet),
        'isInitialized': _isInitialized,
        'listenersCount': _connectionListeners.length,
        'platform': Platform.operatingSystem,
      };
    } catch (e) {
      return {
        'isOnline': false,
        'error': e.toString(),
        'isInitialized': _isInitialized,
        'listenersCount': _connectionListeners.length,
        'platform': Platform.operatingSystem,
      };
    }
  }

  /// 清理資源
  void dispose() {
    // print('IOSNetworkMonitorService: 清理 iOS 網路監控服務');
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _connectivityCheckTimer?.cancel();
    _connectivityCheckTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectionListeners.clear();
    _isInitialized = false;
  }
}
