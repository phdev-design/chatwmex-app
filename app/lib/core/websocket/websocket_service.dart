import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:uuid/uuid.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final StorageService _storageService;
  final StreamController<dynamic> _streamController =
      StreamController.broadcast();

  // Connection state
  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _retryAttempts = 0;

  // Queue & ACK
  final List<Map<String, dynamic>> _messageQueue = [];
  final Map<String, Completer<void>> _pendingAcks = {};

  WebSocketService(this._storageService);

  Future<void> connect() async {
    if (_isConnected) return;

    final token = await _storageService.read('jwt_token');
    if (token == null) return;

    // Use proper IP for emulator/device
    // Android Emulator: 10.0.2.2
    // iOS Simulator / Real Device on LAN: Needs LAN IP or localhost (if Simulator)
    String baseUrl = 'ws://localhost:8080/ws';
    if (Platform.isAndroid) {
      baseUrl = 'ws://10.0.2.2:8080/ws';
    }

    final uri = Uri.parse('$baseUrl?token=$token');

    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      _retryAttempts = 0;
      print('WebSocket connected');

      // Process offline queue
      _processQueue();

      _channel!.stream.listen(
        (message) {
          try {
            final decoded = jsonDecode(message);

            if (decoded['event'] == 'message_ack') {
              final clientMsgId = decoded['data']['client_msg_id'];
              if (clientMsgId != null &&
                  _pendingAcks.containsKey(clientMsgId)) {
                _pendingAcks[clientMsgId]?.complete();
                _pendingAcks.remove(clientMsgId);
              }
              _streamController.add(decoded);
            } else {
              _streamController.add(decoded);
            }
          } catch (e) {
            print('WebSocket decode error: $e');
          }
        },
        onDone: () {
          print('WebSocket closed');
          _handleDisconnect();
        },
        onError: (error) {
          print('WebSocket error: $error');
          _handleDisconnect();
        },
      );
    } catch (e) {
      print('WebSocket connection failed: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _channel = null;

    // Exponential backoff
    final delay = Duration(seconds: (1 << _retryAttempts).clamp(1, 30));
    _retryAttempts++;

    print('Reconnecting in ${delay.inSeconds} seconds...');
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
      print('Send failed, queuing message: $e');
      _messageQueue.add(payload);
      // Trigger reconnect if needed?
      if (_isConnected) _handleDisconnect();
    }
  }

  void _processQueue() async {
    if (_messageQueue.isEmpty) return;

    print('Processing ${_messageQueue.length} queued messages...');
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
  return WebSocketService(storage);
});
