import 'dart:io';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/models/message.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/websocket/websocket_service.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

// State for the Chat Room
class ChatRoomState {
  final List<Message> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final List<String> typingUsers;
  final bool isConnected;

  const ChatRoomState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.typingUsers = const [],
    this.isConnected = false,
  });

  ChatRoomState copyWith({
    List<Message>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
    List<String>? typingUsers,
    bool? isConnected,
  }) {
    return ChatRoomState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: error ?? this.error,
      typingUsers: typingUsers ?? this.typingUsers,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

// Parameters for the ViewModel
class ChatRoomParams extends Equatable {
  final String roomId;
  final bool isRoom;
  final String currentUserId;
  final String token;

  const ChatRoomParams({
    required this.roomId,
    required this.isRoom,
    required this.currentUserId,
    required this.token,
  });

  @override
  List<Object?> get props => [roomId, isRoom, currentUserId, token];
}

// ViewModel (Notifier)
class ChatRoomViewModel extends FamilyNotifier<ChatRoomState, ChatRoomParams> {
  late final NetworkService _network;
  late final WebSocketService _wsService;
  Timer? _typingTimer;
  bool _typingSent = false;

  @override
  ChatRoomState build(ChatRoomParams arg) {
    _network = ref.watch(networkServiceProvider);
    _wsService = ref.watch(webSocketServiceProvider);

    // Connect WebSocket
    _wsService.connect();

    // Listen to WS events
    final subscription = _wsService.events.listen((data) {
      if (data is Map) {
        final event = data['event'];
        final payload = data['data'];

        if (event == 'chat_message') {
          try {
            final message = Message.fromJson(payload);
            if ((arg.isRoom && message.roomId == arg.roomId) ||
                (!arg.isRoom &&
                    (message.senderId == arg.roomId ||
                        message.receiverId == arg.roomId))) {
              _addMessage(message);
              if (message.senderId != arg.currentUserId) {
                markAsRead();
              }
            }
          } catch (e) {
            print('Error parsing message: $e');
          }
        } else if (event == 'message_ack') {
          if (payload is Map) {
            final clientMsgId = payload['client_msg_id'];
            final messageId = payload['message_id'];
            if (clientMsgId is String && messageId is String) {
              _replaceMessageId(clientMsgId, messageId);
              _updateMessageStatus(clientMsgId, MessageStatus.sent);
            }
          }
        } else if (event == 'message_delivered') {
          if (payload is Map) {
            final clientMsgId = payload['client_msg_id'];
            final messageId = payload['message_id'];
            if (clientMsgId is String) {
              _updateMessageStatus(clientMsgId, MessageStatus.delivered);
            } else if (messageId is String) {
              _updateMessageStatus(messageId, MessageStatus.delivered);
            }
          }
        } else if (event == 'typing_start') {
          // Basic typing indicator logic
          final roomId = payload['room_id'];
          final userId = payload['user_id'];

          if (roomId == arg.roomId && userId != arg.currentUserId) {
            if (!state.typingUsers.contains(userId)) {
              state = state.copyWith(
                typingUsers: [...state.typingUsers, userId],
              );

              // Auto clear after 3 seconds
              Future.delayed(const Duration(seconds: 3), () {
                if (state.typingUsers.contains(userId)) {
                  state = state.copyWith(
                    typingUsers: state.typingUsers
                        .where((id) => id != userId)
                        .toList(),
                  );
                }
              });
            }
          }
        } else if (event == 'typing_stop') {
          final roomId = payload['room_id'];
          final userId = payload['user_id'];
          if (roomId == arg.roomId && userId != arg.currentUserId) {
            if (state.typingUsers.contains(userId)) {
              state = state.copyWith(
                typingUsers: state.typingUsers
                    .where((id) => id != userId)
                    .toList(),
              );
            }
          }
        } else if (event == 'read_receipt') {
          if (payload is Map) {
            final readerId = payload['reader_id'];
            final conversationId = payload['conversation_id'];
            final readAtRaw = payload['read_at'];
            final readAt = readAtRaw is String
                ? DateTime.tryParse(readAtRaw)
                : null;
            if (readerId is String &&
                conversationId is String &&
                conversationId == arg.currentUserId &&
                readerId == arg.roomId) {
              _markConversationRead(readAt);
            }
          }
        }
      }
    });

    ref.onDispose(() {
      subscription.cancel();
      _typingTimer?.cancel();
    });

    Future.microtask(() => loadHistory());

    return const ChatRoomState(isConnected: true);
  }

  void _addMessage(Message msg) {
    final existingIndex = state.messages.indexWhere((m) {
      if (msg.clientMsgId != null && msg.clientMsgId!.isNotEmpty) {
        return m.clientMsgId == msg.clientMsgId || m.id == msg.clientMsgId;
      }
      return m.id == msg.id;
    });
    if (existingIndex != -1) {
      final updated = [...state.messages];
      updated[existingIndex] = msg;
      state = state.copyWith(messages: updated);
      return;
    }
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  void _replaceMessageId(String clientMsgId, String messageId) {
    final index = state.messages.indexWhere(
      (m) => m.clientMsgId == clientMsgId || m.id == clientMsgId,
    );
    if (index == -1) return;
    final existing = state.messages[index];
    final updated = Message(
      id: messageId,
      clientMsgId: existing.clientMsgId,
      content: existing.content,
      senderId: existing.senderId,
      receiverId: existing.receiverId,
      roomId: existing.roomId,
      type: existing.type,
      createdAt: existing.createdAt,
      isRead: existing.isRead,
      status: MessageStatus.sent,
      readAt: existing.readAt,
    );
    final messages = [...state.messages];
    messages[index] = updated;
    state = state.copyWith(messages: messages);
  }

  void _updateMessageStatus(String clientMsgId, MessageStatus status) {
    final index = state.messages.indexWhere(
      (m) => m.clientMsgId == clientMsgId || m.id == clientMsgId,
    );
    if (index == -1) return;
    final existing = state.messages[index];
    final updated = Message(
      id: existing.id,
      clientMsgId: existing.clientMsgId,
      content: existing.content,
      senderId: existing.senderId,
      receiverId: existing.receiverId,
      roomId: existing.roomId,
      type: existing.type,
      createdAt: existing.createdAt,
      isRead: existing.isRead,
      status: status,
      readAt: existing.readAt,
    );
    final messages = [...state.messages];
    messages[index] = updated;
    state = state.copyWith(messages: messages);
  }

  void _markConversationRead(DateTime? readAt) {
    final updated = state.messages.map((m) {
      if (m.senderId == arg.currentUserId &&
          m.receiverId == arg.roomId &&
          m.status != MessageStatus.read) {
        return Message(
          id: m.id,
          clientMsgId: m.clientMsgId,
          content: m.content,
          senderId: m.senderId,
          receiverId: m.receiverId,
          roomId: m.roomId,
          type: m.type,
          createdAt: m.createdAt,
          isRead: true,
          status: MessageStatus.read,
          readAt: readAt ?? DateTime.now(),
        );
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  // --- API Logic ---

  Future<void> loadHistory({int limit = 50, int offset = 0}) async {
    if (offset == 0) state = state.copyWith(isLoading: true);
    try {
      final response = await _network.client.get(
        '/messages/history',
        queryParameters: {
          'contact_id': arg.roomId,
          'limit': limit,
          'offset': offset,
        },
      );

      final List<dynamic> list = response.data['data'];
      final history = list.map((e) => Message.fromJson(e)).toList();

      final ordered = history.reversed.toList();
      state = state.copyWith(
        messages: offset == 0 ? ordered : [...ordered, ...state.messages],
        isLoading: false,
      );
      if (offset == 0) {
        markAsRead();
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> sendMessage(
    String content, {
    MessageType type = MessageType.text,
  }) async {
    final clientMsgId = const Uuid().v4();
    final tempMessage = Message(
      id: clientMsgId,
      clientMsgId: clientMsgId,
      content: content,
      senderId: arg.currentUserId,
      receiverId: arg.isRoom ? null : arg.roomId,
      roomId: arg.isRoom ? arg.roomId : null,
      type: type,
      createdAt: DateTime.now(),
      isRead: true,
      status: MessageStatus.sending,
    );
    _addMessage(tempMessage);

    final payload = {
      'receiver_id': arg.isRoom ? null : arg.roomId,
      'room_id': arg.isRoom ? arg.roomId : null,
      'content': content,
      'type': type.toString().split('.').last,
      'client_msg_id': clientMsgId,
    };

    try {
      await _wsService.send('chat_message', payload);
      _updateMessageStatus(clientMsgId, MessageStatus.sent);
    } catch (e) {
      _updateMessageStatus(clientMsgId, MessageStatus.failed);
    }
  }

  Future<void> retrySend(Message message) async {
    if (message.clientMsgId == null || message.clientMsgId!.isEmpty) {
      return;
    }
    final clientMsgId = message.clientMsgId!;
    _updateMessageStatus(clientMsgId, MessageStatus.sending);
    final payload = {
      'receiver_id': message.receiverId,
      'room_id': message.roomId,
      'content': message.content,
      'type': message.type.toString().split('.').last,
      'client_msg_id': clientMsgId,
    };
    try {
      await _wsService.send('chat_message', payload);
      _updateMessageStatus(clientMsgId, MessageStatus.sent);
    } catch (e) {
      _updateMessageStatus(clientMsgId, MessageStatus.failed);
    }
  }

  Future<void> sendMedia(File file, MessageType type) async {
    state = state.copyWith(isSending: true);
    try {
      final url = await _network.uploadFile(
        file,
        type == MessageType.image ? 'image' : 'voice',
      );
      await sendMessage(url, type: type);
      state = state.copyWith(isSending: false);
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> markAsRead() async {
    final payload = {'conversation_id': arg.roomId, 'is_room': arg.isRoom};
    _wsService.send('mark_read', payload);
    try {
      await _network.client.post('/messages/read', data: payload);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void startTyping() {
    if (!_typingSent) {
      _typingSent = true;
      _wsService.send('typing_start', {
        'room_id': arg.isRoom ? arg.roomId : null,
        'receiver_id': arg.isRoom ? null : arg.roomId,
      });
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _typingSent = false;
      _wsService.send('typing_stop', {
        'room_id': arg.isRoom ? arg.roomId : null,
        'receiver_id': arg.isRoom ? null : arg.roomId,
      });
    });
  }
}

// Provider Definition
final chatRoomProvider =
    NotifierProvider.family<ChatRoomViewModel, ChatRoomState, ChatRoomParams>(
      ChatRoomViewModel.new,
    );
