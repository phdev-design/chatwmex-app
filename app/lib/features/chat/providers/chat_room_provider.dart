import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
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
  bool _isAutoResendInitialized = false;

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
          _initializeAutoResend();
        } else if (event == 'ws_disconnected') {
          _isAutoResendInitialized = false;
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
        } else if (event == 're_encrypt_request') {
          // 🔐 E2EE Auto-Resend: 處理重新加密請求（發送方收到）
          if (payload is Map) {
            _handleReEncryptRequest(Map<String, dynamic>.from(payload));
          }
        } else if (event == 're_encrypt_response') {
          // 🔐 E2EE Auto-Resend: 處理重新加密回應（接收方收到）
          if (payload is Map) {
            _handleReEncryptResponse(Map<String, dynamic>.from(payload));
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
    Future.microtask(() => _initializeAutoResend());

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
      linkPreview: existing.linkPreview,
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
      linkPreview: existing.linkPreview,
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
          linkPreview: m.linkPreview,
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
          linkPreview: m.linkPreview,
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

  Future<String> _encryptGroupMessage(String plaintext, List<String> memberIds) async {
    final ciphertexts = <String, String>{};
    int keysUnavailableCount = 0;
    int encryptionFailureCount = 0;
    
    const batchSize = 10;
    for (int i = 0; i < memberIds.length; i += batchSize) {
      final batchEnd = (i + batchSize < memberIds.length) ? i + batchSize : memberIds.length;
      final batch = memberIds.sublist(i, batchEnd);
      
      final futures = batch.map((memberId) async {
        final publicKey = await _publicKeyCacheService.getPublicKey(memberId);
        if (publicKey != null) {
          try {
            final ciphertext = await _cryptoService.encryptMessage(plaintext, publicKey);
            return MapEntry(memberId, ciphertext);
          } catch (e) {
            debugPrint('[E2EE] Encryption failed for member: roomId=${arg.roomId}, memberCount=${memberIds.length}, error=${e.runtimeType}');
            return MapEntry<String, String>('', '');
          }
        }
        return null;
      }).toList();
      
      final results = await Future.wait(futures);
      
      for (final result in results) {
        if (result == null) {
          keysUnavailableCount++;
        } else if (result.key.isEmpty) {
          encryptionFailureCount++;
        } else {
          ciphertexts[result.key] = result.value;
        }
      }
    }
    
    if (ciphertexts.isEmpty) {
      if (keysUnavailableCount == memberIds.length) {
        debugPrint('[E2EE] Complete key unavailability: roomId=${arg.roomId}, memberCount=${memberIds.length}');
        throw Exception('無法取得任何成員的公鑰');
      } else if (encryptionFailureCount == memberIds.length) {
        debugPrint('[E2EE] Complete encryption failure: roomId=${arg.roomId}, memberCount=${memberIds.length}');
        throw Exception('所有成員的加密操作均失敗');
      } else {
        debugPrint('[E2EE] Complete encryption failure (mixed): roomId=${arg.roomId}, memberCount=${memberIds.length}, keysUnavailable=$keysUnavailableCount, encryptionFailed=$encryptionFailureCount');
        throw Exception('加密失敗，無法發送訊息');
      }
    }
    
    if (keysUnavailableCount > 0 || encryptionFailureCount > 0) {
      debugPrint('[E2EE] Partial encryption success: roomId=${arg.roomId}, successful=${ciphertexts.length}, keysUnavailable=$keysUnavailableCount, encryptionFailed=$encryptionFailureCount');
    }
    
    final fanoutPayload = {
      'is_fanout': true,
      'ciphertexts': ciphertexts,
    };
    
    return jsonEncode(fanoutPayload);
  }

  Future<String> _decryptGroupMessage(
    String content,
    String senderId, {
    String? messageId,
  }) async {
    try {
      final payload = jsonDecode(content);
      
      if (payload is! Map || payload['is_fanout'] != true) {
        return content;
      }
      
      final ciphertexts = payload['ciphertexts'] as Map<String, dynamic>?;
      if (ciphertexts == null) {
        debugPrint('[E2EE] Decryption failed: Invalid fan-out payload structure');
        if (messageId != null) {
          throw DecryptionFailureException(
            messageId: messageId,
            senderId: senderId,
            originalCiphertext: content,
            reason: 'Invalid fan-out payload structure',
          );
        }
        return '🔒 訊息格式錯誤';
      }
      
      final myCiphertext = ciphertexts[arg.currentUserId];
      if (myCiphertext == null) {
        debugPrint('[E2EE] Decryption failed: Missing ciphertext for current user');
        if (messageId != null) {
          throw DecryptionFailureException(
            messageId: messageId,
            senderId: senderId,
            originalCiphertext: content,
            reason: 'Missing ciphertext for current user',
          );
        }
        return '🔒 此訊息不包含您的加密內容';
      }
      
      final senderPublicKey = await _publicKeyCacheService.getPublicKey(senderId);
      if (senderPublicKey == null) {
        debugPrint('[E2EE] Decryption failed: Sender public key unavailable');
        if (messageId != null) {
          throw DecryptionFailureException(
            messageId: messageId,
            senderId: senderId,
            originalCiphertext: content,
            reason: 'Sender public key unavailable',
          );
        }
        return '🔒 此訊息無法解密（金鑰已更新）';
      }
      
      try {
        final plaintext = await _cryptoService.decryptMessage(
          myCiphertext.toString(),
          senderPublicKey,
          messageId: messageId,
          senderId: senderId,
        );
        return plaintext;
      } on DecryptionFailureException {
        rethrow;
      } catch (decryptError) {
        if (messageId != null) {
          throw DecryptionFailureException(
            messageId: messageId,
            senderId: senderId,
            originalCiphertext: content,
            reason: 'Decryption operation failed: ${decryptError.runtimeType}',
          );
        }
        return '🔒 此訊息無法解密（金鑰已更新）';
      }
    } on FormatException catch (e) {
      return content;
    } on DecryptionFailureException {
      rethrow;
    } catch (e) {
      if (messageId != null) {
        throw DecryptionFailureException(
          messageId: messageId,
          senderId: senderId,
          originalCiphertext: content,
          reason: 'Unexpected error: ${e.runtimeType}',
        );
      }
      return '🔒 此訊息無法解密（金鑰已更新）';
    }
  }

  Future<String?> _getPublicKey(String userId) async {
    if (arg.isRoom) return null;
    return await _publicKeyCacheService.getPublicKey(userId);
  }

  /// 🔐 E2EE Auto-Resend: 處理解密失敗，並實作重試次數上限以防止死迴圈
  Future<void> _handleDecryptionFailure(
    Message message,
    DecryptionFailureException exception,
  ) async {
    if (message.id.isEmpty || exception.senderId.isEmpty) {
      return;
    }

    try {
      // 1. 取得當前重試次數
      final currentRetryCount = await LocalDbService().getDecryptRetryCount(message.id);
      
      // 2. 如果重試超過 2 次，直接標記為解密失敗，不再觸發 re_encrypt_request
      if (currentRetryCount >= 2) {
        debugPrint('[E2EE Auto-Resend] Retry limit reached for message: ${message.id}. Marking as failed.');
        await LocalDbService().updateMessageContentAndStatus(
          messageId: message.id,
          newContent: '🔒 解密失敗（已超過重試次數）',
          newStatus: MessageStatus.failed,
        );
        
        // 更新 UI 狀態為失敗
        final index = state.messages.indexWhere((m) => m.id == message.id);
        if (index != -1) {
          final updated = message.copyWith(
             content: '🔒 解密失敗（已超過重試次數）',
             status: MessageStatus.failed
          );
          final messages = [...state.messages];
          messages[index] = updated;
          state = state.copyWith(messages: messages);
        }
        return; // 終止流程
      }

      // 3. 更新重試次數 + 1
      await LocalDbService().updateDecryptRetryCount(message.id, currentRetryCount + 1);

      // 4. 更新訊息狀態為 decryptingRetry
      await LocalDbService().updateMessageContentAndStatus(
        messageId: message.id,
        newContent: message.content, // 保留原密文
        newStatus: MessageStatus.decryptingRetry,
      );
      
      // 更新 UI 狀態
      final index = state.messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        final updated = message.copyWith(status: MessageStatus.decryptingRetry);
        final messages = [...state.messages];
        messages[index] = updated;
        state = state.copyWith(messages: messages);
      }
      
      if (!_wsService.isConnected) {
        debugPrint('[E2EE Auto-Resend] WebSocket not connected, will retry when reconnected');
        return;
      }
      
      // 5. 發送 re_encrypt_request
      debugPrint('[E2EE Auto-Resend] Sending re_encrypt_request for message: ${message.id}');
      try {
        await _wsService.send('re_encrypt_request', {
          'message_id': message.id,
          'sender_id': exception.senderId,
          'receiver_id': arg.currentUserId,
          'room_id': arg.isRoom ? arg.roomId : null,
        });
      } catch (e) {
        debugPrint('[E2EE Auto-Resend] Failed to send re_encrypt_request: $e');
      }
    } catch (e) {
      debugPrint('[E2EE Auto-Resend] Unexpected error in _handleDecryptionFailure: $e');
    }
  }

  Future<void> _handleReEncryptRequest(Map<String, dynamic> payload) async {
    final messageId = payload['message_id'] as String?;
    final receiverId = payload['receiver_id'] as String?;
    final roomId = payload['room_id'] as String?;
    
    if (messageId == null || messageId.isEmpty || receiverId == null || receiverId.isEmpty) {
      return;
    }
    
    try {
      final originalMessage = await LocalDbService().getMessageById(messageId);
      if (originalMessage == null) return;
      if (originalMessage.senderId != arg.currentUserId) return;
      if (originalMessage.content.isEmpty) return;
      
      final receiverPublicKey = await _publicKeyCacheService.getPublicKey(receiverId);
      if (receiverPublicKey == null) return;
      
      String reEncryptedContent;
      try {
        if (arg.isRoom) {
          final ciphertext = await _cryptoService.encryptMessage(
            originalMessage.content,
            receiverPublicKey,
          );
          final fanoutPayload = {
            'is_fanout': true,
            'ciphertexts': {receiverId: ciphertext},
          };
          reEncryptedContent = jsonEncode(fanoutPayload);
        } else {
          reEncryptedContent = await _cryptoService.encryptMessage(
            originalMessage.content,
            receiverPublicKey,
          );
        }
      } catch (e) {
        debugPrint('[E2EE Auto-Resend] Re-encryption failed: $e');
        return;
      }
      
      if (!_wsService.isConnected) return;
      
      debugPrint('[E2EE Auto-Resend] Sending re_encrypt_response for message: $messageId to receiver: $receiverId');
      try {
        await _wsService.send('re_encrypt_response', {
          'message_id': messageId,
          'receiver_id': receiverId,
          'room_id': roomId,
          're_encrypted_content': reEncryptedContent,
        });
      } catch (e) {
        debugPrint('[E2EE Auto-Resend] Failed to send re_encrypt_response: $e');
      }
    } catch (e) {
      debugPrint('[E2EE Auto-Resend] Unexpected error in _handleReEncryptRequest: $e');
    }
  }

  Future<void> _handleReEncryptResponse(Map<String, dynamic> payload) async {
    final messageId = payload['message_id'] as String?;
    final content = (payload['re_encrypted_content'] ?? payload['content']) as String?;
    final receiverId = payload['receiver_id'] as String?;
    
    if (messageId == null || messageId.isEmpty || content == null || content.isEmpty) {
      return;
    }
    
    if (receiverId != null && receiverId != arg.currentUserId) {
      return;
    }
    
    try {
      final originalMessage = await LocalDbService().getMessageById(messageId);
      if (originalMessage == null) return;
      
      if (originalMessage.status != MessageStatus.decryptingRetry) {
        return;
      }
      
      String decryptedContent;
      try {
        if (arg.isRoom) {
          decryptedContent = await _decryptGroupMessage(content, originalMessage.senderId);
          if (decryptedContent.startsWith('🔒')) {
            throw Exception('Decryption returned error message');
          }
        } else {
          final senderPublicKey = await _publicKeyCacheService.getPublicKey(originalMessage.senderId);
          if (senderPublicKey == null) {
            throw Exception('Sender public key unavailable');
          }
          decryptedContent = await _cryptoService.decryptMessage(content, senderPublicKey);
          
          if (decryptedContent == content) {
            throw Exception('Decryption failed: returned original ciphertext');
          }
        }
      } catch (e) {
        debugPrint('[E2EE Auto-Resend] Re-decryption failed again: $e');
        
        // 🔐 關鍵修復：收到重新加密的內容後依然解密失敗，不再維持 decryptingRetry 狀態
        // 強制轉為 failed 避免死迴圈
        await LocalDbService().updateMessageContentAndStatus(
          messageId: messageId,
          newContent: '🔒 重新解密失敗',
          newStatus: MessageStatus.failed,
        );
        
        final index = state.messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          final updated = originalMessage.copyWith(
            content: '🔒 重新解密失敗',
            status: MessageStatus.failed,
          );
          final messages = [...state.messages];
          messages[index] = updated;
          state = state.copyWith(messages: messages);
        }
        return;
      }
      
      // 解密成功
      await LocalDbService().updateMessageContentAndStatus(
        messageId: messageId,
        newContent: decryptedContent,
        newStatus: MessageStatus.delivered,
      );
      
      final index = state.messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final updated = originalMessage.copyWith(
          content: decryptedContent,
          status: MessageStatus.delivered,
        );
        final messages = [...state.messages];
        messages[index] = updated;
        state = state.copyWith(messages: messages);
      }
      
      debugPrint('[E2EE Auto-Resend] Successfully re-decrypted message: $messageId');
    } catch (e) {
      debugPrint('[E2EE Auto-Resend] Unexpected error in _handleReEncryptResponse: $e');
    }
  }

  /// 🔐 E2EE Auto-Resend: 取得所有狀態為 decryptingRetry 的訊息
  /// 用於 app 重啟或 WebSocket 重連時，自動重試解密失敗的訊息
  Future<List<Message>> _getDecryptingRetryMessages() async {
    return await LocalDbService().getDecryptingRetryMessages();
  }

  /// 🔐 E2EE Auto-Resend: 初始化自動重發邏輯
  /// 在 app 重啟或 WebSocket 重連時呼叫，檢查 LocalDB 中的 decryptingRetry 訊息
  /// 並根據記憶體中的當前狀態決定是否發送 re_encrypt_request
  Future<void> _initializeAutoResend() async {
    // 檢查是否已初始化，防止重複執行
    if (_isAutoResendInitialized) {
      debugPrint('[E2EE Auto-Resend] Already initialized, skipping');
      return;
    }
  _isAutoResendInitialized = true;  // 立即設，防止 race condition

    try {
      // 從 LocalDB 查詢所有 status = 'decryptingRetry' 的訊息
      final decryptingRetryMessages = await _getDecryptingRetryMessages();
      
      if (decryptingRetryMessages.isEmpty) {
        debugPrint('[E2EE Auto-Resend] No decryptingRetry messages found in LocalDB');
        _isAutoResendInitialized = true;
        return;
      }

      debugPrint('[E2EE Auto-Resend] Found ${decryptingRetryMessages.length} decryptingRetry messages in LocalDB');

      // 對每條訊息，檢查在記憶體中的當前狀態
      for (final dbMessage in decryptingRetryMessages) {
        final messageId = dbMessage.id;
        
        // 在 state.messages 中查找該訊息
        final memoryMessage = state.messages.firstWhere(
          (m) => m.id == messageId || m.clientMsgId == messageId,
          orElse: () => Message(
            id: '',
            content: '',
            senderId: '',
            createdAt: DateTime.now(),
          ),
        );

        // 如果在記憶體中找不到訊息，使用 LocalDB 中的狀態
        final currentStatus = memoryMessage.id.isNotEmpty 
            ? memoryMessage.status 
            : dbMessage.status;

        // 如果記憶體中的狀態已經是 read/delivered/sent/failed，跳過該訊息
        if (currentStatus == MessageStatus.read ||
            currentStatus == MessageStatus.delivered ||
            currentStatus == MessageStatus.sent ||
            currentStatus == MessageStatus.failed) {
          debugPrint('[E2EE Auto-Resend] Skipping message $messageId: status is already $currentStatus');
          continue;
        }

        // 如果記憶體中的狀態仍然是 decryptingRetry，檢查重試次數
        if (currentStatus == MessageStatus.decryptingRetry) {
          final retryCount = await LocalDbService().getDecryptRetryCount(messageId);
          
          if (retryCount >= 2) {
            debugPrint('[E2EE Auto-Resend] Skipping message $messageId: retry limit reached (retryCount=$retryCount)');
            continue;
          }

          // 檢查 WebSocket 是否已連線
          if (!_wsService.isConnected) {
            debugPrint('[E2EE Auto-Resend] WebSocket not connected, will retry when reconnected');
            continue;
          }

          // 發送 re_encrypt_request
          debugPrint('[E2EE Auto-Resend] Sending re_encrypt_request for message: $messageId (retryCount=$retryCount)');
          try {
            await _wsService.send('re_encrypt_request', {
              'message_id': messageId,
              'sender_id': dbMessage.senderId,
              'receiver_id': arg.currentUserId,
              'room_id': arg.isRoom ? arg.roomId : null,
            });
          } catch (e) {
            debugPrint('[E2EE Auto-Resend] Failed to send re_encrypt_request: $e');
          }
        }
      }

      // 設定初始化完成標記
      _isAutoResendInitialized = true;
      debugPrint('[E2EE Auto-Resend] Initialization completed');
    } catch (e) {
      debugPrint('[E2EE Auto-Resend] Unexpected error in _initializeAutoResend: $e');
      // 即使發生錯誤，也設定為已初始化，避免重複嘗試
      _isAutoResendInitialized = true;
    }
  }

  Future<Message> _tryDecryptMessage(Message m) async {
    if (m.isUnsent || m.content.isEmpty) return m;

    final isE2EEEnabled =
        ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;
    if (!isE2EEEnabled) return m;

    if (arg.isRoom) {
      try {
        final decrypted = await _decryptGroupMessage(m.content, m.senderId, messageId: m.id);
        if (decrypted != m.content) {
          // Update LocalDB status to sync with memory state after successful decryption
          await LocalDbService().updateMessageStatus(m.clientMsgId ?? m.id, MessageStatus.delivered);
          return m.copyWith(content: decrypted);
        }
        return m;
      } on DecryptionFailureException catch (e) {
        await _handleDecryptionFailure(m, e);
        return m; 
      }
    } else {
      final opponentId = (m.senderId == arg.currentUserId)
          ? m.receiverId
          : m.senderId;
      if (opponentId == null) return m;

      final pubKey = await _getPublicKey(opponentId);
      if (pubKey == null) return m;

      try {
        final decrypted = await _cryptoService.decryptMessage(
          m.content,
          pubKey,
          messageId: m.id,
          senderId: m.senderId,
        );

        if (decrypted != m.content) {
          // Update LocalDB status to sync with memory state after successful decryption
          await LocalDbService().updateMessageStatus(m.clientMsgId ?? m.id, MessageStatus.delivered);
          return m.copyWith(content: decrypted);
        }

        final looksLikeCiphertext = _looksLikeE2EECiphertext(m.content);
        if (looksLikeCiphertext) {
          return m.copyWith(content: '🔒 此訊息無法解密（金鑰已更新）');
        }
        return m;
      } on DecryptionFailureException catch (e) {
        await _handleDecryptionFailure(m, e);
        return m; 
      }
    }
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
    } catch (e) {
      debugPrint('Error caught: $e');
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

      if (isE2EEEnabled) {
        if (arg.isRoom) {
          try {
            final members = await _chatRepository.getRoomMemberProfiles(arg.roomId);
            final memberIds = members.map((m) => m.id).toList();
            payloadContent = await _encryptGroupMessage(message.content, memberIds);
          } catch (e) {
            continue;
          }
        } else {
          final pubKey = await _getPublicKey(arg.roomId);
          if (pubKey != null) {
            try {
              payloadContent = await _cryptoService.encryptMessage(
                message.content,
                pubKey,
              );
            } catch (e) {
              continue;
            }
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
    dynamic linkPreview,
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
      linkPreview: linkPreview,
    );

    await LocalDbService().insertMessages([tempMessage]);
    _addMessage(tempMessage);
    state = state.copyWith(isSending: true, clearReplyingTo: true);

    String payloadContent = content;
    final isE2EEEnabled =
        ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;

    if (isE2EEEnabled) {
      if (arg.isRoom) {
        try {
          final members = await _chatRepository.getRoomMemberProfiles(arg.roomId);
          final memberIds = members.map((m) => m.id).toList();
          payloadContent = await _encryptGroupMessage(content, memberIds);
        } catch (e) {
          state = state.copyWith(
            isSending: false,
            error: '加密失敗，無法發送訊息',
          );
          return;
        }
      } else {
        final pubKey = await _getPublicKey(arg.roomId);
        if (pubKey != null) {
          try {
            payloadContent = await _cryptoService.encryptMessage(content, pubKey);
          } catch (e) {
            // error
          }
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
      if (linkPreview != null) 'link_preview': {
        'url': linkPreview.url,
        'title': linkPreview.title,
        'description': linkPreview.description,
        if (linkPreview.imageUrl != null) 'image_url': linkPreview.imageUrl,
      },
    };

    try {
      await _wsService.send('chat_message', payload);
      _updateMessageStatus(clientMsgId, MessageStatus.sent);
      final sentMsg = tempMessage.copyWith(status: MessageStatus.sent);
      Future.microtask(() => LocalDbService().insertMessages([sentMsg]));
      state = state.copyWith(isSending: false);
    } catch (e) {
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

    if (isE2EEEnabled) {
      if (arg.isRoom) {
        try {
          final members = await _chatRepository.getRoomMemberProfiles(arg.roomId);
          final memberIds = members.map((m) => m.id).toList();
          payloadContent = await _encryptGroupMessage(message.content, memberIds);
        } catch (e) {
          _updateMessageStatus(clientMsgId, MessageStatus.failed);
          state = state.copyWith(error: '加密失敗');
          return;
        }
      } else {
        final pubKey = await _getPublicKey(arg.roomId);
        if (pubKey != null) {
          try {
            payloadContent = await _cryptoService.encryptMessage(
              message.content,
              pubKey,
            );
          } catch (e) {
            // Error handling
          }
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

  Future<void> cancelRecording() async {
    final mediaService = ref.read(mediaServiceProvider);
    state = state.copyWith(isRecording: false);
    
    final path = await mediaService.stopRecording();
    if (path != null && path.isNotEmpty) {
      try {
        await File(path).delete();
      } catch (e) {
        // ...
      }
    }
  }

  Future<void> stopRecordingAndSend() async {
    final mediaService = ref.read(mediaServiceProvider);
    state = state.copyWith(isRecording: false);
    final path = await mediaService.stopRecording();
    
    if (path == null || path.isEmpty) {
      return;
    }

    final replyToId = state.replyingToMessage?.id;
    state = state.copyWith(isSending: true);
    
    try {
      final message = await _chatRepository.sendAudioMessage(
        audioFilePath: path,
        roomId: arg.isRoom ? arg.roomId : '',
        receiverId: arg.isRoom ? null : arg.roomId,
      );

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
      
      try {
        await File(path).delete();
      } catch (e) {
        // ...
      }
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
      try {
        await File(path).delete();
      } catch (cleanupError) {
        // ...
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