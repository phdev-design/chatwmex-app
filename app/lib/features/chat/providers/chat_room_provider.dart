import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/models/message.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/media/media_service.dart';
import 'package:app/core/websocket/websocket_service.dart';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/features/chat/providers/room_list_provider.dart';
import 'package:equatable/equatable.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/features/chat/providers/e2ee_provider.dart';

// State for the Chat Room
class ChatRoomState {
  final List<Message> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final List<String> typingUsers;
  final bool isConnected;
  final bool isLoadingMore;
  final bool hasMore;
  final int offset;
  final Message? replyingToMessage;
  final bool isRecording;
  final Map<String, String> userAvatarUrls;
  final String roomAvatarUrl;

  const ChatRoomState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.typingUsers = const [],
    this.isConnected = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.offset = 0,
    this.replyingToMessage,
    this.isRecording = false,
    this.userAvatarUrls = const {},
    this.roomAvatarUrl = '',
  });

  ChatRoomState copyWith({
    List<Message>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
    List<String>? typingUsers,
    bool? isConnected,
    bool? isLoadingMore,
    bool? hasMore,
    int? offset,
    Message? replyingToMessage,
    bool? isRecording,
    Map<String, String>? userAvatarUrls,
    String? roomAvatarUrl,
    bool clearReplyingTo = false,
    bool clearError = false,
  }) {
    return ChatRoomState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
      typingUsers: typingUsers ?? this.typingUsers,
      isConnected: isConnected ?? this.isConnected,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      replyingToMessage: clearReplyingTo
          ? null
          : (replyingToMessage ?? this.replyingToMessage),
      isRecording: isRecording ?? this.isRecording,
      userAvatarUrls: userAvatarUrls ?? this.userAvatarUrls,
      roomAvatarUrl: roomAvatarUrl ?? this.roomAvatarUrl,
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
  late final ChatRepository _chatRepository;
  late final CryptoService _cryptoService;
  late final PublicKeyCacheService _publicKeyCacheService;
  Timer? _typingTimer;
  bool _typingSent = false;

  Timer? _markConversationReadTimer;
  DateTime? _lastMarkConversationReadTime;

  Timer? _readBatchTimer;
  DateTime? _lastReadBatchTime;

  final Set<String> _pendingReadMessageIds = {};
  final LinkedHashSet<String> _alreadyReportedMessageIds = LinkedHashSet();

  @override
  ChatRoomState build(ChatRoomParams arg) {
    _network = ref.watch(networkServiceProvider);
    _wsService = ref.watch(webSocketServiceProvider);
    _chatRepository = ref.watch(chatRepositoryProvider);
    _cryptoService = ref.watch(cryptoServiceProvider);
    _publicKeyCacheService = ref.watch(publicKeyCacheServiceProvider);
    var initialRoomAvatarUrl = '';
    if (!arg.isRoom) {
      final rooms = ref.read(roomListViewModelProvider).rooms;
      for (final room in rooms) {
        if (room.id == arg.roomId && room.avatarUrl != null) {
          initialRoomAvatarUrl = room.avatarUrl!;
          break;
        }
      }
    }

    _wsService.connect();

    final subscription = _wsService.events.listen((data) {
      if (data is Map) {
        final event = data['event'];
        final payload = data['data'];

        if (event == 'ws_reconnected') {
          resendPendingMessages();
        } else if (event == 'chat_message') {
          try {
            final rawMessage = Message.fromJson(payload);
            _tryDecryptMessage(rawMessage).then((message) {
              if ((arg.isRoom && message.roomId == arg.roomId) ||
                  (!arg.isRoom &&
                      (message.senderId == arg.roomId ||
                          message.receiverId == arg.roomId))) {
                _addMessage(message);
                Future(
                  () => LocalDbService().insertMessages([rawMessage]),
                );
                if (message.senderId != arg.currentUserId) {
                  _wsService.send('message_delivered', {
                    'message_id': message.id,
                    'room_id': (arg.isRoom ? arg.roomId : null),
                    'sender_id': message.senderId,
                  });
                  if (arg.isRoom) {
                    markAsRead(message.id);
                  } else {
                    markConversationAsRead();
                  }
                }
              }
            });
          } catch (e) {
            debugPrint('Error parsing message: $e');
          }
        } else if (event == 'error') {
          if (payload is Map && payload['message'] == 'cannot_send_blocked') {
            state = state.copyWith(error: '無法傳送訊息，你已被對方封鎖或已封鎖對方');
          } else if (payload is Map && payload['message'] != null) {
            state = state.copyWith(error: payload['message'].toString());
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
        } else if (event == 'message_delivered' || event == 'message_read') {
          if (payload is Map) {
            final clientMsgId = payload['client_msg_id'];
            final messageId = payload['message_id'];
            final status = event == 'message_read'
                ? MessageStatus.read
                : MessageStatus.delivered;

            if (clientMsgId is String) {
              _updateMessageStatus(clientMsgId, status);
            } else if (messageId is String) {
              _updateMessageStatus(messageId, status);
            }
          }
        } else if (event == 'typing_start') {
          final roomId = payload['room_id'];
          final userId = payload['user_id'];

          if (roomId == arg.roomId && userId != arg.currentUserId) {
            if (!state.typingUsers.contains(userId)) {
              state = state.copyWith(
                typingUsers: [...state.typingUsers, userId],
              );
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
        } else if (event == 'messages_read_receipt') {
          if (payload is Map) {
            final roomId = payload['room_id'];
            final readBy = payload['read_by_user_id'];
            final messageIds = payload['message_ids'];
            if (roomId is String &&
                readBy is String &&
                messageIds is List &&
                roomId == arg.roomId) {
              _applyReadReceipt(
                messageIds.map((e) => e.toString()).toList(),
                readBy,
              );
            }
          }
        } else if (event == 'messages_delivered_receipt') {
          if (payload is Map) {
            final roomId = payload['room_id'];
            final messageIds = payload['message_ids'];
            if (roomId is String &&
                messageIds is List &&
                roomId == arg.roomId) {
              for (final msgId in messageIds) {
                if (msgId is String) {
                  _updateMessageStatus(msgId, MessageStatus.delivered);
                }
              }
            }
          }
        } else if (event == 'message_reaction') {
          if (payload is Map) {
            final roomId = payload['room_id'];
            final messageId = payload['message_id'];
            final reactionsRaw = payload['reactions'];
            if (roomId is String &&
                messageId is String &&
                roomId == arg.roomId) {
              final reactions = _parseReactionsMap(reactionsRaw);
              _applyReactionUpdate(messageId, reactions);
            }
          }
        } else if (event == 'message_unsent') {
          if (payload is Map) {
            final roomId = payload['room_id'];
            final messageId = payload['message_id'];
            if (roomId is String &&
                messageId is String &&
                roomId == arg.roomId) {
              _applyUnsentUpdate(messageId);
            }
          }
        } else if (event == 'user_profile_updated') {
          if (payload is Map) {
            final userId = payload['user_id'];
            final avatarUrl = payload['avatar_url'];
            if (userId is String && avatarUrl is String) {
              _applyUserAvatarUpdated(arg, userId, avatarUrl);
            }
          }
        } else if (event == 'room_updated') {
          if (payload is Map) {
            final roomId = payload['room_id']?.toString();
            final avatarUrl = payload['avatar_url']?.toString();
            if (roomId == arg.roomId && avatarUrl != null) {
              state = state.copyWith(roomAvatarUrl: avatarUrl);
            }
          }
        }
      }
    });

    ref.onDispose(() {
      subscription.cancel();
      _typingTimer?.cancel();
      _markConversationReadTimer?.cancel();
      _readBatchTimer?.cancel();
    });

    Future.microtask(() => loadHistory());

    return ChatRoomState(
      isConnected: true,
      roomAvatarUrl: initialRoomAvatarUrl,
    );
  }

  void _addMessage(Message msg) {
    final hydrated = _attachReplyMessage(msg);
    final existingIndex = state.messages.indexWhere((m) {
      if (hydrated.clientMsgId != null && hydrated.clientMsgId!.isNotEmpty) {
        return m.clientMsgId == hydrated.clientMsgId ||
            m.id == hydrated.clientMsgId;
      }
      return m.id == hydrated.id;
    });
    if (existingIndex != -1) {
      final updated = [...state.messages];
      updated[existingIndex] = hydrated;
      state = state.copyWith(messages: updated);
      return;
    }
    state = state.copyWith(
      messages: [hydrated, ...state.messages],
      offset: state.offset + 1,
    );
  }

  void _applyUserAvatarUpdated(
    ChatRoomParams arg,
    String userId,
    String avatarUrl,
  ) {
    final avatars = Map<String, String>.from(state.userAvatarUrls);
    avatars[userId] = avatarUrl;
    String roomAvatarUrl = state.roomAvatarUrl;
    if (!arg.isRoom && arg.roomId == userId) {
      roomAvatarUrl = avatarUrl;
    }
    state = state.copyWith(
      userAvatarUrls: avatars,
      roomAvatarUrl: roomAvatarUrl,
    );
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
      replyToMessageId: existing.replyToMessageId,
      replyToMessage: existing.replyToMessage,
      reactions: existing.reactions,
      isUnsent: existing.isUnsent,
      type: existing.type,
      createdAt: existing.createdAt,
      isRead: existing.isRead,
      status: MessageStatus.sent,
      readAt: existing.readAt,
      readBy: existing.readBy,
      linkPreview: existing.linkPreview, // 🔥 保留預覽
    );
    final messages = [...state.messages];
    messages[index] = updated;
    state = state.copyWith(messages: messages);
    Future(() => LocalDbService().insertMessages([updated]));
    Future(() => LocalDbService().deleteMessageLocal(clientMsgId));
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
      replyToMessageId: existing.replyToMessageId,
      replyToMessage: existing.replyToMessage,
      reactions: existing.reactions,
      isUnsent: existing.isUnsent,
      type: existing.type,
      createdAt: existing.createdAt,
      isRead: existing.isRead,
      status: status,
      readAt: existing.readAt,
      readBy: existing.readBy,
      linkPreview: existing.linkPreview, // 🔥 保留預覽
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
        final readBy = {...m.readBy, arg.currentUserId}.toList();
        return Message(
          id: m.id,
          clientMsgId: m.clientMsgId,
          content: m.content,
          senderId: m.senderId,
          receiverId: m.receiverId,
          roomId: m.roomId,
          replyToMessageId: m.replyToMessageId,
          replyToMessage: m.replyToMessage,
          reactions: m.reactions,
          isUnsent: m.isUnsent,
          type: m.type,
          createdAt: m.createdAt,
          isRead: true,
          status: MessageStatus.read,
          readAt: readAt ?? DateTime.now(),
          readBy: readBy,
          linkPreview: m.linkPreview, // 🔥 保留預覽
        );
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
  }

  void _applyReadReceipt(List<String> messageIds, String readByUserId) {
    final idSet = messageIds.toSet();
    final List<Message> updatedMessages = [];
    final updated = state.messages.map((m) {
      if (idSet.contains(m.id) && !m.readBy.contains(readByUserId)) {
        final newMessage = Message(
          id: m.id,
          clientMsgId: m.clientMsgId,
          content: m.content,
          senderId: m.senderId,
          receiverId: m.receiverId,
          roomId: m.roomId,
          replyToMessageId: m.replyToMessageId,
          replyToMessage: m.replyToMessage,
          reactions: m.reactions,
          isUnsent: m.isUnsent,
          type: m.type,
          createdAt: m.createdAt,
          isRead: m.isRead,
          status: m.status,
          readAt: m.readAt,
          readBy: [...m.readBy, readByUserId],
          linkPreview: m.linkPreview, // 🔥 保留預覽
        );
        updatedMessages.add(newMessage);
        return newMessage;
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updated);
    if (updatedMessages.isNotEmpty) {
      Future(() => LocalDbService().insertMessages(updatedMessages));
    }
  }

  Future<String?> _getPublicKey(String userId) async {
    if (arg.isRoom) return null;
    return await _publicKeyCacheService.getPublicKey(userId);
  }

  Future<Message> _tryDecryptMessage(Message m) async {
    if (arg.isRoom) return m;
    if (m.isUnsent || m.content.isEmpty) return m;

    final isE2EEEnabled =
        ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;
    if (!isE2EEEnabled) return m;

    final opponentId = (m.senderId == arg.currentUserId)
        ? m.receiverId
        : m.senderId;
    if (opponentId == null) return m;

    final pubKey = await _getPublicKey(opponentId);
    if (pubKey == null) return m;

    final decrypted = await _cryptoService.decryptMessage(m.content, pubKey);

    if (decrypted != m.content) {
      return m.copyWith(content: decrypted);
    }

    final looksLikeCiphertext = _looksLikeE2EECiphertext(m.content);
    if (looksLikeCiphertext) {
      return m.copyWith(content: '🔒 此訊息無法解密（金鑰已更新）');
    }
    return m;
  }

  bool _looksLikeE2EECiphertext(String content) {
    if (content.length < 40) {
      return false;
    }
    final base64Regex = RegExp(r'^[A-Za-z0-9+/]+=*$');
    return base64Regex.hasMatch(content.trim());
  }

  Future<List<Message>> _decryptMessages(List<Message> messages) async {
    final futures = messages.map((m) => _tryDecryptMessage(m));
    return Future.wait(futures);
  }

  Future<void> loadHistory({int limit = 50, int offset = 0}) async {
    if (offset == 0) {
      state = state.copyWith(isLoading: true);
    }
    try {
      final history = await _chatRepository.getMessages(
        arg.roomId,
        limit: limit,
        offset: offset,
      );
      final ordered = history.map(_attachReplyMessage).toList();
      final decrypted = await _decryptMessages(ordered);
      state = state.copyWith(
        messages: offset == 0 ? decrypted : [...state.messages, ...decrypted],
        isLoading: false,
        offset: offset == 0 ? ordered.length : state.offset + ordered.length,
        hasMore: ordered.length >= limit,
      );
      if (offset == 0) {
        if (arg.isRoom) {
          _preloadRoomMemberAvatars();
        }
        if (arg.isRoom) {
          final ids = ordered
              .where(
                (m) =>
                    m.senderId != arg.currentUserId &&
                    !m.readBy.contains(arg.currentUserId),
              )
              .map((m) => m.id)
              .where((id) => id.isNotEmpty)
              .toList();
          for (final id in ids) {
            markAsRead(id);
          }
        } else {
          markConversationAsRead();
        }
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> _preloadRoomMemberAvatars() async {
    try {
      final members = await _chatRepository.getRoomMemberProfiles(arg.roomId);
      if (members.isEmpty) return;
      final avatars = Map<String, String>.from(state.userAvatarUrls);
      for (final user in members) {
        final avatarUrl = user.avatarUrl;
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          avatars[user.id] = avatarUrl;
        }
      }
      state = state.copyWith(userAvatarUrls: avatars);
    } catch (_) {
      debugPrint('Error caught');
    }
  }

  Future<void> loadMoreMessages() async {
    if (state.isLoadingMore || !state.hasMore) {
      return;
    }
    state = state.copyWith(isLoadingMore: true);
    try {
      final olderMessages = await _chatRepository.getMessages(
        arg.roomId,
        limit: 50,
        offset: state.offset,
      );
      final hydrated = olderMessages.map(_attachReplyMessage).toList();
      final decrypted = await _decryptMessages(hydrated);
      final hasMore = olderMessages.length >= 50;
      state = state.copyWith(
        messages: [...state.messages, ...decrypted],
        isLoadingMore: false,
        hasMore: hasMore,
        offset: state.offset + 50,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  Future<void> resendPendingMessages() async {
    final pending = await LocalDbService().getPendingMessages();
    if (pending.isEmpty) return;

    for (final message in pending) {
      final isRelevant =
          (arg.isRoom && message.roomId == arg.roomId) ||
          (!arg.isRoom &&
              (message.receiverId == arg.roomId ||
                  message.senderId == arg.roomId));

      if (!isRelevant) continue;

      String payloadContent = message.content;
      final isE2EEEnabled =
          ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;

      if (!arg.isRoom && isE2EEEnabled) {
        final pubKey = await _getPublicKey(arg.roomId);
        if (pubKey != null) {
          try {
            payloadContent = await _cryptoService.encryptMessage(
              message.content,
              pubKey,
            );
          } catch (e) {
            debugPrint('Failed to encrypt pending message: $e');
            continue;
          }
        }
      }

      final payload = {
        'receiver_id': message.receiverId,
        'room_id': message.roomId,
        'reply_to_message_id': message.replyToMessageId,
        'content': payloadContent,
        'type': message.type.name,
        'client_msg_id': message.clientMsgId,
        // 🔥 修復：加上 link_preview 屬性
        if (message.linkPreview != null) 'link_preview': {
          'url': message.linkPreview!.url,
          'title': message.linkPreview!.title,
          'description': message.linkPreview!.description,
          if (message.linkPreview!.imageUrl != null) 'image_url': message.linkPreview!.imageUrl,
        },
      };

      try {
        await _wsService.send('chat_message', payload);
        _updateMessageStatus(message.clientMsgId!, MessageStatus.sent);
        await LocalDbService().updateMessageStatus(
          message.clientMsgId!,
          MessageStatus.sent,
        );
      } catch (e) {
        debugPrint(
          'Failed to resend pending message ${message.clientMsgId}: $e',
        );
      }
    }
  }

  Future<void> sendMessage(
    String content, {
    MessageType type = MessageType.text,
    dynamic linkPreview, // 🔥 接收 link preview 參數 (使用 dynamic 以對應 Message 內的型別)
  }) async {
    final clientMsgId = const Uuid().v4();
    final replyToId = state.replyingToMessage?.id;
    final tempMessage = Message(
      id: clientMsgId,
      clientMsgId: clientMsgId,
      content: content,
      senderId: arg.currentUserId,
      receiverId: arg.isRoom ? null : arg.roomId,
      roomId: arg.isRoom ? arg.roomId : null,
      replyToMessageId: replyToId,
      replyToMessage: state.replyingToMessage,
      reactions: null,
      isUnsent: false,
      type: type,
      createdAt: DateTime.now(),
      isRead: true,
      status: MessageStatus.pending,
      readBy: [arg.currentUserId],
      linkPreview: linkPreview, // 🔥 儲存 link preview
    );

    await LocalDbService().insertMessages([tempMessage]);
    _addMessage(tempMessage);
    state = state.copyWith(isSending: true, clearReplyingTo: true);

    String payloadContent = content;
    final isE2EEEnabled =
        ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;

    if (!arg.isRoom && isE2EEEnabled) {
      final pubKey = await _getPublicKey(arg.roomId);
      if (pubKey != null) {
        try {
          payloadContent = await _cryptoService.encryptMessage(content, pubKey);
        } catch (e) {
          debugPrint('Failed to encrypt message: $e');
        }
      }
    }

    final payload = {
      'receiver_id': arg.isRoom ? null : arg.roomId,
      'room_id': arg.isRoom ? arg.roomId : null,
      'reply_to_message_id': replyToId,
      'content': payloadContent,
      'type': type.toString().split('.').last,
      'client_msg_id': clientMsgId,
      // 🔥 將 link preview 加入 payload
      if (linkPreview != null) 'link_preview': {
        'url': linkPreview.url,
        'title': linkPreview.title,
        'description': linkPreview.description,
        if (linkPreview.imageUrl != null) 'image_url': linkPreview.imageUrl,
      },
    };

    print('📤 [ChatRoom] 發送訊息 payload: ${payload.containsKey('link_preview') ? '包含 Link Preview' : '純文字'}');

    try {
      await _wsService.send('chat_message', payload);
      _updateMessageStatus(clientMsgId, MessageStatus.sent);
      final sentMsg = tempMessage.copyWith(status: MessageStatus.sent);
      Future.microtask(() => LocalDbService().insertMessages([sentMsg]));
      state = state.copyWith(isSending: false);
    } catch (e) {
      debugPrint('⚠️ WS send failed, message kept as pending: $e');
      state = state.copyWith(isSending: false);
    }
  }

  Future<void> retrySend(Message message) async {
    if (message.clientMsgId == null || message.clientMsgId!.isEmpty) {
      return;
    }
    final clientMsgId = message.clientMsgId!;
    _updateMessageStatus(clientMsgId, MessageStatus.sending);

    String payloadContent = message.content;
    final isE2EEEnabled =
        ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;

    if (!arg.isRoom && isE2EEEnabled) {
      final pubKey = await _getPublicKey(arg.roomId);
      if (pubKey != null) {
        try {
          payloadContent = await _cryptoService.encryptMessage(
            message.content,
            pubKey,
          );
        } catch (e) {
          debugPrint('Failed to encrypt retry: $e');
        }
      }
    }

    final payload = {
      'receiver_id': message.receiverId,
      'room_id': message.roomId,
      'reply_to_message_id': message.replyToMessageId,
      'content': payloadContent,
      'type': message.type.toString().split('.').last,
      'client_msg_id': clientMsgId,
      // 🔥 修復：加上 link_preview 屬性
      if (message.linkPreview != null) 'link_preview': {
        'url': message.linkPreview!.url,
        'title': message.linkPreview!.title,
        'description': message.linkPreview!.description,
        if (message.linkPreview!.imageUrl != null) 'image_url': message.linkPreview!.imageUrl,
      },
    };
    try {
      await _wsService.send('chat_message', payload);
      _updateMessageStatus(clientMsgId, MessageStatus.sent);
      Future.microtask(() => LocalDbService().insertMessages([message]));
      state = state.copyWith(isSending: false, clearReplyingTo: true);
    } catch (e) {
      _updateMessageStatus(clientMsgId, MessageStatus.failed);
      state = state.copyWith(isSending: false, error: e.toString());
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

  Future<void> startRecording() async {
    final mediaService = ref.read(mediaServiceProvider);
    try {
      final path = await mediaService.getTemporaryAudioPath();
      await mediaService.startRecording(path);
      state = state.copyWith(isRecording: true);
    } catch (e) {
      state = state.copyWith(isRecording: false, error: e.toString());
    }
  }

  /// Cancels the current recording and deletes the temporary file
  Future<void> cancelRecording() async {
    final mediaService = ref.read(mediaServiceProvider);
    state = state.copyWith(isRecording: false);
    
    final path = await mediaService.stopRecording();
    if (path != null && path.isNotEmpty) {
      try {
        await File(path).delete();
        debugPrint('✅ Deleted cancelled recording: $path');
      } catch (e) {
        debugPrint('⚠️ Failed to delete cancelled recording: $e');
      }
    }
  }

  Future<void> stopRecordingAndSend() async {
    final mediaService = ref.read(mediaServiceProvider);
    state = state.copyWith(isRecording: false);
    final path = await mediaService.stopRecording();
    
    // Check if recording is valid
    if (path == null || path.isEmpty) {
      debugPrint('⚠️ Recording path is null or empty');
      return;
    }

    final replyToId = state.replyingToMessage?.id;
    state = state.copyWith(isSending: true);
    
    try {
      // Use the new encrypted audio sending method
      final message = await _chatRepository.sendAudioMessage(
        audioFilePath: path,
        roomId: arg.isRoom ? arg.roomId : '',
        receiverId: arg.isRoom ? null : arg.roomId,
      );

      // Update the optimistic message with reply info if needed
      if (replyToId != null) {
        final updatedMessage = message.copyWith(
          replyToMessageId: replyToId,
          replyToMessage: state.replyingToMessage,
        );
        _addMessage(updatedMessage);
        state = state.copyWith(replyingToMessage: null);
      } else {
        _addMessage(message);
      }

      state = state.copyWith(isSending: false);
      
      // Clean up temporary audio file
      try {
        await File(path).delete();
        debugPrint('✅ Deleted temp audio file: $path');
      } catch (e) {
        debugPrint('⚠️ Failed to delete temp audio file: $e');
      }
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
      debugPrint('❌ Failed to send audio message: $e');
      
      // Still try to clean up temp file on error
      try {
        await File(path).delete();
        debugPrint('✅ Deleted temp audio file after error: $path');
      } catch (cleanupError) {
        debugPrint('⚠️ Failed to delete temp file after error: $cleanupError');
      }
    }
  }

  Future<void> sendImageMessage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    state = state.copyWith(isSending: true);
    try {
      final url = await _chatRepository.uploadImage(File(picked.path));
      await sendMessage(url, type: MessageType.image);
      state = state.copyWith(isSending: false);
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> sendDocument(File file) async {
    state = state.copyWith(isSending: true);
    try {
      final url = await _chatRepository.uploadImage(file);
      await sendMessage(url, type: MessageType.file);
      state = state.copyWith(isSending: false);
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
    }
  }

  Future<void> toggleReaction(String messageId, String emoji) async {
    if (messageId.isEmpty || emoji.isEmpty) return;
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final existing = state.messages[index];
    final previousReactions = existing.reactions;
    final updatedReactions = _toggleReactions(
      existing.reactions,
      emoji,
      arg.currentUserId,
    );
    final updated = existing.copyWith(reactions: updatedReactions);
    final messages = [...state.messages];
    messages[index] = updated;
    state = state.copyWith(messages: messages);
    Future.microtask(() => LocalDbService().insertMessages([updated]));
    try {
      await _chatRepository.toggleReaction(messageId, emoji);
    } catch (e) {
      final rollback = existing.copyWith(reactions: previousReactions);
      final rollbackMessages = [...state.messages];
      final rollbackIndex = rollbackMessages.indexWhere(
        (m) => m.id == messageId,
      );
      if (rollbackIndex != -1) {
        rollbackMessages[rollbackIndex] = rollback;
        state = state.copyWith(messages: rollbackMessages, error: e.toString());
        Future(() => LocalDbService().insertMessages([rollback]));
      }
    }
  }

  Future<void> unsendMessage(Message msg) async {
    if (msg.id.isEmpty) return;
    final index = state.messages.indexWhere((m) => m.id == msg.id);
    if (index == -1) return;

    final existing = state.messages[index];
    final updated = existing.copyWith(isUnsent: true, content: '');
    final messages = [...state.messages];
    messages[index] = updated;
    state = state.copyWith(messages: messages);
    Future.microtask(() => LocalDbService().insertMessages([updated]));

    if (index == 0) {
      ref
          .read(roomListViewModelProvider.notifier)
          .updateRoomLastMessage(
            arg.roomId,
            '此訊息已收回',
            lastMessageTime: updated.createdAt,
          );
    }

    try {
      await _chatRepository.unsendMessage(msg.id);
    } catch (e) {
      final rollbackMessages = [...state.messages];
      final rollbackIndex = rollbackMessages.indexWhere((m) => m.id == msg.id);
      if (rollbackIndex != -1) {
        rollbackMessages[rollbackIndex] = existing;
        state = state.copyWith(messages: rollbackMessages, error: e.toString());
        Future(() => LocalDbService().insertMessages([existing]));
      }
    }
  }

  Future<void> deleteMessage(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      await _chatRepository.deleteMessage(messageId);
      _removeMessageFromState(messageId);
      Future.microtask(() => LocalDbService().deleteMessageLocal(messageId));
      Future.microtask(
        () => ref.read(roomListViewModelProvider.notifier).fetchRooms(),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> clearHistory() async {
    try {
      await _chatRepository.clearChatHistory(arg.roomId);
      await LocalDbService().clearRoomMessages(arg.roomId);
      state = state.copyWith(messages: [], hasMore: false, offset: 0);
      ref
          .read(roomListViewModelProvider.notifier)
          .updateRoomLastMessage(arg.roomId, '', lastMessageTime: null);
    } catch (e) {
      state = state.copyWith(error: '清除失敗：${e.toString()}');
    }
  }

  void deleteMessageLocal(Message msg) {
    if (msg.id.isEmpty) return;
    _removeMessageFromState(msg.id);
    Future.microtask(() => LocalDbService().deleteMessageLocal(msg.id));
  }

  void _removeMessageFromState(String messageId) {
    final messages = state.messages.where((m) => m.id != messageId).toList();
    state = state.copyWith(messages: messages);

    String newLastMessage = '';
    DateTime? newLastTime;

    if (messages.isNotEmpty) {
      final latest = messages.first;
      if (latest.isUnsent) {
        newLastMessage = '此訊息已收回';
      } else if (latest.type == MessageType.image) {
        newLastMessage = '[圖片]';
      } else if (latest.type == MessageType.voice) {
        newLastMessage = '[語音訊息]';
      } else if (latest.type == MessageType.file) {
        newLastMessage = '[檔案]';
      } else {
        newLastMessage = latest.content;
      }
      newLastTime = latest.createdAt;
    }

    ref
        .read(roomListViewModelProvider.notifier)
        .updateRoomLastMessage(
          arg.roomId,
          newLastMessage,
          lastMessageTime: newLastTime,
        );
  }

  void setReplyingTo(Message? message) {
    if (message == null) {
      state = state.copyWith(clearReplyingTo: true);
    } else {
      state = state.copyWith(replyingToMessage: message);
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Map<String, List<String>> _toggleReactions(
    Map<String, List<String>>? current,
    String emoji,
    String userId,
  ) {
    final reactions = Map<String, List<String>>.from(current ?? {});
    final users = List<String>.from(reactions[emoji] ?? []);
    if (users.contains(userId)) {
      users.remove(userId);
    } else {
      users.add(userId);
    }
    if (users.isEmpty) {
      reactions.remove(emoji);
    } else {
      reactions[emoji] = users;
    }
    return reactions;
  }

  Map<String, List<String>> _parseReactionsMap(dynamic raw) {
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        ),
      );
    }
    return {};
  }

  void _applyReactionUpdate(
    String messageId,
    Map<String, List<String>> reactions,
  ) {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final existing = state.messages[index];
    final updated = existing.copyWith(reactions: reactions);
    final messages = [...state.messages];
    messages[index] = updated;
    state = state.copyWith(messages: messages);
    Future.microtask(() => LocalDbService().insertMessages([updated]));
  }

  void _applyUnsentUpdate(String messageId) {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final existing = state.messages[index];
    final updated = existing.copyWith(isUnsent: true, content: '');
    final messages = [...state.messages];
    messages[index] = updated;
    state = state.copyWith(messages: messages);
    Future.microtask(() => LocalDbService().insertMessages([updated]));
  }

  Message _attachReplyMessage(Message message) {
    final replyId = message.replyToMessageId;
    if (replyId == null || replyId.isEmpty) {
      return message;
    }
    if (message.replyToMessage != null) {
      return message;
    }
    final found = state.messages
        .where((m) => m.id == replyId)
        .cast<Message?>()
        .firstWhere((m) => m != null, orElse: () => null);
    if (found == null) {
      return message;
    }
    return message.copyWith(replyToMessage: found);
  }

  Future<void> markConversationAsRead() async {
    if (arg.roomId.isEmpty) {
      return;
    }

    _markConversationReadTimer?.cancel();
    _markConversationReadTimer = Timer(
      const Duration(milliseconds: 800),
      () async {
        final now = DateTime.now();
        if (_lastMarkConversationReadTime != null &&
            now.difference(_lastMarkConversationReadTime!).inSeconds < 2) {
          return;
        }
        _lastMarkConversationReadTime = now;

        final payload = {'conversation_id': arg.roomId, 'is_room': arg.isRoom};
        _wsService.send('mark_read', payload);
        try {
          await _network.client.post('/messages/read', data: payload);
          ref
              .read(roomListViewModelProvider.notifier)
              .clearUnreadCount(arg.roomId);
        } catch (e) {
          state = state.copyWith(error: e.toString());
        }
      },
    );
  }

  void markAsRead(String messageId) {
    if (messageId.isEmpty) return;
    if (_alreadyReportedMessageIds.contains(messageId)) {
      return;
    }
    _pendingReadMessageIds.add(messageId);

    _readBatchTimer?.cancel();
    _readBatchTimer = Timer(const Duration(milliseconds: 800), () async {
      if (_pendingReadMessageIds.isEmpty) return;

      final now = DateTime.now();
      if (_lastReadBatchTime != null &&
          now.difference(_lastReadBatchTime!).inSeconds < 2) {
        return;
      }
      _lastReadBatchTime = now;

      final ids = _pendingReadMessageIds.toList();
      _pendingReadMessageIds.clear();
      _alreadyReportedMessageIds.addAll(ids);
      if (_alreadyReportedMessageIds.length > 1000) {
        final toRemove = _alreadyReportedMessageIds.take(200).toList();
        _alreadyReportedMessageIds.removeAll(toRemove);
      }
      try {
        await _chatRepository.markMessagesAsRead(ids);
        _applyReadReceipt(ids, arg.currentUserId);

        for (final id in ids) {
          final msg = state.messages.firstWhere(
            (m) => m.id == id,
            orElse: () => Message(
              id: '',
              content: '',
              senderId: '',
              createdAt: DateTime.now(),
            ),
          );
          if (msg.id.isNotEmpty && msg.senderId != arg.currentUserId) {
            _wsService.send('message_read', {
              'message_id': msg.id,
              'room_id': (arg.isRoom ? arg.roomId : null),
              'sender_id': msg.senderId,
            });
          }
        }
        ref
            .read(roomListViewModelProvider.notifier)
            .clearUnreadCount(arg.roomId);
      } catch (e) {
        _alreadyReportedMessageIds.removeAll(ids);
        state = state.copyWith(error: e.toString());
      }
    });
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

final chatRoomProvider =
    NotifierProvider.family<ChatRoomViewModel, ChatRoomState, ChatRoomParams>(
      ChatRoomViewModel.new,
    );