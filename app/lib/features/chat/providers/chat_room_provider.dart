import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/models/message.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/websocket/websocket_service.dart';
import 'package:equatable/equatable.dart';

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
        }
      }
    });

    ref.onDispose(() {
      subscription.cancel();
    });

    Future.microtask(() => loadHistory());

    return const ChatRoomState(isConnected: true);
  }

  void _addMessage(Message msg) {
    if (state.messages.any((m) => m.id == msg.id)) return;
    state = state.copyWith(messages: [...state.messages, msg]);
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

      state = state.copyWith(
        messages: offset == 0
            ? history.reversed.toList()
            : [...history.reversed, ...state.messages],
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
    final payload = {
      'receiver_id': arg.isRoom ? null : arg.roomId,
      'room_id': arg.isRoom ? arg.roomId : null,
      'content': content,
      'type': type.toString().split('.').last,
    };

    _wsService.send('chat_message', payload);
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
  }

  void startTyping() {
    _wsService.send('typing_start', {'room_id': arg.roomId});
  }
}

// Provider Definition
final chatRoomProvider =
    NotifierProvider.family<ChatRoomViewModel, ChatRoomState, ChatRoomParams>(
      ChatRoomViewModel.new,
    );
