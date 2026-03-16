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
  /// 群組房間的總成員數（含自己），用於判斷是否全員已讀
  final int roomMemberCount;

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
    this.roomMemberCount = 0,
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
    int? roomMemberCount,
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
      roomMemberCount: roomMemberCount ?? this.roomMemberCount,
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

  // 🔐 E2EE Exponential Backoff: 重試排程器
  Timer? _retrySchedulerTimer;
  // 追蹤每個訊息的下次重試時間
  final Map<String, DateTime> _nextRetryTime = {};
  // 最大退避時間（60 秒）
  static const int _maxBackoffSeconds = 60;

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
        
        // 🔍 Log event routing for debugging
        debugPrint('📨 [ChatRoom] Routing WebSocket event: $event');

        if (event == 'ws_reconnected') {
          resendPendingMessages();
          _initializeAutoResend();
        } else if (event == 'ws_disconnected') {
          _isAutoResendInitialized = false;
        } else if (event == 'chat_message') {
          try {
            // 🔍 DEBUG: 檢查接收到的 sender_id 和 room_id
            debugPrint('[DEBUG] received chat_message: sender_id=${payload['sender_id']}, room_id=${payload['room_id']}, type=${payload['type']}');
            
            final rawMessage = Message.fromJson(payload);
            
            // 🔐 修復：群組中發送方自己的訊息已在 sendMessage() 中以明文加入 state，
            // 後端回傳的 WebSocket 訊息 content 為空（fanout 模式），不應覆蓋本地明文。
            // 只更新 message ID（從 clientMsgId 換成 server ID），不覆蓋 content。
            if (arg.isRoom && rawMessage.senderId == arg.currentUserId) {
              // 發送方自己的群組訊息：只需要更新 server-assigned ID
              if (rawMessage.clientMsgId != null && rawMessage.clientMsgId!.isNotEmpty) {
                final existingIndex = state.messages.indexWhere((m) =>
                    m.clientMsgId == rawMessage.clientMsgId || m.id == rawMessage.clientMsgId);
                if (existingIndex != -1) {
                  // 已存在本地明文版本，跳過覆蓋
                  debugPrint('[E2EE] ⏭️ 跳過自己的群組訊息回傳覆蓋: ${rawMessage.clientMsgId}');
                  return;
                }
              }
            }
            
            // 🚀 先檢查訊息是否屬於此聊天室，避免不相關的 ChatRoomViewModel 浪費解密資源
            final belongsToThisRoom = (arg.isRoom && rawMessage.roomId == arg.roomId) ||
                (!arg.isRoom &&
                    (rawMessage.senderId == arg.roomId ||
                        rawMessage.receiverId == arg.roomId));
            if (!belongsToThisRoom) return;
            
            _tryDecryptMessage(rawMessage).then((message) async {
                _addMessage(message);
                
                // 🔐 修復：儲存解密後的訊息（明文），而不是原始密文
                // 這確保 re-encrypt flow 可以讀取明文進行重新加密
                await LocalDbService().insertMessages([message]);
                
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
          debugPrint('🔄 [ChatRoom] Routing to _handleReEncryptRequest');
          if (payload is Map) {
            _handleReEncryptRequest(Map<String, dynamic>.from(payload));
          }
        } else if (event == 're_encrypt_response') {
          // 🔐 E2EE Auto-Resend: 處理重新加密回應（接收方收到）
          debugPrint('🔄 [ChatRoom] Routing to _handleReEncryptResponse');
          if (payload is Map) {
            _handleReEncryptResponse(Map<String, dynamic>.from(payload));
          } else {
            debugPrint('❌ [ChatRoom] re_encrypt_response payload is not a Map: ${payload.runtimeType}');
          }
        }
      }
    });

    ref.onDispose(() {
      subscription.cancel();
      _typingTimer?.cancel();
      _markConversationReadTimer?.cancel();
      _readBatchTimer?.cancel();
      _retrySchedulerTimer?.cancel();
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
    // 🔐 Bug #2 防呆：過濾掉 roomId，避免將 roomId 當作 userId 查詢公鑰導致 404
    final filteredMemberIds = memberIds.where((id) => id != arg.roomId).toList();
    if (filteredMemberIds.length != memberIds.length) {
      debugPrint('[E2EE] ⚠️ Filtered out roomId from member list: ${arg.roomId}');
    }
    
    final ciphertexts = <String, String>{};
    int keysUnavailableCount = 0;
    int encryptionFailureCount = 0;
    
    const batchSize = 10;
    for (int i = 0; i < filteredMemberIds.length; i += batchSize) {
      final batchEnd = (i + batchSize < filteredMemberIds.length) ? i + batchSize : filteredMemberIds.length;
      final batch = filteredMemberIds.sublist(i, batchEnd);
      
      final futures = batch.map((memberId) async {
        final publicKey = await _publicKeyCacheService.getPublicKey(memberId);
        if (publicKey != null) {
          try {
            final ciphertext = await _cryptoService.encryptMessage(plaintext, publicKey);
            return MapEntry(memberId, ciphertext);
          } catch (e) {
            debugPrint('[E2EE] Encryption failed for member: roomId=${arg.roomId}, memberCount=${filteredMemberIds.length}, error=${e.runtimeType}');
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
      if (keysUnavailableCount == filteredMemberIds.length) {
        debugPrint('[E2EE] Complete key unavailability: roomId=${arg.roomId}, memberCount=${filteredMemberIds.length}');
        throw Exception('無法取得任何成員的公鑰');
      } else if (encryptionFailureCount == filteredMemberIds.length) {
        debugPrint('[E2EE] Complete encryption failure: roomId=${arg.roomId}, memberCount=${filteredMemberIds.length}');
        throw Exception('所有成員的加密操作均失敗');
      } else {
        debugPrint('[E2EE] Complete encryption failure (mixed): roomId=${arg.roomId}, memberCount=${filteredMemberIds.length}, keysUnavailable=$keysUnavailableCount, encryptionFailed=$encryptionFailureCount');
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

  /// 🔐 E2EE Group Messages: 新版本 - 回傳 Map 而非 JSON 字串
  /// 用於新的 encrypted_contents_fanout 欄位
  Future<Map<String, String>> _encryptGroupMessageToMap(String plaintext, List<String> memberIds) async {
    // 🔐 Bug #2 防呆：過濾掉 roomId，避免將 roomId 當作 userId 查詢公鑰導致 404
    final filteredMemberIds = memberIds.where((id) => id != arg.roomId).toList();
    if (filteredMemberIds.length != memberIds.length) {
      debugPrint('[E2EE] ⚠️ Filtered out roomId from member list: ${arg.roomId}');
    }
    
    final ciphertexts = <String, String>{};
    int keysUnavailableCount = 0;
    int encryptionFailureCount = 0;
    
    const batchSize = 10;
    for (int i = 0; i < filteredMemberIds.length; i += batchSize) {
      final batchEnd = (i + batchSize < filteredMemberIds.length) ? i + batchSize : filteredMemberIds.length;
      final batch = filteredMemberIds.sublist(i, batchEnd);
      
      final futures = batch.map((memberId) async {
        final publicKey = await _publicKeyCacheService.getPublicKey(memberId);
        if (publicKey != null) {
          try {
            final ciphertext = await _cryptoService.encryptMessage(plaintext, publicKey);
            return MapEntry(memberId, ciphertext);
          } catch (e) {
            debugPrint('[E2EE] Encryption failed for member: roomId=${arg.roomId}, memberCount=${filteredMemberIds.length}, error=${e.runtimeType}');
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
      if (keysUnavailableCount == filteredMemberIds.length) {
        debugPrint('[E2EE] Complete key unavailability: roomId=${arg.roomId}, memberCount=${filteredMemberIds.length}');
        throw Exception('無法取得任何成員的公鑰');
      } else if (encryptionFailureCount == filteredMemberIds.length) {
        debugPrint('[E2EE] Complete encryption failure: roomId=${arg.roomId}, memberCount=${filteredMemberIds.length}');
        throw Exception('所有成員的加密操作均失敗');
      } else {
        debugPrint('[E2EE] Complete encryption failure (mixed): roomId=${arg.roomId}, memberCount=${filteredMemberIds.length}, keysUnavailable=$keysUnavailableCount, encryptionFailed=$encryptionFailureCount');
        throw Exception('加密失敗，無法發送訊息');
      }
    }
    
    if (keysUnavailableCount > 0 || encryptionFailureCount > 0) {
      debugPrint('[E2EE] Partial encryption success: roomId=${arg.roomId}, successful=${ciphertexts.length}, keysUnavailable=$keysUnavailableCount, encryptionFailed=$encryptionFailureCount');
    }
    
    return ciphertexts;
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
    // 🔐 修復：群組聊天也需要獲取成員的公鑰來解密訊息
    // 移除 isRoom 檢查，直接使用 userId 獲取公鑰
    return await _publicKeyCacheService.getPublicKey(userId);
  }

  /// 🔐 E2EE Auto-Resend: 處理解密失敗，使用指數退避策略持續重試
  /// 移除硬性重試上限，依賴後端 7 天 TTL 作為最終過期機制
  Future<void> _handleDecryptionFailure(
    Message message,
    DecryptionFailureException exception,
  ) async {
    if (message.id.isEmpty || exception.senderId.isEmpty) {
      return;
    }

    // 🔐 自己發送的訊息解密失敗 → 不發 re_encrypt_request
    // 避免 from == to 的無限迴圈（自己向自己請求 → 自己處理 → 自己回應 → 又觸發解密）
    if (exception.senderId == arg.currentUserId) {
      debugPrint('[E2EE] Self-sent message decryption failed, skipping re_encrypt_request: ${message.id}');
      
      // 將訊息標記為永久解密失敗
      await LocalDbService().updateMessageContentAndStatus(
        messageId: message.id,
        newContent: message.content,
        newStatus: MessageStatus.failed,
      );
      
      // 更新 UI 狀態
      final index = state.messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        final updated = message.copyWith(status: MessageStatus.failed);
        final messages = [...state.messages];
        messages[index] = updated;
        state = state.copyWith(messages: messages);
      }
      
      return;
    }

    try {
      // 1. 取得當前重試次數
      final currentRetryCount = await LocalDbService().getDecryptRetryCount(message.id);
      
      // 2. 計算指數退避延遲時間（1s, 2s, 4s, 8s, 16s, 32s, 60s max）
      final backoffSeconds = _calculateBackoffDelay(currentRetryCount);
      final nextRetry = DateTime.now().add(Duration(seconds: backoffSeconds));
      _nextRetryTime[message.id] = nextRetry;
      
      debugPrint('[E2EE Auto-Resend] Message ${message.id}: retryCount=$currentRetryCount, next retry in ${backoffSeconds}s');
      
      // 3. 啟動重試排程器（如果尚未啟動）
      _startRetryScheduler();

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
    debugPrint('🔍 [E2EE Re-Encrypt Request] Handler called with payload: $payload');
    
    final messageId = payload['message_id'] as String?;
    final receiverId = payload['receiver_id'] as String?;
    final roomId = payload['room_id'] as String?;
    
    debugPrint('[E2EE Re-Encrypt Request] 📥 Received re_encrypt_request');
    debugPrint('[E2EE Re-Encrypt Request]   message_id: $messageId');
    debugPrint('[E2EE Re-Encrypt Request]   receiver_id: $receiverId');
    debugPrint('[E2EE Re-Encrypt Request]   room_id: $roomId');
    debugPrint('[E2EE Re-Encrypt Request]   current_user_id: ${arg.currentUserId}');
    
    if (messageId == null || messageId.isEmpty || receiverId == null || receiverId.isEmpty) {
      debugPrint('[E2EE Re-Encrypt Request] ❌ Invalid payload: missing required fields');
      return;
    }
    
    try {
      final originalMessage = await LocalDbService().getMessageById(messageId);
      if (originalMessage == null) {
        debugPrint('[E2EE Re-Encrypt Request] ❌ Message not found in LocalDB: $messageId');
        return;
      }
      
      debugPrint('[E2EE Re-Encrypt Request] 📋 Original message found');
      debugPrint('[E2EE Re-Encrypt Request]   sender_id: ${originalMessage.senderId}');
      debugPrint('[E2EE Re-Encrypt Request]   current_user_id: ${arg.currentUserId}');
      
      if (originalMessage.senderId != arg.currentUserId) {
        debugPrint('[E2EE Re-Encrypt Request] ❌ Security check failed: not the sender');
        return;
      }
      
      if (originalMessage.content.isEmpty) {
        debugPrint('[E2EE Re-Encrypt Request] ❌ Original message has no content');
        return;
      }
      
      debugPrint('[E2EE Re-Encrypt Request] 🔑 Fetching receiver public key...');
      final receiverPublicKey = await _publicKeyCacheService.getPublicKey(receiverId);
      if (receiverPublicKey == null) {
        debugPrint('[E2EE Re-Encrypt Request] ❌ Receiver public key not found');
        return;
      }
      debugPrint('[E2EE Re-Encrypt Request] ✅ Receiver public key found: ${receiverPublicKey.substring(0, 8)}...');
      
      String reEncryptedContent;
      try {
        debugPrint('[E2EE Re-Encrypt Request] 🔐 Re-encrypting message...');
        if (arg.isRoom) {
          debugPrint('[E2EE Re-Encrypt Request]   Mode: Group message (fanout)');
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
          debugPrint('[E2EE Re-Encrypt Request]   Mode: Direct message');
          reEncryptedContent = await _cryptoService.encryptMessage(
            originalMessage.content,
            receiverPublicKey,
          );
        }
        debugPrint('[E2EE Re-Encrypt Request] ✅ Re-encryption successful');
        debugPrint('[E2EE Re-Encrypt Request]   Re-encrypted content length: ${reEncryptedContent.length}');
      } catch (e) {
        debugPrint('[E2EE Auto-Resend] Re-encryption failed: $e');
        return;
      }
      
      if (!_wsService.isConnected) {
        debugPrint('[E2EE Re-Encrypt Request] ❌ WebSocket not connected');
        return;
      }
      
      debugPrint('[E2EE Auto-Resend] Sending re_encrypt_response for message: $messageId to receiver: $receiverId');
      debugPrint('[E2EE Auto-Resend]   Payload: message_id=$messageId, receiver_id=$receiverId, room_id=$roomId');
      try {
        await _wsService.send('re_encrypt_response', {
          'message_id': messageId,
          'receiver_id': receiverId,
          'room_id': roomId,
          're_encrypted_content': reEncryptedContent,
        });
        debugPrint('[E2EE Auto-Resend] ✅ re_encrypt_response sent successfully');
      } catch (e) {
        debugPrint('[E2EE Auto-Resend] Failed to send re_encrypt_response: $e');
      }
    } catch (e) {
      debugPrint('[E2EE Auto-Resend] Unexpected error in _handleReEncryptRequest: $e');
    }
  }

  Future<void> _handleReEncryptResponse(Map<String, dynamic> payload) async {
    debugPrint('🔍 [E2EE Re-Encrypt Response] Handler called with payload: $payload');
    
    final messageId = payload['message_id'] as String?;
    final content = (payload['re_encrypted_content'] ?? payload['content']) as String?;
    final receiverId = payload['receiver_id'] as String?;
    
    debugPrint('[E2EE Re-Encrypt Response] 📥 Received re_encrypt_response');
    debugPrint('[E2EE Re-Encrypt Response]   message_id: $messageId');
    debugPrint('[E2EE Re-Encrypt Response]   receiver_id: $receiverId');
    debugPrint('[E2EE Re-Encrypt Response]   current_user_id: ${arg.currentUserId}');
    debugPrint('[E2EE Re-Encrypt Response]   content length: ${content?.length ?? 0}');
    debugPrint('[E2EE Re-Encrypt Response]   has re_encrypted_content: ${payload.containsKey('re_encrypted_content')}');
    debugPrint('[E2EE Re-Encrypt Response]   has content: ${payload.containsKey('content')}');
    debugPrint('[E2EE Re-Encrypt Response]   Full payload keys: ${payload.keys.toList()}');
    
    if (messageId == null || messageId.isEmpty || content == null || content.isEmpty) {
      debugPrint('[E2EE Re-Encrypt Response] ❌ Invalid payload: missing message_id or content');
      return;
    }
    
    if (receiverId != null && receiverId != arg.currentUserId) {
      debugPrint('[E2EE Re-Encrypt Response] ❌ Security check failed: receiver_id mismatch');
      debugPrint('[E2EE Re-Encrypt Response]   Expected receiver_id: ${arg.currentUserId}');
      debugPrint('[E2EE Re-Encrypt Response]   Actual receiver_id: $receiverId');
      return;
    }
    
    try {
      final originalMessage = await LocalDbService().getMessageById(messageId);
      if (originalMessage == null) {
        debugPrint('[E2EE Re-Encrypt Response] ❌ Message not found in LocalDB: $messageId');
        return;
      }
      
      debugPrint('[E2EE Re-Encrypt Response] 📋 Original message status: ${originalMessage.status.name}');
      debugPrint('[E2EE Re-Encrypt Response] 📋 Original message is_decrypted: ${originalMessage.isDecrypted}');
      
      // 🔐 修復：只要訊息尚未解密成功，就允許重新解密
      // 即使訊息已經被標記為 read（用戶進入聊天室自動觸發），但內容還是密文，就應該允許更新
      if (originalMessage.isDecrypted == true) {
        debugPrint('[E2EE Re-Encrypt Response] ⚠️ Message already decrypted, skipping');
        return;
      }
      
      debugPrint('[E2EE Re-Encrypt Response] ✅ Message not yet decrypted, proceeding with re-encryption response');
      
      // Log current private key fingerprint
      final currentPublicKey = _cryptoService.publicKeyBase64;
      final keyFingerprint = currentPublicKey != null 
          ? currentPublicKey.substring(0, 8) 
          : 'null';
      debugPrint('[E2EE Re-Encrypt Response] 🔑 Using private key with public key fingerprint: $keyFingerprint...');
      
      String decryptedContent;
      try {
        debugPrint('[E2EE Re-Encrypt Response] 🔓 Attempting decryption...');
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
          debugPrint('[E2EE Re-Encrypt Response] 🔑 Sender public key fingerprint: ${senderPublicKey.substring(0, 8)}...');
          debugPrint('[E2EE Re-Encrypt Response] 🔑 Sender public key (full): $senderPublicKey');
          debugPrint('[E2EE Re-Encrypt Response] 🔑 My public key (full): ${_cryptoService.publicKeyBase64}');
          debugPrint('[E2EE Re-Encrypt Response] 🔑 Keys are same: ${senderPublicKey == _cryptoService.publicKeyBase64}');
          
          decryptedContent = await _cryptoService.decryptMessage(content, senderPublicKey);
          
          debugPrint('[E2EE Re-Encrypt Response] 🔍 Decryption result check:');
          debugPrint('[E2EE Re-Encrypt Response]   Original ciphertext length: ${content.length}');
          debugPrint('[E2EE Re-Encrypt Response]   Decrypted content length: ${decryptedContent.length}');
          debugPrint('[E2EE Re-Encrypt Response]   Content unchanged: ${decryptedContent == content}');
          debugPrint('[E2EE Re-Encrypt Response]   Looks like base64: ${RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(decryptedContent.trim())}');
          
          if (decryptedContent == content) {
            throw Exception('Decryption failed: returned original ciphertext');
          }
        }
        debugPrint('[E2EE Re-Encrypt Response] ✅ Decryption succeeded!');
        debugPrint('[E2EE Re-Encrypt Response]   Decrypted content length: ${decryptedContent.length}');
        debugPrint('[E2EE Re-Encrypt Response]   Decrypted content preview: ${decryptedContent.substring(0, decryptedContent.length > 50 ? 50 : decryptedContent.length)}...');
      } catch (e) {
        debugPrint('[E2EE Re-Encrypt Response] ❌ Decryption failed: $e');
        
        // 🔐 關鍵修復：收到重新加密的內容後依然解密失敗，不再維持 decryptingRetry 狀態
        // 強制轉為 failed 避免死迴圈
        debugPrint('[E2EE Re-Encrypt Response] 🔄 Marking message as failed in LocalDB...');
        await LocalDbService().updateMessageContentAndStatus(
          messageId: messageId,
          newContent: '🔒 重新解密失敗',
          newStatus: MessageStatus.failed,
        );
        debugPrint('[E2EE Re-Encrypt Response] ✅ LocalDB updated: status=failed');
        
        final index = state.messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          final updated = originalMessage.copyWith(
            content: '🔒 重新解密失敗',
            status: MessageStatus.failed,
          );
          final messages = [...state.messages];
          messages[index] = updated;
          state = state.copyWith(messages: messages);
          debugPrint('[E2EE Re-Encrypt Response] ✅ Memory state updated: status=failed');
        }
        return;
      }
      
      // 解密成功
      debugPrint('[E2EE Re-Encrypt Response] 💾 Updating LocalDB with decrypted content...');
      debugPrint('[E2EE Re-Encrypt Response] 📸 Message type: ${originalMessage.type.name}');
      debugPrint('[E2EE Re-Encrypt Response] 📸 Full decrypted content: $decryptedContent');
      
      // 🖼️ 圖片/檔案訊息特殊處理：可能需要二次解密（AES 對稱加密）
      String finalContent = decryptedContent;
      if (originalMessage.type == MessageType.image || 
          originalMessage.type == MessageType.file ||
          originalMessage.type == MessageType.voice ||
          originalMessage.type == MessageType.video) {
        debugPrint('[E2EE Re-Encrypt Response] 🖼️ Detected media message (${originalMessage.type.name})');
        debugPrint('[E2EE Re-Encrypt Response] 🖼️ Content looks like URL: ${decryptedContent.startsWith('http')}');
        debugPrint('[E2EE Re-Encrypt Response] 🖼️ Content looks like base64: ${!decryptedContent.contains(' ') && decryptedContent.length > 40}');
        
        // 如果解密後的內容看起來還是 base64（不是 URL），可能需要二次解密
        if (!decryptedContent.startsWith('http') && 
            !decryptedContent.contains(' ') && 
            decryptedContent.length > 40 &&
            originalMessage.fileKey != null) {
          try {
            debugPrint('[E2EE Re-Encrypt Response] 🔓 Attempting secondary AES decryption with fileKey...');
            debugPrint('[E2EE Re-Encrypt Response] 🔑 FileKey available: ${originalMessage.fileKey != null}');
            
            // 使用 fileKey 進行 AES 解密
            final encryptedBytes = base64Decode(decryptedContent);
            final decryptedBytes = await _cryptoService.decryptBytes(
              encryptedBytes,
              originalMessage.fileKey!,
            );
            finalContent = utf8.decode(decryptedBytes);
            
            debugPrint('[E2EE Re-Encrypt Response] ✅ Secondary decryption succeeded!');
            debugPrint('[E2EE Re-Encrypt Response] 📸 Final content: $finalContent');
          } catch (e) {
            debugPrint('[E2EE Re-Encrypt Response] ⚠️ Secondary decryption failed: $e');
            debugPrint('[E2EE Re-Encrypt Response] ⚠️ Using first-layer decrypted content as-is');
            // 保持 finalContent = decryptedContent
          }
        } else if (!decryptedContent.startsWith('http')) {
          debugPrint('[E2EE Re-Encrypt Response] ⚠️ Content is not a URL and no fileKey available');
          debugPrint('[E2EE Re-Encrypt Response] ⚠️ This media message may not display correctly');
        }
      }
      
      await LocalDbService().updateMessageContentAndStatus(
        messageId: messageId,
        newContent: finalContent,
        newStatus: MessageStatus.delivered,
      );
      debugPrint('[E2EE Re-Encrypt Response] ✅ LocalDB updated: status=delivered, content updated');
      
      // 🔐 標記訊息為已解密
      debugPrint('[E2EE Re-Encrypt Response] 🔐 Marking message as decrypted (is_decrypted=1)...');
      await LocalDbService().markMessageAsDecrypted(messageId);
      debugPrint('[E2EE Re-Encrypt Response] ✅ LocalDB updated: is_decrypted=1');
      
      // Verify the update
      final verifyMessage = await LocalDbService().getMessageById(messageId);
      if (verifyMessage != null) {
        debugPrint('[E2EE Re-Encrypt Response] 🔍 Verification from LocalDB:');
        debugPrint('[E2EE Re-Encrypt Response]   is_decrypted: ${verifyMessage.isDecrypted}');
        debugPrint('[E2EE Re-Encrypt Response]   status: ${verifyMessage.status.name}');
        debugPrint('[E2EE Re-Encrypt Response]   content length: ${verifyMessage.content.length}');
      }
      
      final index = state.messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final updated = originalMessage.copyWith(
          content: finalContent,
          status: MessageStatus.delivered,
          isDecrypted: true,  // 🔐 更新記憶體中的解密狀態
        );
        final messages = [...state.messages];
        messages[index] = updated;
        state = state.copyWith(messages: messages);
        debugPrint('[E2EE Re-Encrypt Response] ✅ Memory state updated: status=delivered, is_decrypted=true');
      }
      
      // 🔐 修復：成功解密後，立即從 Scheduler 排程列表中移除
      if (_nextRetryTime.containsKey(messageId)) {
        _nextRetryTime.remove(messageId);
        debugPrint('[E2EE Re-Encrypt Response] ✅ Removed message from retry scheduler: $messageId');
      }
      
      debugPrint('[E2EE Re-Encrypt Response] 🎉 Successfully re-decrypted message: $messageId');
    } catch (e) {
      debugPrint('[E2EE Re-Encrypt Response] ❌ Unexpected error in _handleReEncryptResponse: $e');
    }
  }

  /// 🔐 E2EE Auto-Resend: 取得所有狀態為 decryptingRetry 的訊息
  /// 用於 app 重啟或 WebSocket 重連時，自動重試解密失敗的訊息
  Future<List<Message>> _getDecryptingRetryMessages() async {
    return await LocalDbService().getDecryptingRetryMessages();
  }

  /// 🔐 E2EE Auto-Resend: 初始化自動重發邏輯
  /// 在 app 重啟或 WebSocket 重連時呼叫，檢查 LocalDB 中未解密的訊息
  /// 並根據 is_decrypted 欄位決定是否發送 re_encrypt_request
  Future<void> _initializeAutoResend() async {
    // 檢查是否已初始化，防止重複執行
    if (_isAutoResendInitialized) {
      debugPrint('[E2EE Auto-Resend] Already initialized, skipping');
      return;
    }
    _isAutoResendInitialized = true;  // 立即設定，防止 race condition

    try {
      // 從 LocalDB 查詢所有 is_decrypted = 0 的訊息
      final undecryptedMessages = await LocalDbService().getUndecryptedMessages();
      
      if (undecryptedMessages.isEmpty) {
        debugPrint('[E2EE Auto-Resend] No undecrypted messages found in LocalDB');
        return;
      }

      debugPrint('[E2EE Auto-Resend] Found ${undecryptedMessages.length} undecrypted messages in LocalDB');

      // 對每條訊息，檢查在記憶體中的當前狀態
      for (final dbMessage in undecryptedMessages) {
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

        // 如果在記憶體中找到訊息且已解密，跳過該訊息
        if (memoryMessage.id.isNotEmpty && memoryMessage.isDecrypted) {
          debugPrint('[E2EE Auto-Resend] Skipping message $messageId: already decrypted in memory');
          continue;
        }

        // 取得重試次數（用於計算退避延遲）
        final retryCount = await LocalDbService().getDecryptRetryCount(messageId);
        
        // 計算指數退避延遲並排程重試
        final backoffSeconds = _calculateBackoffDelay(retryCount);
        final nextRetry = DateTime.now().add(Duration(seconds: backoffSeconds));
        _nextRetryTime[messageId] = nextRetry;
        
        debugPrint('[E2EE Auto-Resend] Scheduled retry for message $messageId: retryCount=$retryCount, delay=${backoffSeconds}s');
      }

      // 啟動重試排程器
      _startRetryScheduler();

      debugPrint('[E2EE Auto-Resend] Initialization completed');
    } catch (e) {
      debugPrint('[E2EE Auto-Resend] Unexpected error in _initializeAutoResend: $e');
    }
  }

  Future<Message> _tryDecryptMessage(Message m) async {
    // 🔐 修復：content 為空但有 encryptedContentsFanout 時，不能直接 return
    // 群組訊息的 fanout 模式下，發送方收到的回傳訊息 content 為空，
    // 但 encryptedContentsFanout 包含所有成員的密文，需要繼續解密流程
    final hasFanout = m.encryptedContentsFanout != null && m.encryptedContentsFanout!.isNotEmpty;
    if (m.isUnsent) return m;
    if (m.content.isEmpty && !hasFanout) return m;

    final isE2EEEnabled =
        ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;
    if (!isE2EEEnabled) return m;

if (arg.isRoom) {
      try {
        // 🛑 1. 新增防禦：如果 senderId 變成 roomId (系統訊息或後端給錯)，直接跳過避免 404
        if (m.senderId == arg.roomId) {
          debugPrint('[E2EE] ⚠️ 跳過解密: senderId 等於 roomId (${m.senderId})');
          return m;
        }

        Message updatedMessage = m;
        final isMedia = (m.type == MessageType.image || 
                         m.type == MessageType.video || 
                         m.type == MessageType.file || 
                         m.type == MessageType.voice);
        bool contentDecrypted = false;

        // 🔐 2. 專屬「文字訊息」的解密 (排除媒體，避免重複解密)
        if (!isMedia) {
          String decryptedText;
          if (m.encryptedContentsFanout != null) {
            final myCiphertext = m.encryptedContentsFanout![arg.currentUserId];
            if (myCiphertext == null) {
              throw DecryptionFailureException(
                messageId: m.id,
                senderId: m.senderId,
                originalCiphertext: '',
                reason: 'Missing ciphertext for current user in fanout',
              );
            }
            final senderPublicKey = await _getPublicKey(m.senderId);
            if (senderPublicKey == null) {
              throw DecryptionFailureException(
                messageId: m.id,
                senderId: m.senderId,
                originalCiphertext: myCiphertext,
                reason: 'Sender public key unavailable',
              );
            }
            decryptedText = await _cryptoService.decryptMessage(
              myCiphertext,
              senderPublicKey,
              messageId: m.id,
              senderId: m.senderId,
            );
          } else if (_looksLikeE2EECiphertext(m.content)) {
            // 新格式（Go routeMessage 裁切後）：
            // content = 接收方的專屬密文，encryptedContentsFanout 已被 Go 清空
            // 直接用 sender 的 public key 解密 content
            final senderPublicKey = await _getPublicKey(m.senderId);
            if (senderPublicKey != null) {
              try {
                decryptedText = await _cryptoService.decryptMessage(
                  m.content,
                  senderPublicKey,
                  messageId: m.id,
                  senderId: m.senderId,
                );
                debugPrint('[E2EE] ✅ Decrypted group text (stripped fanout format) for message ${m.id}');
              } catch (e) {
                debugPrint('[E2EE] ❌ Direct decryption failed, fallback to old format: $e');
                decryptedText = await _decryptGroupMessage(m.content, m.senderId, messageId: m.id);
              }
            } else {
              decryptedText = await _decryptGroupMessage(m.content, m.senderId, messageId: m.id);
            }
          } else {
            // 真正的舊格式（JSON fanout wrapper）或明文
            decryptedText = await _decryptGroupMessage(m.content, m.senderId, messageId: m.id);
          }

          if (decryptedText != m.content) {
            updatedMessage = updatedMessage.copyWith(content: decryptedText);
            contentDecrypted = true;
          }
        }

        // 🔐 3. 群組媒體：提取 fileKey
        if (m.fileKeysFanout != null && m.fileKey == null) {
          try {
            final senderPublicKey = await _getPublicKey(m.senderId);
            if (senderPublicKey != null) {
              final decryptedFileKey = await _cryptoService.extractFileKeyFromFanout(
                m.fileKeysFanout!,
                arg.currentUserId,
                senderPublicKey,
              );
              if (decryptedFileKey != null) {
                updatedMessage = updatedMessage.copyWith(fileKey: decryptedFileKey);
                debugPrint('[_tryDecryptMessage] ✅ Extracted fileKey from fanout');
              }
            }
          } catch (e) {
            debugPrint('[_tryDecryptMessage] ❌ Error extracting fileKey: $e');
          }
        }
        
        // 🔐 4. 群組媒體：解密 URL
        if (isMedia && m.encryptedContentsFanout != null && (m.content.isEmpty || _looksLikeE2EECiphertext(m.content))) {
          final myEncryptedUrl = m.encryptedContentsFanout![arg.currentUserId];
          if (myEncryptedUrl != null && myEncryptedUrl.isNotEmpty) {
            try {
              final senderPubKey = await _getPublicKey(m.senderId);
              if (senderPubKey != null) {
                final decryptedUrl = await _cryptoService.decryptMessage(
                  myEncryptedUrl,
                  senderPubKey,
                  messageId: m.id,
                  senderId: m.senderId,
                );
                updatedMessage = updatedMessage.copyWith(content: decryptedUrl);
                contentDecrypted = true;
                debugPrint('[E2EE] ✅ Decrypted media URL for message ${m.id}');
              }
            } catch (e) {
              debugPrint('[E2EE] ❌ Failed to decrypt media URL: $e');
            }
          }
        } else if (isMedia && m.encryptedContentsFanout == null) {
          // 先判斷是否為新格式（Go routeMessage 裁切後的 raw ciphertext）
          if (_looksLikeE2EECiphertext(m.content)) {
            // 新格式：直接用 sender public key 解密
            final senderPubKey = await _getPublicKey(m.senderId);
            if (senderPubKey != null) {
              try {
                final decryptedUrl = await _cryptoService.decryptMessage(
                  m.content,
                  senderPubKey,
                  messageId: m.id,
                  senderId: m.senderId,
                );
                if (decryptedUrl != m.content) {
                  updatedMessage = updatedMessage.copyWith(content: decryptedUrl);
                  contentDecrypted = true;
                  debugPrint('[E2EE] ✅ Decrypted group media URL (stripped fanout format) for message ${m.id}');
                }
              } catch (e) {
                debugPrint('[E2EE] ❌ Direct media URL decryption failed, fallback: $e');
                // fallback 到舊格式
                try {
                  final decryptedUrl = await _decryptGroupMessage(m.content, m.senderId, messageId: m.id);
                  if (decryptedUrl != m.content) {
                    updatedMessage = updatedMessage.copyWith(content: decryptedUrl);
                    contentDecrypted = true;
                  }
                } catch (e2) {
                  debugPrint('[E2EE] ❌ Old format media decryption also failed: $e2');
                }
              }
            }
          } else {
            // 真正的舊格式（JSON fanout wrapper）
            try {
              final decryptedUrl = await _decryptGroupMessage(m.content, m.senderId, messageId: m.id);
              if (decryptedUrl != m.content) {
                updatedMessage = updatedMessage.copyWith(content: decryptedUrl);
                contentDecrypted = true;
              }
            } catch (e) {
              debugPrint('[E2EE] ❌ Failed to decrypt old format media: $e');
            }
          }
        }
        
        // 🏁 5. 收尾與更新狀態
        if (contentDecrypted) {
          debugPrint('[E2EE] ✅ contentDecrypted=true, returning with isDecrypted=true for ${m.id}, content preview: ${updatedMessage.content.substring(0, updatedMessage.content.length > 30 ? 30 : updatedMessage.content.length)}');
          await LocalDbService().updateMessageStatus(m.clientMsgId ?? m.id, MessageStatus.delivered);
          await LocalDbService().markMessageAsDecrypted(m.id);
          return updatedMessage.copyWith(isDecrypted: true);
        } else if (updatedMessage.fileKey != m.fileKey) {
          return updatedMessage; // 只有 fileKey 解密成功但 content 沒變的情況
        }
        
        return updatedMessage;
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
          await LocalDbService().updateMessageStatus(m.clientMsgId ?? m.id, MessageStatus.delivered);
          await LocalDbService().markMessageAsDecrypted(m.id);
          return m.copyWith(content: decrypted, isDecrypted: true);
        }

        final looksLikeCiphertext = _looksLikeE2EECiphertext(m.content);
        if (looksLikeCiphertext) {
          return m.copyWith(content: '🔒 此訊息無法解密（金鑰已更新）');
        }
        return m;
      } on DecryptionFailureException {
        // 🔐 解密失敗：可能是對方已更換金鑰，嘗試從 API 重新取得公鑰後再試一次
        debugPrint('[E2EE] DM decryption failed, refreshing public key for $opponentId...');
        final refreshedKey = await _publicKeyCacheService.refreshPublicKey(opponentId);
        if (refreshedKey != null && refreshedKey != pubKey) {
          debugPrint('[E2EE] 🔑 Got new public key, retrying decryption...');
          try {
            final decrypted = await _cryptoService.decryptMessage(
              m.content,
              refreshedKey,
              messageId: m.id,
              senderId: m.senderId,
            );
            if (decrypted != m.content) {
              await LocalDbService().updateMessageStatus(m.clientMsgId ?? m.id, MessageStatus.delivered);
              await LocalDbService().markMessageAsDecrypted(m.id);
              return m.copyWith(content: decrypted, isDecrypted: true);
            }
          } on DecryptionFailureException catch (e2) {
            debugPrint('[E2EE] ❌ Retry with refreshed key also failed, triggering auto-resend');
            await _handleDecryptionFailure(m, e2);
            return m;
          }
        }
        // 公鑰沒變或刷新失敗，走 auto-resend 流程
        final fallbackException = DecryptionFailureException(
          messageId: m.id,
          senderId: m.senderId,
          originalCiphertext: m.content,
          reason: 'Decryption failed after key refresh',
        );
        await _handleDecryptionFailure(m, fallbackException);
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
      state = state.copyWith(
        userAvatarUrls: avatars,
        roomMemberCount: members.length,
      );
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
    Map<String, String>? encryptedContentsFanout;
    final isE2EEEnabled =
        ref.read(e2eeEnabledProvider(arg.roomId)).value ?? true;

    if (isE2EEEnabled) {
      if (arg.isRoom) {
        try {
          final members = await _chatRepository.getRoomMemberProfiles(arg.roomId);
          final memberIds = members.map((m) => m.id).toList();
          // 🔐 使用新的 fanout 格式
          encryptedContentsFanout = await _encryptGroupMessageToMap(content, memberIds);
          // content 欄位保留空字串供向後相容
          payloadContent = '';
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
      // 🔐 群組訊息：使用新的 encrypted_contents_fanout 欄位
      if (encryptedContentsFanout != null) 
        'encrypted_contents_fanout': encryptedContentsFanout,
      if (linkPreview != null) 'link_preview': {
        'url': linkPreview.url,
        'title': linkPreview.title,
        'description': linkPreview.description,
        if (linkPreview.imageUrl != null) 'image_url': linkPreview.imageUrl,
      },
    };

    // 🚀 Optimistic UI: 立即更新聊天列表（不等伺服器回應）
    _updateRoomListPreview(content, type, linkPreview);

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

  /// 🚀 Optimistic UI: 發送訊息後立即更新聊天列表的最後訊息與排序
  void _updateRoomListPreview(String content, MessageType type, dynamic linkPreview) {
    String preview;
    String? previewType = type.toString().split('.').last;
    switch (type) {
      case MessageType.image:
        preview = '[圖片]';
        break;
      case MessageType.voice:
        preview = '[語音訊息]';
        break;
      case MessageType.video:
        preview = '[影片]';
        break;
      case MessageType.file:
        preview = '[檔案]';
        break;
      default:
        if (linkPreview != null) {
          final title = linkPreview.title?.toString() ?? '';
          preview = title.isNotEmpty ? title : content;
          previewType = 'link';
        } else {
          preview = content;
        }
    }
    ref.read(roomListViewModelProvider.notifier).updateRoomLastMessage(
      arg.roomId,
      preview,
      lastMessageType: previewType,
      lastMessageTime: DateTime.now(),
    );
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

  /// 🔐 E2EE Retry: 手動重試解密失敗的訊息
  /// 當用戶點擊解密失敗的訊息時呼叫此方法
  Future<void> retryDecryptMessage(String messageId) async {
    if (messageId.isEmpty) {
      debugPrint('[E2EE Retry] Invalid messageId: empty');
      return;
    }

    try {
      // 1. 找到對應的訊息
      final index = state.messages.indexWhere((m) => m.id == messageId);
      if (index == -1) {
        debugPrint('[E2EE Retry] Message not found in state: $messageId');
        return;
      }

      final message = state.messages[index];
      
      // 2. 取得當前重試次數（用於計算退避延遲）
      final currentRetryCount = await LocalDbService().getDecryptRetryCount(messageId);
      
      debugPrint('[E2EE Retry] Manual retry for message: $messageId, retryCount=$currentRetryCount');

      // 3. 更新重試次數 + 1
      await LocalDbService().updateDecryptRetryCount(messageId, currentRetryCount + 1);

      // 4. 更新訊息狀態為 decryptingRetry
      await LocalDbService().updateMessageContentAndStatus(
        messageId: messageId,
        newContent: message.content, // 保留原密文
        newStatus: MessageStatus.decryptingRetry,
      );
      
      // 更新 UI 狀態
      final updated = message.copyWith(status: MessageStatus.decryptingRetry);
      final messages = [...state.messages];
      messages[index] = updated;
      state = state.copyWith(messages: messages);
      
      // 5. 檢查 WebSocket 連線
      if (!_wsService.isConnected) {
        debugPrint('[E2EE Retry] WebSocket not connected, will retry when reconnected');
        return;
      }
      
      // 6. 發送 re_encrypt_request
      debugPrint('[E2EE Retry] Sending re_encrypt_request for message: $messageId');
      try {
        await _wsService.send('re_encrypt_request', {
          'message_id': messageId,
          'sender_id': message.senderId,
          'receiver_id': arg.currentUserId,
          'room_id': arg.isRoom ? arg.roomId : null,
        });
        debugPrint('[E2EE Retry] re_encrypt_request sent successfully');
      } catch (e) {
        debugPrint('[E2EE Retry] Failed to send re_encrypt_request: $e');
        // 發送失敗，恢復為 failed 狀態
        await LocalDbService().updateMessageContentAndStatus(
          messageId: messageId,
          newContent: message.content,
          newStatus: MessageStatus.failed,
        );
        
        final failedUpdate = message.copyWith(status: MessageStatus.failed);
        final failedMessages = [...state.messages];
        failedMessages[index] = failedUpdate;
        state = state.copyWith(messages: failedMessages);
      }
    } catch (e) {
      debugPrint('[E2EE Retry] Unexpected error in retryDecryptMessage: $e');
    }
  }

  /// 🔐 E2EE Exponential Backoff: 計算退避延遲時間
  /// 使用指數退避策略：1s, 2s, 4s, 8s, 16s, 32s, 60s (max)
  int _calculateBackoffDelay(int retryCount) {
    if (retryCount == 0) return 1;
    final delay = (1 << retryCount).clamp(1, _maxBackoffSeconds);
    return delay;
  }

  /// 🔐 E2EE Exponential Backoff: 啟動重試排程器
  /// 每秒檢查是否有訊息需要重試
  void _startRetryScheduler() {
    if (_retrySchedulerTimer != null && _retrySchedulerTimer!.isActive) {
      return; // 排程器已在運行
    }

    _retrySchedulerTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      await _processScheduledRetries();
    });
    
    debugPrint('[E2EE Retry Scheduler] Started');
  }

  /// 🔐 E2EE Exponential Backoff: 處理排程的重試
  Future<void> _processScheduledRetries() async {
    final now = DateTime.now();
    final messagesToRetry = <String>[];

    // 找出所有需要重試的訊息
    _nextRetryTime.forEach((messageId, nextRetry) {
      if (now.isAfter(nextRetry) || now.isAtSameMomentAs(nextRetry)) {
        messagesToRetry.add(messageId);
      }
    });

    if (messagesToRetry.isEmpty) {
      return;
    }

    debugPrint('[E2EE Retry Scheduler] Processing ${messagesToRetry.length} scheduled retries');

    for (final messageId in messagesToRetry) {
      // 從排程中移除
      _nextRetryTime.remove(messageId);

      // 🔐 修復：檢查 LocalDB 中的 is_decrypted 狀態
      final dbMessage = await LocalDbService().getMessageById(messageId);
      if (dbMessage == null) {
        debugPrint('[E2EE Retry Scheduler] Message $messageId not found in LocalDB, skipping');
        continue;
      }

      // 🔐 修復：如果訊息已解密或已讀，跳過並從排程移除
      if (dbMessage.isDecrypted == true) {
        debugPrint('[E2EE Retry Scheduler] Message $messageId already decrypted (is_decrypted=true), skipping');
        continue;
      }

      if (dbMessage.status == MessageStatus.read) {
        debugPrint('[E2EE Retry Scheduler] Message $messageId already read (status=read), skipping');
        continue;
      }

      // 檢查訊息是否仍在 state 中且狀態為 decryptingRetry
      final message = state.messages.firstWhere(
        (m) => m.id == messageId,
        orElse: () => Message(
          id: '',
          content: '',
          senderId: '',
          createdAt: DateTime.now(),
        ),
      );

      if (message.id.isEmpty) {
        debugPrint('[E2EE Retry Scheduler] Message $messageId not found in state, skipping');
        continue;
      }

      if (message.status != MessageStatus.decryptingRetry) {
        debugPrint('[E2EE Retry Scheduler] Message $messageId status is ${message.status}, skipping');
        continue;
      }

      // 檢查 WebSocket 是否已連線
      if (!_wsService.isConnected) {
        debugPrint('[E2EE Retry Scheduler] WebSocket not connected, rescheduling message $messageId');
        // 重新排程（使用當前重試次數）
        final retryCount = await LocalDbService().getDecryptRetryCount(messageId);
        final backoffSeconds = _calculateBackoffDelay(retryCount);
        _nextRetryTime[messageId] = DateTime.now().add(Duration(seconds: backoffSeconds));
        continue;
      }

      // 發送 re_encrypt_request
      try {
        final retryCount = await LocalDbService().getDecryptRetryCount(messageId);
        debugPrint('[E2EE Retry Scheduler] Sending re_encrypt_request for message: $messageId (retryCount=$retryCount)');
        
        await _wsService.send('re_encrypt_request', {
          'message_id': messageId,
          'sender_id': message.senderId,
          'receiver_id': arg.currentUserId,
          'room_id': arg.isRoom ? arg.roomId : null,
        });

        // 更新重試次數
        await LocalDbService().updateDecryptRetryCount(messageId, retryCount + 1);

        // 計算下次重試時間並重新排程
        final nextBackoffSeconds = _calculateBackoffDelay(retryCount + 1);
        _nextRetryTime[messageId] = DateTime.now().add(Duration(seconds: nextBackoffSeconds));
        
        debugPrint('[E2EE Retry Scheduler] Next retry for message $messageId in ${nextBackoffSeconds}s');
      } catch (e) {
        debugPrint('[E2EE Retry Scheduler] Failed to send re_encrypt_request for message $messageId: $e');
        // 發送失敗，重新排程
        final retryCount = await LocalDbService().getDecryptRetryCount(messageId);
        final backoffSeconds = _calculateBackoffDelay(retryCount);
        _nextRetryTime[messageId] = DateTime.now().add(Duration(seconds: backoffSeconds));
      }
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

final chatRoomProvider =
    NotifierProvider.family<ChatRoomViewModel, ChatRoomState, ChatRoomParams>(
      ChatRoomViewModel.new,
    );