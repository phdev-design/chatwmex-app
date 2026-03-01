import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/storage/storage_service.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final StorageService _storageService;
  final StreamController<dynamic> _streamController = StreamController.broadcast();

  WebSocketService(this._storageService);

  Future<void> connect() async {
    final token = await _storageService.read('jwt_token');
    if (token == null) return;

    // TODO: Use env config. 
    // Note: Android emulator uses 10.0.2.2, iOS uses localhost. 
    // The previous steps used localhost, but for real device/emulator we need IP.
    final uri = Uri.parse('ws://localhost:8080/ws?token=$token');
    
    _channel = WebSocketChannel.connect(uri);
    
    _channel!.stream.listen(
      (message) {
        try {
          final decoded = jsonDecode(message);
          _streamController.add(decoded);
        } catch (e) {
          print('WebSocket decode error: $e');
        }
      },
      onDone: () {
        print('WebSocket closed');
        // Reconnect logic could go here
      },
      onError: (error) {
        print('WebSocket error: $error');
      },
    );
  }

  void send(String event, dynamic data) {
    if (_channel == null) return;
    final payload = jsonEncode({
      'event': event,
      'data': data,
    });
    _channel!.sink.add(payload);
  }

  Stream<dynamic> get events => _streamController.stream;

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return WebSocketService(storage);
});
