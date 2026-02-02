// lib/services/chat_service.dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../config/api_config.dart';
import '../models/message.dart' as chat_msg;
import '../models/chat_room.dart';
import '../utils/token_storage.dart';
import 'notification_service.dart';
import 'network_monitor_service.dart';
import 'ios_network_monitor_service.dart';
import 'message_cache_service.dart';
import '../models/voice_message.dart' as voice_msg;

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  bool _allowReconnect = true;

  final NotificationService _notificationService = NotificationService();
  final NetworkMonitorService _networkMonitor = NetworkMonitorService();
  final IOSNetworkMonitorService _iosNetworkMonitor =
      IOSNetworkMonitorService();
  final MessageCacheService _messageCache = MessageCacheService();

  // 使用 Map 來管理多個監聽器
  final Map<String, Function(chat_msg.Message)> _messageReceivedCallbacks = {};
  final Map<String, Function(ChatRoom)> _roomUpdatedCallbacks = {};
  final Map<String, Function(String, bool)> _userStatusChangedCallbacks = {};
  final Map<String, Function(bool)> _connectionChangedCallbacks = {};

  // 🔥 新增：Reaction 更新回調
  final Map<String, Function(String, Map<String, List<String>>)>
      _reactionUpdateCallbacks = {};

  final Map<String, String> _chatRoomNames = {};

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

  // === 初始化方法 ===

  Future<void> initialize() async {
    if (_isConnecting || _isConnected) return;
    if (!_allowReconnect) {
      print('ChatService: initialize() skipped because reconnect is disabled');
      return;
    }

    try {
      _isConnecting = true;

      await _notificationService.initialize();
      await _networkMonitor.initialize();

      if (Platform.isIOS) {
        await _iosNetworkMonitor.initialize();
        _iosNetworkMonitor.addConnectionListener(_onNetworkStatusChanged);
        _iosNetworkMonitor.startAutoReconnect(_forceReconnect);
      } else {
        _networkMonitor.addConnectionListener(_onNetworkStatusChanged);
      }

      await _messageCache.initialize();

      final isValidToken = await TokenStorage.isTokenValid();
      if (!isValidToken) {
        print('ChatService: Token 無效或過期，停止初始化');
        _isConnecting = false;
        throw Exception('Token expired or invalid');
      }

      final token = await TokenStorage.getToken();
      if (token == null) {
        throw Exception('No authentication token found');
      }

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
            .setReconnectionAttempts(_maxReconnectAttempts)
            .enableReconnection()
            .enableAutoConnect()
            .enableForceNew()
            .build(),
      );

      _setupEventListeners();

      Timer(const Duration(seconds: 10), () {
        if (!_allowReconnect) return;
        if (_isConnecting && !_isConnected) {
          print('Connection timeout, retrying...');
          _retryConnection();
        }
      });

      _socket!.connect();
    } catch (e) {
      print('Socket initialization error: $e');
      _isConnecting = false;
      _handleAuthenticationError(e);

      if (_allowReconnect &&
          !e.toString().contains('expired') &&
          !e.toString().contains('invalid')) {
        _retryConnection();
      }
      throw e;
    }
  }

  // === 🔥 修正：合併後的事件監聽器設置 ===

  void _setupEventListeners() {
    if (_socket == null) return;

    // 連接相關事件
    _socket!.onConnect((_) {
      print('Socket connected successfully');
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _startHeartbeat();
      _notifyConnectionChanged(true);
    });

    _socket!.onDisconnect((reason) {
      print('Socket disconnected: $reason');
      _isConnected = false;
      _isConnecting = false;
      _stopHeartbeat();
      _notifyConnectionChanged(false);

      if (_allowReconnect && reason != 'client namespace disconnect') {
        _scheduleReconnect();
      }
    });

    _socket!.onConnectError((error) {
      print('Socket connection error: $error');
      _isConnected = false;
      _isConnecting = false;
      _notifyConnectionChanged(false);
      _handleAuthenticationError(error);

      if (_allowReconnect && !error.toString().contains('authentication')) {
        _scheduleReconnect();
      }
    });

    _socket!.on('auth_error', (data) {
      print('Socket auth error: $data');
      _handleAuthenticationError(data);
    });

    _socket!.onReconnectAttempt((attemptCount) {
      print('Attempting to reconnect... Attempt: $attemptCount');
      _isConnecting = true;
      _notifyConnectionChanged(false);
    });

    _socket!.onReconnect((attemptCount) {
      print('Reconnected successfully after $attemptCount attempts');
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _startHeartbeat();
      _notifyConnectionChanged(true);
    });

    _socket!.onReconnectError((error) {
      print('Reconnection error: $error');
      _isConnecting = false;
      _notifyConnectionChanged(false);
      _handleAuthenticationError(error);

      if (_allowReconnect && !error.toString().contains('authentication')) {
        _scheduleReconnect();
      }
    });

    _socket!.onReconnectFailed((_) {
      print('All reconnection attempts failed');
      _isConnecting = false;
      _notifyConnectionChanged(false);
      _scheduleReconnect();
    });

    // 🔥 消息相關事件

    // 語音消息
    _socket!.on('voice_message', (data) {
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

    // 普通文本消息
    _socket!.on('chat_message', (data) {
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

    // 🔥 Reaction 更新事件
    _socket!.on('reaction_update', (data) {
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

    // 聊天室更新
    _socket!.on('room_updated', (data) {
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

    // 用戶狀態變更
    _socket!.on('user_status', (data) {
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

    // 其他事件
    _socket!.on('pong', (_) {
      print('Received pong from server');
    });

    _socket!.on('error', (error) {
      print('Socket error: $error');
    });

    _socket!.on('connect_error', (error) {
      print('Connection error: $error');
      _isConnected = false;
      _isConnecting = false;
      _notifyConnectionChanged(false);
      _scheduleReconnect();
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

      await _notificationService.showChatNotificationSimple(
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

  // === 心跳和重連相關 ===

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_socket != null && _isConnected) {
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
    if (_reconnectAttempts >= _maxReconnectAttempts) return;

    bool isOnline =
        Platform.isIOS ? _iosNetworkMonitor.isOnline : _networkMonitor.isOnline;

    if (!isOnline) return;

    _reconnectTimer?.cancel();
    final delay = Duration(seconds: (2 << _reconnectAttempts).clamp(1, 30));

    _reconnectTimer = Timer(delay, () {
      bool isOnline = Platform.isIOS
          ? _iosNetworkMonitor.isOnline
          : _networkMonitor.isOnline;

      if (isOnline) {
        _retryConnection();
      }
    });
  }

  void _retryConnection() {
    if (!_allowReconnect) return;
    if (_isConnected || _isConnecting) return;

    bool isOnline =
        Platform.isIOS ? _iosNetworkMonitor.isOnline : _networkMonitor.isOnline;

    if (!isOnline) return;

    _reconnectAttempts++;
    disconnect();
    initialize().catchError((error) {
      _scheduleReconnect();
    });
  }

  void _handleAuthenticationError(dynamic error) {
    if (error.toString().contains('token is expired')) {
      // 🔥 不要直接清除，讓下次 API 請求時自動刷新
      print('ChatService: 檢測到 token 過期，等待自動刷新');
      // 只在確定無法刷新時才斷開連接
    }
  }

  void _onNetworkStatusChanged(bool isOnline) {
    if (isOnline) {
      if (!_isConnected && !_isConnecting && _allowReconnect) {
        _retryConnection();
      }
    } else {
      _reconnectTimer?.cancel();
      _isConnecting = false;
      _notifyConnectionChanged(false);
    }
  }

  void _forceReconnect() {
    if (!_allowReconnect) return;
    if (_isConnected || _isConnecting) return;
    _retryConnection();
  }

  // === 公開方法 ===

  void joinRoom(String roomId) {
    if (_socket != null && _isConnected) {
      _socket!.emit('join_room', roomId);
      print('ChatService: 加入房間成功: $roomId');
    }
  }

  void leaveRoom(String roomId) {
    if (_socket != null && _isConnected) {
      _socket!.emit('leave_room', roomId);
    }
  }

  void sendMessage(String roomId, String content,
      {chat_msg.MessageType type = chat_msg.MessageType.text}) {
    if (_socket != null && _isConnected) {
      final messageData = {
        'room': roomId,
        'content': content,
        'type': type.toString().split('.').last,
        'timestamp': DateTime.now().toIso8601String(),
      };

      _socket!.emit('chat_message', messageData);
    } else {
      throw Exception('Socket not connected');
    }
  }

  void sendTypingStatus(String roomId, bool isTyping) {
    if (_socket != null && _isConnected) {
      _socket!.emit('typing', {
        'room': roomId,
        'is_typing': isTyping,
      });
    }
  }

  void sendVoiceMessage(String roomId, voice_msg.VoiceMessage voiceMessage) {
    if (_socket != null && _isConnected) {
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

      _socket!.emit('voice_message', messageData);
    } else {
      throw Exception('Socket not connected');
    }
  }

  // 🔥 發送 Reaction
  void sendReaction(String messageId, String emoji) {
    if (_socket == null || !_socket!.connected) {
      print('ChatService: Socket 未連接，無法發送 reaction');
      return;
    }

    try {
      _socket!.emit('message_reaction', {
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

  bool get isConnected => _isConnected && !_isConnecting;
  bool get isConnecting => _isConnecting;

  void disconnect() {
    _allowReconnect = false;
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _notificationService.clearAllNotifications();

    if (Platform.isIOS) {
      _iosNetworkMonitor.removeConnectionListener(_onNetworkStatusChanged);
      _iosNetworkMonitor.stopAutoReconnect();
    } else {
      _networkMonitor.removeConnectionListener(_onNetworkStatusChanged);
    }

    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    _isConnected = false;
    _isConnecting = false;
    _reconnectAttempts = 0;
    _notifyConnectionChanged(false);
  }

  void disableReconnect() {
    _allowReconnect = false;
    _reconnectTimer?.cancel();
  }

  Future<void> reconnect() async {
    disconnect();
    _allowReconnect = true;
    await Future.delayed(const Duration(seconds: 1));

    final hasNetwork = await checkNetworkConnection();
    if (!hasNetwork) {
      throw Exception('No network connection');
    }

    try {
      await initialize();
    } catch (e) {
      _scheduleReconnect();
      rethrow;
    }
  }

  Future<void> forceReconnect() async {
    _reconnectAttempts = 0;
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
      'isConnected': _isConnected,
      'isConnecting': _isConnecting,
      'reconnectAttempts': _reconnectAttempts,
      'maxReconnectAttempts': _maxReconnectAttempts,
      'hasHeartbeat': _heartbeatTimer != null,
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
    print('Socket 連接狀態: $_isConnected');
    print('================================');
  }
}
