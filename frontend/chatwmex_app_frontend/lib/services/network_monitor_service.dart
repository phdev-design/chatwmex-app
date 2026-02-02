import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// 網路連接監控服務
/// 負責監聽網路狀態變化，並通知其他服務
class NetworkMonitorService {
  static final NetworkMonitorService _instance =
      NetworkMonitorService._internal();
  factory NetworkMonitorService() => _instance;
  NetworkMonitorService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = true;
  bool _isInitialized = false;

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
      print('NetworkMonitorService: 初始化網路監控服務');

      // 檢查初始網路狀態
      await _checkInitialConnectivity();

      // 開始監聽網路狀態變化
      _startConnectivityMonitoring();

      _isInitialized = true;
      print(
          'NetworkMonitorService: 網路監控服務初始化完成，當前狀態: ${_isOnline ? "在線" : "離線"}');
    } catch (e) {
      print('NetworkMonitorService: 初始化失敗: $e');
      _isOnline = false;
    }
  }

  /// 檢查初始網路連接狀態
  Future<void> _checkInitialConnectivity() async {
    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      _updateConnectionStatus(connectivityResults);
    } catch (e) {
      print('NetworkMonitorService: 檢查初始連接狀態失敗: $e');
      _isOnline = false;
    }
  }

  /// 開始監聽網路狀態變化
  void _startConnectivityMonitoring() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
      onError: (error) {
        print('NetworkMonitorService: 網路狀態監聽錯誤: $error');
        _isOnline = false;
        _notifyConnectionListeners(false);
      },
    );
  }

  /// 更新連接狀態
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;

    // 檢查是否有任何有效的連接
    _isOnline = results.any((result) =>
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet);

    // 如果狀態發生變化，通知監聽器
    if (wasOnline != _isOnline) {
      print('NetworkMonitorService: 網路狀態變化: ${_isOnline ? "在線" : "離線"}');
      _notifyConnectionListeners(_isOnline);
    }
  }

  /// 註冊連接狀態監聽器
  void addConnectionListener(Function(bool) listener) {
    _connectionListeners.add(listener);
    print(
        'NetworkMonitorService: 註冊連接監聽器，當前總數: ${_connectionListeners.length}');
  }

  /// 移除連接狀態監聽器
  void removeConnectionListener(Function(bool) listener) {
    _connectionListeners.remove(listener);
    print(
        'NetworkMonitorService: 移除連接監聽器，當前總數: ${_connectionListeners.length}');
  }

  /// 通知所有監聽器
  void _notifyConnectionListeners(bool isOnline) {
    for (final listener in _connectionListeners) {
      try {
        listener(isOnline);
      } catch (e) {
        print('NetworkMonitorService: 通知監聽器時出錯: $e');
      }
    }
  }

  /// 手動檢查網路連接
  Future<bool> checkConnection() async {
    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      final isConnected = connectivityResults.any((result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet);

      // 更新內部狀態
      if (_isOnline != isConnected) {
        _isOnline = isConnected;
        _notifyConnectionListeners(_isOnline);
      }

      return isConnected;
    } catch (e) {
      print('NetworkMonitorService: 手動檢查連接失敗: $e');
      return false;
    }
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
      };
    } catch (e) {
      return {
        'isOnline': false,
        'error': e.toString(),
        'isInitialized': _isInitialized,
        'listenersCount': _connectionListeners.length,
      };
    }
  }

  /// 清理資源
  void dispose() {
    print('NetworkMonitorService: 清理網路監控服務');
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _connectionListeners.clear();
    _isInitialized = false;
  }
}
