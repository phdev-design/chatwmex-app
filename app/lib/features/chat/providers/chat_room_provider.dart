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
import 'package:app/features/chat/providers/e2ee_provider.dart'; // 👉 新增

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
    this.offset = 50,
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
  late final PublicKeyCacheService _publicKeyCacheService; // 👉 替換舊 cache 變數
  Timer? _typingTimer;
  bool _typingSent = false;

  // 👉 針對單人對話的批次已讀 (_markConversationAsRead) 狀態變數
  Timer? _markConversationReadTimer;
  DateTime? _lastMarkConversationReadTime;

  // 👉 針對群組多筆訊息的批次已讀 (_markAsRead) 狀態變數
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
    _publicKeyCacheService = ref.watch(publicKeyCacheServiceProvider); // 👉 初始化
    var initialRoomAvatarUrl = '';
    if (!arg.isRoom) {
      final rooms = ref.read(roomListViewModelProvider).rooms;
      for (final room in rooms) {
        if (room.id == arg.roomId && room.avatarUrl != null) {
          initialRoomAvatarUrl = room.avatarUrl!;
          break;
        }
      }
      // debugPrint(
      //   'chat_room init dm room_id=${arg.roomId} initial_room_avatar_url=$initialRoomAvatarUrl rooms_count=${rooms.length}',
      // );
    }

    // Connect WebSocket
    _wsService.connect();

    // Listen to WS events
    final subscription = _wsService.events.listen((data) {
      if (data is Map) {
        final event = data['event'];
        final payload = data['data'];

        if (event == 'chat_message') {
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
                ); // Store encrypted locally
                if (message.senderId != arg.currentUserId) {
                  if (arg.isRoom) {
                    markAsRead(message.id);
                  } else {
                    markConversationAsRead();
                  }
                }
              }
            });
          } catch (e) {
            print('Error parsing message: $e');
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
        }
      }
    });

    ref.onDispose(() {
      subscription.cancel();
      _typingTimer?.cancel();
      _markConversationReadTimer?.cancel(); // 👉 清理新增的計時器
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
    state = state.copyWith(messages: [hydrated, ...state.messages]);
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
    debugPrint(
      'chat_room user_profile_updated dm=${!arg.isRoom} room_id=${arg.roomId} event_user_id=$userId room_avatar_url=$roomAvatarUrl',
    );
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

  // 統一使用 _publicKeyCacheService 下的快取與 API 機制
  Future<String?> _getPublicKey(String userId) async {
    if (arg.isRoom) return null;
    return await _publicKeyCacheService.getPublicKey(userId);
  }

  Future<Message> _tryDecryptMessage(Message m) async {
    if (arg.isRoom) return m;
    if (m.isUnsent || m.content.isEmpty) return m;

    // 👉 判斷 E2EE 開關，若為 false 直接跳過解密，以明文顯示
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

    // 解密成功：回傳解密後的內容
    if (decrypted != m.content) {
      return m.copyWith(content: decrypted);
    }

    // 解密後內容與密文相同，代表：
    // A) 原本就是舊版明文（非 base64），直接顯示即可
    // B) 解密失敗（金鑰不匹配），顯示 placeholder
    // 判斷依據：純文字通常不會以 base64 字元集組成且長度是4的倍數
    final looksLikeCiphertext = _looksLikeE2EECiphertext(m.content);
    if (looksLikeCiphertext) {
      return m.copyWith(content: '🔒 此訊息無法解密（金鑰已更新）');
    }
    return m; // 原本就是明文，直接顯示
  }

  // 判斷字串是否看起來像我們的 E2EE 密文格式（base64，且長度 > 28bytes 對應的 base64 長度）
  bool _looksLikeE2EECiphertext(String content) {
    if (content.length < 40)
      return false; // < 28 bytes base64 encoded 約 40 chars
    final base64Regex = RegExp(r'^[A-Za-z0-9+/]+=*$');
    return base64Regex.hasMatch(content.trim());
  }

  Future<List<Message>> _decryptMessages(List<Message> messages) async {
    final futures = messages.map((m) => _tryDecryptMessage(m));
    return Future.wait(futures);
  }

  // --- API Logic ---

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
    } catch (_) {}
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

  Future<void> sendMessage(
    String content, {
    MessageType type = MessageType.text,
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
      status: MessageStatus.sending,
      readBy: [arg.currentUserId],
    );
    _addMessage(tempMessage);

    String payloadContent = content;
    final isE2EEEnabled =
        ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;

    // 👉 判斷 E2EE 開關，若為 false 則直接傳送明文
    if (!arg.isRoom && isE2EEEnabled) {
      final pubKey = await _getPublicKey(arg.roomId);
      if (pubKey != null) {
        try {
          payloadContent = await _cryptoService.encryptMessage(content, pubKey);
        } catch (e) {
          print('Failed to encrypt message: $e');
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
    };

    try {
      await _wsService.send('chat_message', payload);
      _updateMessageStatus(clientMsgId, MessageStatus.sent);
      Future(() => LocalDbService().insertMessages([tempMessage]));
      state = state.copyWith(clearReplyingTo: true);
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

    String payloadContent = message.content;
    final isE2EEEnabled =
        ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;

    // 👉 判斷 E2EE 開關，若為 false 則直接傳送明文
    if (!arg.isRoom && isE2EEEnabled) {
      final pubKey = await _getPublicKey(arg.roomId);
      if (pubKey != null) {
        try {
          payloadContent = await _cryptoService.encryptMessage(
            message.content,
            pubKey,
          );
        } catch (e) {
          print('Failed to encrypt retry: $e');
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
    };
    try {
      await _wsService.send('chat_message', payload);
      _updateMessageStatus(clientMsgId, MessageStatus.sent);
      Future(() => LocalDbService().insertMessages([message]));
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

  Future<void> stopRecordingAndSend() async {
    final mediaService = ref.read(mediaServiceProvider);
    state = state.copyWith(isRecording: false);
    final path = await mediaService.stopRecording();
    if (path == null || path.isEmpty) return;

    final clientMsgId = const Uuid().v4();
    final replyToId = state.replyingToMessage?.id;
    state = state.copyWith(isSending: true);
    try {
      final url = await _chatRepository.uploadMedia(File(path), 'audio');
      final tempMessage = Message(
        id: clientMsgId,
        clientMsgId: clientMsgId,
        content: url,
        senderId: arg.currentUserId,
        receiverId: arg.isRoom ? null : arg.roomId,
        roomId: arg.isRoom ? arg.roomId : null,
        replyToMessageId: replyToId,
        replyToMessage: state.replyingToMessage,
        reactions: null,
        isUnsent: false,
        type: MessageType.voice,
        createdAt: DateTime.now(),
        isRead: true,
        status: MessageStatus.sending,
        readBy: [arg.currentUserId],
      );
      _addMessage(tempMessage);

      String payloadContent = url;
      final isE2EEEnabled =
          ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;

      if (!arg.isRoom && isE2EEEnabled) {
        final pubKey = await _getPublicKey(arg.roomId);
        if (pubKey != null) {
          try {
            payloadContent = await _cryptoService.encryptMessage(url, pubKey);
          } catch (e) {}
        }
      }

      final payload = {
        'receiver_id': arg.isRoom ? null : arg.roomId,
        'room_id': arg.isRoom ? arg.roomId : null,
        'reply_to_message_id': replyToId,
        'content': payloadContent,
        'type': 'audio',
        'client_msg_id': clientMsgId,
      };

      await _wsService.send('chat_message', payload);
      _updateMessageStatus(clientMsgId, MessageStatus.sent);
      Future(() => LocalDbService().insertMessages([tempMessage]));
      state = state.copyWith(isSending: false, replyingToMessage: null);
    } catch (e) {
      _updateMessageStatus(clientMsgId, MessageStatus.failed);
      state = state.copyWith(isSending: false, error: e.toString());
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
    Future(() => LocalDbService().insertMessages([updated]));
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
    Future(() => LocalDbService().insertMessages([updated]));

    // 👇 新增：如果收回的是最新一則訊息（index == 0），同步更新 RoomList
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
      Future(() => LocalDbService().deleteMessageLocal(messageId));
      Future(() => ref.read(roomListViewModelProvider.notifier).fetchRooms());
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void deleteMessageLocal(Message msg) {
    if (msg.id.isEmpty) return;
    _removeMessageFromState(msg.id);
    Future(() => LocalDbService().deleteMessageLocal(msg.id));
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
    Future(() => LocalDbService().insertMessages([updated]));
  }

  void _applyUnsentUpdate(String messageId) {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final existing = state.messages[index];
    final updated = existing.copyWith(isUnsent: true, content: '');
    final messages = [...state.messages];
    messages[index] = updated;
    state = state.copyWith(messages: messages);
    Future(() => LocalDbService().insertMessages([updated]));
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
        // 2 秒冷卻時間：如果短時間內針對同一個對話已經送過，跳過不送
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

      // 2 秒冷卻時間：如果短時間內剛剛送過一個 batch，且新的 batch 未滿特定數量，則考慮延遲或丟棄
      // 這裡採用如果不到 2 秒則直接取消執行這回，等待下一次 trigger
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

// Provider Definition
final chatRoomProvider =
    NotifierProvider.family<ChatRoomViewModel, ChatRoomState, ChatRoomParams>(
      ChatRoomViewModel.new,
    );
