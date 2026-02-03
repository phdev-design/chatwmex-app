// lib/services/chat_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart'; // Added
import '../config/api_config.dart';
import '../models/message.dart' as chat_msg;
import '../models/chat_room.dart';
import '../utils/token_storage.dart';
import 'notification_service.dart';
import 'network_monitor_service.dart';
import 'ios_network_monitor_service.dart';
import 'message_cache_service.dart';
import 'api_client_service.dart';
import '../models/voice_message.dart' as voice_msg;
import 'database_helper.dart'; // Added

enum _SocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class ConnectionManager {
  final NetworkMonitorService _networkMonitor = NetworkMonitorService();
  final IOSNetworkMonitorService _iosNetworkMonitor =
      IOSNetworkMonitorService();
  Function(bool)? _statusListener;

  Future<void> initialize({
    required Function(bool) onStatusChanged,
    required Function() onForceReconnect,
  }) async {
    if (_statusListener != null) {
      _removeListener(_statusListener!);
    }
    _statusListener = onStatusChanged;

    await _networkMonitor.initialize();

    if (Platform.isIOS) {
      await _iosNetworkMonitor.initialize();
      _iosNetworkMonitor.addConnectionListener(onStatusChanged);
      _iosNetworkMonitor.startAutoReconnect(onForceReconnect);
    } else {
      _networkMonitor.addConnectionListener(onStatusChanged);
    }
  }

  bool get isOnline {
    return Platform.isIOS
        ? _iosNetworkMonitor.isOnline
        : _networkMonitor.isOnline;
  }

  Future<bool> checkConnection() async {
    try {
      if (Platform.isIOS) {
        return await _iosNetworkMonitor.checkConnection();
      } else {
        return await _networkMonitor.checkConnection();
      }
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    if (_statusListener != null) {
      _removeListener(_statusListener!);
    }
    if (Platform.isIOS) {
      _iosNetworkMonitor.stopAutoReconnect();
    }
    _statusListener = null;
  }

  void _removeListener(Function(bool) listener) {
    if (Platform.isIOS) {
      _iosNetworkMonitor.removeConnectionListener(listener);
    } else {
      _networkMonitor.removeConnectionListener(listener);
    }
  }
}

class SocketClient {
  SocketClient({
    required ConnectionManager connectionManager,
    required void Function(bool) onConnectionChanged,
    required void Function(dynamic) onAuthError,
  })  : _connectionManager = connectionManager,
        _onConnectionChanged = onConnectionChanged,
        _onAuthError = onAuthError;

  static const int maxReconnectAttempts = 10;

  final ConnectionManager _connectionManager;
  final void Function(bool) _onConnectionChanged;
  final void Function(dynamic) _onAuthError;

  IO.Socket? _socket;
  _SocketConnectionState _state = _SocketConnectionState.disconnected;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _connectTimeoutTimer;
  int _reconnectAttempts = 0;
  bool _allowReconnect = true;
  String? _token;
  void Function(IO.Socket)? _registerHandlers;

  bool get isConnected => _state == _SocketConnectionState.connected;
  bool get isConnecting =>
      _state == _SocketConnectionState.connecting ||
      _state == _SocketConnectionState.reconnecting;
  int get reconnectAttempts => _reconnectAttempts;
  bool get hasHeartbeat => _heartbeatTimer != null;
  bool get allowReconnect => _allowReconnect;
  IO.Socket? get socket => _socket;

  Future<void> connect({
    required String token,
    required void Function(IO.Socket) registerHandlers,
  }) async {
    if (isConnecting || isConnected) return;
    await _connectInternal(
      token: token,
      registerHandlers: registerHandlers,
      isReconnect: false,
    );
  }

  Future<void> _connectInternal({
    required String token,
    required void Function(IO.Socket) registerHandlers,
    required bool isReconnect,
  }) async {
    if (!_allowReconnect) {
      print('SocketClient: initialize() skipped because reconnect is disabled');
      return;
    }

    try {
      _setState(isReconnect
          ? _SocketConnectionState.reconnecting
          : _SocketConnectionState.connecting);
      _token = token;
      _registerHandlers = registerHandlers;

      if (_socket != null) {
        _socket!.disconnect();
        _socket = null;
      }

      print('Initializing socket connection to: ${ApiConfig.baseUrl}');

      _socket = IO.io(
        ApiConfig.baseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setQuery({'token': token})
            .setExtraHeaders({'authorization': 'Bearer $token'})
            .setTimeout(15000)
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setReconnectionAttempts(maxReconnectAttempts)
            .enableReconnection()
            .enableAutoConnect()
            .enableForceNew()
            .build(),
      );

      _setupLifecycleListeners();
      registerHandlers(_socket!);

      _startConnectTimeout();

      _socket!.connect();
    } catch (e) {
      print('Socket initialization error: $e');
      _setState(_SocketConnectionState.disconnected);
      _onAuthError(e);

      if (_allowReconnect &&
          !e.toString().contains('expired') &&
          !e.toString().contains('invalid')) {
        _scheduleReconnect();
      }
      rethrow;
    }
  }

  bool emit(String event, dynamic data) {
    if (_socket == null || !isConnected) {
      return false;
    }
    _socket!.emit(event, data);
    return true;
  }

  void disconnect() {
    _allowReconnect = false;
    _stopHeartbeat();
    _cancelReconnectTimer();
    _cancelConnectTimeout();
    _disposeSocket();
    _setState(_SocketConnectionState.disconnected);
    _reconnectAttempts = 0;
    _onConnectionChanged(false);
  }

  void disableReconnect() {
    _allowReconnect = false;
    _cancelReconnectTimer();
  }

  void enableReconnect() {
    _allowReconnect = true;
  }

  void resetReconnectAttempts() {
    _reconnectAttempts = 0;
  }

  void scheduleReconnect() {
    _scheduleReconnect();
  }

  void handleNetworkStatusChanged(bool isOnline) {
    if (isOnline) {
      if (!isConnected && !isConnecting && _allowReconnect) {
        _scheduleReconnect();
      }
    } else {
      _cancelReconnectTimer();
      _cancelConnectTimeout();
      _stopHeartbeat();
      _setState(_SocketConnectionState.disconnected);
      _onConnectionChanged(false);
    }
  }

  void forceReconnectFromNetwork() {
    if (!_allowReconnect) return;
    if (isConnected || isConnecting) return;
    _retryConnection();
  }

  void _setupLifecycleListeners() {
    if (_socket == null) return;

    _socket!.onConnect((_) {
      print('Socket connected successfully');
      _cancelReconnectTimer();
      _cancelConnectTimeout();
      _setState(_SocketConnectionState.connected);
      _reconnectAttempts = 0;
      _startHeartbeat();
      _onConnectionChanged(true);
    });

    _socket!.onDisconnect((reason) {
      print('Socket disconnected: $reason');
      _cancelConnectTimeout();
      _setState(_SocketConnectionState.disconnected);
      _stopHeartbeat();
      _onConnectionChanged(false);

      if (_allowReconnect && reason != 'client namespace disconnect') {
        _scheduleReconnect();
      }
    });

    _socket!.onConnectError((error) {
      print('Socket connection error: $error');
      _cancelConnectTimeout();
      _setState(_SocketConnectionState.disconnected);
      _onConnectionChanged(false);
      _onAuthError(error);

      if (_allowReconnect && !error.toString().contains('authentication')) {
        _scheduleReconnect();
      }
    });

    _socket!.on('auth_error', (data) {
      print('Socket auth error: $data');
      _onAuthError(data);
    });

    _socket!.onReconnectAttempt((attemptCount) {
      print('Attempting to reconnect... Attempt: $attemptCount');
      _setState(_SocketConnectionState.reconnecting);
      _onConnectionChanged(false);
    });

    _socket!.onReconnect((attemptCount) {
      print('Reconnected successfully after $attemptCount attempts');
      _cancelReconnectTimer();
      _cancelConnectTimeout();
      _setState(_SocketConnectionState.connected);
      _reconnectAttempts = 0;
      _startHeartbeat();
      _onConnectionChanged(true);
    });

    _socket!.onReconnectError((error) {
      print('Reconnection error: $error');
      _cancelConnectTimeout();
      _setState(_SocketConnectionState.disconnected);
      _onConnectionChanged(false);
      _onAuthError(error);

      if (_allowReconnect && !error.toString().contains('authentication')) {
        _scheduleReconnect();
      }
    });

    _socket!.onReconnectFailed((_) {
      print('All reconnection attempts failed');
      _cancelConnectTimeout();
      _setState(_SocketConnectionState.disconnected);
      _onConnectionChanged(false);
      _scheduleReconnect();
    });

    _socket!.on('pong', (_) {
      print('Received pong from server');
    });

    _socket!.on('error', (error) {
      print('Socket error: $error');
    });

    _socket!.on('connect_error', (error) {
      print('Connection error: $error');
      _cancelConnectTimeout();
      _setState(_SocketConnectionState.disconnected);
      _onConnectionChanged(false);
      _scheduleReconnect();
    });
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_socket != null && isConnected) {
        _socket!.emit('ping');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (!_allowReconnect) return;
    if (_reconnectAttempts >= maxReconnectAttempts) return;
    if (!_connectionManager.isOnline) return;
    if (isConnected || isConnecting) return;

    _setState(_SocketConnectionState.reconnecting);
    _cancelReconnectTimer();
    final delay = Duration(seconds: (2 << _reconnectAttempts).clamp(1, 30));

    _reconnectTimer = Timer(delay, () {
      if (!_allowReconnect) return;
      if (_connectionManager.isOnline) {
        _retryConnection();
      }
    });
  }

  void _retryConnection() {
    if (!_allowReconnect) return;
    if (isConnected || isConnecting) return;
    if (!_connectionManager.isOnline) return;
    if (_token == null || _registerHandlers == null) return;

    _reconnectAttempts++;
    _disposeSocket();
    _cancelConnectTimeout();
    _setState(_SocketConnectionState.reconnecting);
    _onConnectionChanged(false);

    _connectInternal(
      token: _token!,
      registerHandlers: _registerHandlers!,
      isReconnect: true,
    ).catchError((error) {
      _setState(_SocketConnectionState.disconnected);
      _scheduleReconnect();
    });
  }

  void _disposeSocket() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }
  }

  void _setState(_SocketConnectionState state) {
    _state = state;
  }

  void _startConnectTimeout() {
    _cancelConnectTimeout();
    _connectTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!_allowReconnect) return;
      if (isConnecting && !isConnected) {
        _setState(_SocketConnectionState.disconnected);
        _onConnectionChanged(false);
        _scheduleReconnect();
      }
    });
  }

  void _cancelConnectTimeout() {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
}

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final NotificationService _notificationService = NotificationService();
  final MessageCacheService _messageCache = MessageCacheService();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final Uuid _uuid = const Uuid();
  final ConnectionManager _connectionManager = ConnectionManager();
  late final SocketClient _socketClient = SocketClient(
    connectionManager: _connectionManager,
    onConnectionChanged: _notifyConnectionChanged,
    onAuthError: _handleAuthenticationError,
  );

  // 使用 Map 來管理多個監聽器
  final Map<String, Function(chat_msg.Message)> _messageReceivedCallbacks = {};
  final Map<String, Function(ChatRoom)> _roomUpdatedCallbacks = {};
  final Map<String, Function(String userId, bool isOnline)>
      _userStatusChangedCallbacks = {};
  final Map<String, Function(bool)> _connectionChangedCallbacks = {};

  // 🔥 新增：Reaction 更新監聽器回調
  final Map<String,
          Function(String messageId, Map<String, List<String>> reactions)>
      _reactionUpdateCallbacks = {};

  // 🔥 新增：消息已讀監聽器回調
  final Map<String, Function(String roomId, String userId)>
      _messageReadCallbacks = {};

  // 🔥 新增：Typing 狀態監聽器回調
  final Map<String, Function(String roomId, String username, bool isTyping)>
      _typingCallbacks = {};

  final Map<String, String> _chatRoomNames = {};
  String? _currentActiveChatRoomId;

  void updateChatRoomNames(List<ChatRoom> rooms) {
    for (var room in rooms) {
      _chatRoomNames[room.id] = room.name;
    }
    print('ChatService: 已更新聊天室名稱快取，共 ${_chatRoomNames.length} 個聊天室');
  }

  // === 監聽器註冊方法 ===

  void registerMessageListener(String id, Function(chat_msg.Message) callback) {
    _messageReceivedCallbacks[id] = callback;
    print('ChatService: 註冊消息監聽器 $id，當前總數: ${_messageReceivedCallbacks.length}');
  }

  void unregisterMessageListener(String id) {
    _messageReceivedCallbacks.remove(id);
    print('ChatService: 移除消息監聽器 $id，當前總數: ${_messageReceivedCallbacks.length}');
  }

  void registerConnectionListener(String id, Function(bool) callback) {
    _connectionChangedCallbacks[id] = callback;
    print(
        'ChatService: 註冊連接監聽器 $id，當前總數: ${_connectionChangedCallbacks.length}');
  }

  void unregisterConnectionListener(String id) {
    _connectionChangedCallbacks.remove(id);
    print(
        'ChatService: 移除連接監聽器 $id，當前總數: ${_connectionChangedCallbacks.length}');
  }

  void registerRoomUpdateListener(String id, Function(ChatRoom) callback) {
    _roomUpdatedCallbacks[id] = callback;
  }

  void unregisterRoomUpdateListener(String id) {
    _roomUpdatedCallbacks.remove(id);
  }

  void registerUserStatusListener(String id, Function(String, bool) callback) {
    _userStatusChangedCallbacks[id] = callback;
  }

  void unregisterUserStatusListener(String id) {
    _userStatusChangedCallbacks.remove(id);
  }

  // 🔥 新增：Reaction 更新監聽器
  void registerReactionUpdateListener(
      String id,
      Function(String messageId, Map<String, List<String>> reactions)
          callback) {
    _reactionUpdateCallbacks[id] = callback;
    print(
        'ChatService: 註冊 Reaction 監聽器 $id，當前總數: ${_reactionUpdateCallbacks.length}');
  }

  void unregisterReactionUpdateListener(String id) {
    _reactionUpdateCallbacks.remove(id);
    print(
        'ChatService: 移除 Reaction 監聽器 $id，當前總數: ${_reactionUpdateCallbacks.length}');
  }

  // 🔥 新增：註冊消息已讀監聽器
  void registerMessageReadListener(
      String id, Function(String roomId, String userId) callback) {
    _messageReadCallbacks[id] = callback;
    print('ChatService: 註冊消息已讀監聽器 $id');
  }

  void unregisterMessageReadListener(String id) {
    _messageReadCallbacks.remove(id);
  }

  // 🔥 新增：註冊 Typing 狀態監聽器
  void registerTypingListener(String id,
      Function(String roomId, String username, bool isTyping) callback) {
    _typingCallbacks[id] = callback;
    print('ChatService: 註冊 Typing 監聽器 $id');
  }

  void unregisterTypingListener(String id) {
    _typingCallbacks.remove(id);
  }

  // === 初始化方法 ===

  Future<void> initialize() async {
    if (_socketClient.isConnecting || _socketClient.isConnected) return;
    if (!_socketClient.allowReconnect) {
      print('ChatService: initialize() skipped because reconnect is disabled');
      return;
    }

    try {
      await _notificationService.initialize();
      await _connectionManager.initialize(
        onStatusChanged: _socketClient.handleNetworkStatusChanged,
        onForceReconnect: _socketClient.forceReconnectFromNetwork,
      );

      await _messageCache.initialize();

      final isValidToken = await TokenStorage.isTokenValid();
      if (!isValidToken) {
        print('ChatService: Token 無效或過期，停止初始化');
        throw Exception('Token expired or invalid');
      }

      final token = await TokenStorage.getToken();
      if (token == null) {
        throw Exception('No authentication token found');
      }

      await _socketClient.connect(
        token: token,
        registerHandlers: _setupMessageEventListeners,
      );
    } catch (e) {
      print('Socket initialization error: $e');
      _handleAuthenticationError(e);
      throw e;
    }
  }

  // 🔥 新增：發送已讀標記
  void markAsRead(String roomId) {
    if (_socketClient.socket != null && _socketClient.isConnected) {
      print('ChatService: 發送 mark_read 事件 (room: $roomId)');
      _socketClient.socket!.emit('mark_read', {'room': roomId});
    }
  }

  // 🔥 新增：發送開始輸入狀態
  void sendTypingStart(String roomId) {
    if (_socketClient.socket != null && _socketClient.isConnected) {
      _socketClient.socket!.emit('typing_start', {'room': roomId});
    }
  }

  // 🔥 新增：發送停止輸入狀態
  void sendTypingEnd(String roomId) {
    if (_socketClient.socket != null && _socketClient.isConnected) {
      _socketClient.socket!.emit('typing_end', {'room': roomId});
    }
  }

  // === 🔥 修正：合併後的事件監聽器設置 ===

  void _setupMessageEventListeners(IO.Socket socket) {
    // 🔥 图片消息监听
    socket.on('image_message', (data) {
      try {
        print('Received image message data: $data');

        Map<String, dynamic> messageData;
        if (data is String) {
          messageData = jsonDecode(data);
        } else {
          messageData = Map<String, dynamic>.from(data);
        }

        final message = chat_msg.Message(
          id: messageData['id'] ?? '',
          senderId: messageData['sender_id'] ?? '',
          senderName: messageData['sender_name'] ?? '',
          content: '[图片]',
          timestamp: DateTime.parse(
              messageData['timestamp'] ?? DateTime.now().toIso8601String()),
          roomId: messageData['room'] ?? '',
          type: chat_msg.MessageType.image,
          fileUrl: messageData['file_url'],
        );

        _notifyMessageReceived(message);
      } catch (e) {
        print('Error parsing image message: $e');
      }
    });

    // 🔥 消息已读监听
    socket.on('message_read', (data) {
      try {
        print('Received message_read event: $data');
        String? roomId;
        String? userId;

        if (data is Map) {
          roomId = data['room']?.toString();
          userId = data['user_id']?.toString();
        }

        if (roomId != null && userId != null) {
          _notifyMessageRead(roomId, userId);
        }
      } catch (e) {
        print('Error handling message_read: $e');
      }
    });

    // 🔥 Typing 事件监听
    socket.on('typing_start', (data) {
      try {
        if (data is Map) {
          final roomId = data['room']?.toString();
          final username = data['sender_name']?.toString();
          if (roomId != null && username != null) {
            _notifyTyping(roomId, username, true);
          }
        }
      } catch (e) {
        print('Error handling typing_start: $e');
      }
    });

    socket.on('typing_end', (data) {
      try {
        if (data is Map) {
          final roomId = data['room']?.toString();
          final username = data['sender_name']?.toString();
          if (roomId != null && username != null) {
            _notifyTyping(roomId, username, false);
          }
        }
      } catch (e) {
        print('Error handling typing_end: $e');
      }
    });

    socket.on('voice_message', (data) {
      try {
        print('Received voice message data: $data');

        Map<String, dynamic> messageData;
        if (data is String) {
          messageData = jsonDecode(data);
        } else {
          messageData = Map<String, dynamic>.from(data);
        }

        final message = chat_msg.Message(
          id: messageData['id'] ?? '',
          senderId: messageData['sender_id'] ?? '',
          senderName: messageData['sender_name'] ?? '',
          content: '[語音消息]',
          timestamp: DateTime.parse(
              messageData['timestamp'] ?? DateTime.now().toIso8601String()),
          roomId: messageData['room'] ?? '',
          type: chat_msg.MessageType.voice,
          fileUrl: messageData['file_url'],
          duration: messageData['duration'] as int?,
          fileSize: messageData['file_size'] as int?,
        );

        _notifyMessageReceived(message);
      } catch (e) {
        print('Error parsing voice message: $e');
      }
    });

    socket.on('chat_message', (data) {
      try {
        print('Received message data: $data');

        Map<String, dynamic> messageData;
        if (data is String) {
          messageData = jsonDecode(data);
        } else {
          messageData = Map<String, dynamic>.from(data);
        }

        final message = chat_msg.Message.fromJson(messageData);
        _notifyMessageReceived(message);
      } catch (e) {
        print('Error parsing message: $e');
      }
    });

    socket.on('reaction_update', (data) {
      print('ChatService: 收到 reaction 更新: $data');
      try {
        Map<String, dynamic> reactionData;
        if (data is String) {
          reactionData = jsonDecode(data);
        } else {
          reactionData = Map<String, dynamic>.from(data);
        }

        final messageId = reactionData['message_id']?.toString() ??
            reactionData['messageId']?.toString();
        final reactionsRaw = reactionData['reactions'] as Map<String, dynamic>?;

        if (messageId != null && reactionsRaw != null) {
          final reactions = <String, List<String>>{};
          reactionsRaw.forEach((key, value) {
            if (value is List) {
              reactions[key] = value.map((e) => e.toString()).toList();
            }
          });

          print(
              'ChatService: 解析 reaction - messageId: $messageId, reactions: $reactions');
          _notifyReactionUpdate(messageId, reactions);
        }
      } catch (e) {
        print('ChatService: 處理 reaction 更新時出錯: $e');
      }
    });

    socket.on('room_updated', (data) {
      try {
        Map<String, dynamic> roomData;
        if (data is String) {
          roomData = jsonDecode(data);
        } else {
          roomData = Map<String, dynamic>.from(data);
        }

        final room = ChatRoom.fromJson(roomData);
        _notifyRoomUpdated(room);
      } catch (e) {
        print('Error parsing room update: $e');
      }
    });

    socket.on('user_status', (data) {
      try {
        Map<String, dynamic> statusData;
        if (data is String) {
          statusData = jsonDecode(data);
        } else {
          statusData = Map<String, dynamic>.from(data);
        }

        final userId = statusData['user_id'] as String;
        final isOnline = statusData['is_online'] as bool;
        _notifyUserStatusChanged(userId, isOnline);
      } catch (e) {
        print('Error parsing user status: $e');
      }
    });
  }

  // === 通知方法 ===

  void _notifyMessageReceived(chat_msg.Message message) {
    print('ChatService: 準備通知 ${_messageReceivedCallbacks.length} 個消息監聽器');
    _messageCache.addMessageToCache(message.roomId, message);

    _messageReceivedCallbacks.forEach((id, callback) {
      try {
        callback(message);
      } catch (e) {
        print('ChatService: 監聽器 $id 調用失敗: $e');
      }
    });

    _handleNotificationForMessage(message);
  }

  // 🔥 新增：通知消息已读
  void _notifyMessageRead(String roomId, String userId) {
    print('ChatService: 通知 ${_messageReadCallbacks.length} 個消息已讀監聽器');
    _messageReadCallbacks.forEach((id, callback) {
      try {
        callback(roomId, userId);
      } catch (e) {
        print('ChatService: 消息已讀監聽器 $id 調用失敗: $e');
      }
    });
  }

  // 🔥 新增：通知 Typing 狀態
  void _notifyTyping(String roomId, String username, bool isTyping) {
    _typingCallbacks.forEach((id, callback) {
      try {
        callback(roomId, username, isTyping);
      } catch (e) {
        print('ChatService: Typing 監聽器 $id 調用失敗: $e');
      }
    });
  }

  // 🔥 新增：通知 Reaction 更新
  void _notifyReactionUpdate(
      String messageId, Map<String, List<String>> reactions) {
    print('ChatService: 通知 ${_reactionUpdateCallbacks.length} 個 Reaction 監聽器');

    _reactionUpdateCallbacks.forEach((id, callback) {
      try {
        callback(messageId, reactions);
      } catch (e) {
        print('ChatService: Reaction 監聽器 $id 調用失敗: $e');
      }
    });
  }

  Future<void> _handleNotificationForMessage(chat_msg.Message message) async {
    try {
      final userInfo = await TokenStorage.getUser();
      final currentUserId = userInfo?['id']?.toString();

      if (currentUserId != null && message.senderId == currentUserId) {
        return;
      }

      String chatRoomName =
          _chatRoomNames[message.roomId] ?? message.senderName;
      if (chatRoomName.isEmpty) {
        chatRoomName = '聊天室';
      }

      await _notificationService.showChatNotification(
        message: message,
        chatRoomName: chatRoomName,
      );
    } catch (e) {
      print('ChatService: 處理通知時發生錯誤: $e');
    }
  }

  void _notifyConnectionChanged(bool isConnected) {
    _connectionChangedCallbacks.forEach((id, callback) {
      try {
        callback(isConnected);
      } catch (e) {
        print('Error in connection callback $id: $e');
      }
    });
  }

  void _notifyRoomUpdated(ChatRoom room) {
    _roomUpdatedCallbacks.forEach((id, callback) {
      try {
        callback(room);
      } catch (e) {
        print('Error in room update callback $id: $e');
      }
    });
  }

  void _notifyUserStatusChanged(String userId, bool isOnline) {
    _userStatusChangedCallbacks.forEach((id, callback) {
      try {
        callback(userId, isOnline);
      } catch (e) {
        print('Error in user status callback $id: $e');
      }
    });
  }

  void _handleAuthenticationError(dynamic error) {
    final errorText = error.toString().toLowerCase();
    final isTokenExpired = errorText.contains('token is expired') ||
        errorText.contains('token expired') ||
        errorText.contains('expired token') ||
        errorText.contains('jwt expired') ||
        errorText.contains('authentication') ||
        errorText.contains('invalid token');

    if (isTokenExpired) {
      _socketClient.disableReconnect();
      _socketClient.disconnect();
      ApiClientService().clearTokensAndLogout();
      return;
    }
  }

  // === 公開方法 ===

  void joinRoom(String roomId) {
    if (_socketClient.emit('join_room', roomId)) {
      print('ChatService: 加入房間成功: $roomId');
    }
  }

  void leaveRoom(String roomId) {
    _socketClient.emit('leave_room', roomId);
  }

  void sendMessage(String roomId, String content,
      {chat_msg.MessageType type = chat_msg.MessageType.text}) {
    final messageData = {
      'room': roomId,
      'content': content,
      'type': type.toString().split('.').last,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (!_socketClient.emit('chat_message', messageData)) {
      throw Exception('Socket not connected');
    }
  }

  void sendTypingStatus(String roomId, bool isTyping) {
    _socketClient.emit('typing', {
      'room': roomId,
      'is_typing': isTyping,
    });
  }

  void sendVoiceMessage(String roomId, voice_msg.VoiceMessage voiceMessage) {
    final messageData = {
      'id': voiceMessage.id,
      'sender_id': voiceMessage.senderId,
      'sender_name': voiceMessage.senderName,
      'room': roomId,
      'file_url': voiceMessage.fileUrl,
      'duration': voiceMessage.duration,
      'file_size': voiceMessage.fileSize,
      'timestamp': voiceMessage.timestamp.toIso8601String(),
      'type': 'voice',
    };

    if (!_socketClient.emit('voice_message', messageData)) {
      throw Exception('Socket not connected');
    }
  }

  void sendImageMessage(String roomId, String imageUrl) {
    final messageData = {
      'room': roomId,
      'content': '[图片]',
      'file_url': imageUrl,
      'type': 'image',
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (!_socketClient.emit('image_message', messageData)) {
      throw Exception('Socket not connected');
    }
  }

  void sendVideoMessage(String roomId, String videoUrl) {
    final messageData = {
      'room': roomId,
      'content': '[视频]',
      'file_url': videoUrl,
      'type': 'video',
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (!_socketClient.emit('video_message', messageData)) {
      throw Exception('Socket not connected');
    }
  }

  // 🔥 發送 Reaction
  void sendReaction(String messageId, String emoji) {
    if (!_socketClient.isConnected) {
      print('ChatService: Socket 未連接，無法發送 reaction');
      return;
    }

    try {
      _socketClient.emit('message_reaction', {
        'message_id': messageId, // 使用 message_id
        'emoji': emoji,
        'timestamp': DateTime.now().toIso8601String(),
      });
      print('ChatService: 已發送 reaction: $emoji 給消息 $messageId');
    } catch (e) {
      print('ChatService: 發送 reaction 時出錯: $e');
    }
  }

  Future<bool> checkNetworkConnection() async {
    return await _connectionManager.checkConnection();
  }

  bool get isConnected => _socketClient.isConnected;
  bool get isConnecting => _socketClient.isConnecting;

  void disconnect() {
    _notificationService.clearAllNotifications();
    _connectionManager.dispose();
    _socketClient.disconnect();
  }

  void disableReconnect() {
    _socketClient.disableReconnect();
  }

  Future<void> reconnect() async {
    disconnect();
    _socketClient.enableReconnect();
    await Future.delayed(const Duration(seconds: 1));

    final hasNetwork = await checkNetworkConnection();
    if (!hasNetwork) {
      throw Exception('No network connection');
    }

    try {
      await initialize();
    } catch (e) {
      _socketClient.scheduleReconnect();
      rethrow;
    }
  }

  Future<void> forceReconnect() async {
    _socketClient.resetReconnectAttempts();
    await reconnect();
  }

  void setCurrentActiveChatRoom(String? roomId) {
    _notificationService.setCurrentActiveChatRoom(roomId);
    if (roomId != null) {
      _notificationService.clearChatNotifications(roomId);
    }
  }

  Map<String, dynamic> getConnectionStats() {
    return {
      'isConnected': _socketClient.isConnected,
      'isConnecting': _socketClient.isConnecting,
      'reconnectAttempts': _socketClient.reconnectAttempts,
      'maxReconnectAttempts': SocketClient.maxReconnectAttempts,
      'hasHeartbeat': _socketClient.hasHeartbeat,
      'messageListeners': _messageReceivedCallbacks.length,
      'connectionListeners': _connectionChangedCallbacks.length,
      'roomUpdateListeners': _roomUpdatedCallbacks.length,
      'userStatusListeners': _userStatusChangedCallbacks.length,
      'reactionListeners': _reactionUpdateCallbacks.length,
    };
  }

  void clearAllListeners() {
    _messageReceivedCallbacks.clear();
    _connectionChangedCallbacks.clear();
    _roomUpdatedCallbacks.clear();
    _userStatusChangedCallbacks.clear();
    _reactionUpdateCallbacks.clear();
  }

  void printListenerStats() {
    print('ChatService 監聽器統計:');
    print('- 消息監聽器: ${_messageReceivedCallbacks.keys.toList()}');
    print('- 連接監聽器: ${_connectionChangedCallbacks.keys.toList()}');
    print('- Reaction 監聽器: ${_reactionUpdateCallbacks.keys.toList()}');
  }

  void debugNotificationFlow() {
    print('=== ChatService 通知流程調試 ===');
    print('消息監聽器數量: ${_messageReceivedCallbacks.length}');
    print('Reaction 監聽器數量: ${_reactionUpdateCallbacks.length}');
    print('聊天室名稱映射: $_chatRoomNames');
    print('Socket 連接狀態: ${_socketClient.isConnected}');
    print('================================');
  }
}
