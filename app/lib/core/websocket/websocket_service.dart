import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/features/auth/providers/auth_provider.dart';
import 'package:uuid/uuid.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final StorageService _storageService;
  final Ref _ref;
  final StreamController<dynamic> _streamController =
      StreamController.broadcast();

  // Connection state
  bool _isConnected = false;
  bool _hasConnectedOnce = false;
  Timer? _reconnectTimer;
  int _retryAttempts = 0;
  bool _isRefreshingToken = false;

  // 🔐 E2EE Auto-Resend: 公開連接狀態供外部檢查
  bool get isConnected => _isConnected;

  // Queue & ACK
  final List<Map<String, dynamic>> _messageQueue = [];
  final Map<String, Completer<void>> _pendingAcks = {};

  WebSocketService(this._storageService, this._ref);

  Future<void> connect() async {
    if (_isConnected) return;

    final token = await _storageService.read('jwt_token');
    if (token == null) return;

    // Debug Mode 強制使用本地 WS
    String baseUrl = '';
    if (kDebugMode) {
      if (Platform.isAndroid) {
        baseUrl = 'ws://10.0.2.2:8080/ws';
      } else if (Platform.isIOS) {
        baseUrl = 'ws://127.0.0.1:8080/ws';
      } else {
        baseUrl = 'ws://localhost:8080/ws';
      }
    } else {
      // Release 讀取環境變數
      baseUrl = dotenv.env['WS_URL'] ?? '';
    }

    // 安全字串替換：防止 dart Uri 把部分缺少 port 的 https/wss 解析掛上 :0
    baseUrl = baseUrl.replaceAll(':0/ws', '/ws').replaceAll(':0', '');

    // 最後組合 token
    final uri = Uri.parse('$baseUrl?token=$token');

    try {
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      _channel = channel;
      _isConnected = true;
      _retryAttempts = 0;
      debugPrint('WebSocket connected');

      if (_hasConnectedOnce) {
        _streamController.add({'event': 'ws_reconnected'});
      } else {
        _hasConnectedOnce = true;
      }

      // Process offline queue
      _processQueue();

      _channel!.stream.listen(
        (message) {
          _handleIncomingMessage(message);
        },
        onDone: () {
          debugPrint('WebSocket closed');
          _handleDisconnect();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
      
      // 偵測 401 / token expired，嘗試刷新 token
      final errorStr = e.toString();
      if (errorStr.contains('not upgraded to websocket') ||
          errorStr.contains('401')) {
        debugPrint('WebSocket auth failed (401), attempting token refresh...');
        
        // 避免重複刷新
        if (_isRefreshingToken) {
          debugPrint('Token refresh already in progress, skipping...');
          _handleDisconnect();
          return;
        }
        
        _isRefreshingToken = true;
        
        try {
          // 呼叫 auth provider 的 refreshToken 方法
          final refreshSuccess = await _ref.read(authViewModelProvider.notifier).refreshToken();
          
          if (refreshSuccess) {
            debugPrint('✅ Token refresh successful, retrying WebSocket connection...');
            _isRefreshingToken = false;
            _retryAttempts = 0; // 重置重試計數
            await connect();
            return;
          } else {
            debugPrint('❌ Token refresh failed, stopping WebSocket retry');
            _isRefreshingToken = false;
            _streamController.add({'event': 'auth_expired'});
            return; // 不呼叫 _handleDisconnect()，不排 retry
          }
        } catch (refreshError) {
          debugPrint('❌ Token refresh error: $refreshError');
          _isRefreshingToken = false;
          _streamController.add({'event': 'auth_expired'});
          return; // 不呼叫 _handleDisconnect()，不排 retry
        }
      }
      
      _handleDisconnect();
    }
  }

  void _handleIncomingMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      _handleDecodedEvent(message);
      return;
    }
    if (message is! String) {
      return;
    }
    final raw = message.trim();
    if (raw.isEmpty) return;

    final chunks = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (final chunk in chunks) {
      try {
        final decoded = jsonDecode(chunk);
        if (decoded is Map) {
          _handleDecodedEvent(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        debugPrint('WebSocket decode error: $e');
      }
    }
  }

  void _handleDecodedEvent(Map<String, dynamic> decoded) {
    // 🔍 Log EVERY incoming WebSocket message for debugging
    final event = decoded['event'];
    debugPrint('🌐 [WebSocket] Incoming message: event=$event');
    
    if (decoded['event'] == 'message_ack') {
      final data = decoded['data'];
      if (data is Map) {
        final clientMsgId = data['client_msg_id'];
        if (clientMsgId != null && _pendingAcks.containsKey(clientMsgId)) {
          _pendingAcks[clientMsgId]?.complete();
          _pendingAcks.remove(clientMsgId);
        }
      }
    }
    _streamController.add(decoded);
  }

  void _handleDisconnect() {
    _isConnected = false;
    _channel = null;

    // Emit disconnect event
    _streamController.add({'event': 'ws_disconnected'});

    // Exponential backoff
    final delay = Duration(seconds: (1 << _retryAttempts).clamp(1, 30));
    _retryAttempts++;

    debugPrint('Reconnecting in ${delay.inSeconds} seconds...');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  Future<void> send(String event, dynamic data) async {
    String? clientMsgId;
    if (data is Map && data['client_msg_id'] is String) {
      clientMsgId = data['client_msg_id'] as String;
    }
    clientMsgId ??= const Uuid().v4();

    if (data is Map) {
      data['client_msg_id'] = clientMsgId;
    }

    final payload = {'event': event, 'data': data};

    if (!_isConnected) {
      _messageQueue.add(payload);
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(payload));

      // If it's a chat message, wait for ACK
      if (event == 'chat_message') {
        final completer = Completer<void>();
        _pendingAcks[clientMsgId] = completer;

        // Timeout for ACK
        await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _pendingAcks.remove(clientMsgId);
            throw TimeoutException('Message ACK timeout');
          },
        );
      }
    } catch (e) {
      debugPrint('Send failed, queuing message: $e');
      _messageQueue.add(payload);
      // Trigger reconnect if needed?
      if (_isConnected) _handleDisconnect();
    }
  }

  void _processQueue() async {
    if (_messageQueue.isEmpty) return;

    debugPrint('Processing ${_messageQueue.length} queued messages...');
    final List<Map<String, dynamic>> queueCopy = List.from(_messageQueue);
    _messageQueue.clear();

    for (final payload in queueCopy) {
      await send(payload['event'], payload['data']);
    }
  }

  Stream<dynamic> get events => _streamController.stream;

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
}

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return WebSocketService(storage, ref);
});
