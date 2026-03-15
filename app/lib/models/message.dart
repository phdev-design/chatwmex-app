import 'dart:convert';
import 'package:equatable/equatable.dart';

enum MessageType { 
  text, 
  image, 
  voice, 
  video, 
  file, 
  link, 
  document,
  // 🔐 E2EE Auto-Resend Control Messages (不顯示在 UI，僅供內部邏輯使用)
  reEncryptRequest,   // 接收方請求重新加密
  reEncryptResponse,  // 發送方回傳重新加密的訊息
}

/// 訊息传送狀態枚裄
/// - pending: 離線中，已存入本地，尚未發送
/// - sending: 發送中（暂時狀態）
/// - sent:    已到達伺服器
/// - delivered: 已送達接收方裝置
/// - read:    接收方已閱讀
/// - failed:  發送失敗
/// - decryptingRetry: 🔐 解密失敗，正在請求重新加密（顯示「正在同步金鑰...」）
enum MessageStatus { 
  pending, 
  sending, 
  sent, 
  delivered, 
  read, 
  failed,
  decryptingRetry,  // 🔐 新增：解密重試中
}

class LinkPreview extends Equatable {
  final String url;
  final String title;
  final String description;
  final String? imageUrl;

  const LinkPreview({
    required this.url,
    required this.title,
    required this.description,
    this.imageUrl,
  });

  factory LinkPreview.fromJson(Map<String, dynamic> json) {
    final imageUrlRaw = (json['image_url'] ?? '').toString();
    return LinkPreview(
      url: (json['url'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      imageUrl: imageUrlRaw.isNotEmpty ? imageUrlRaw : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      'description': description,
      'image_url': imageUrl,
    };
  }

  @override
  List<Object?> get props => [url, title, description, imageUrl];
}

class Message extends Equatable {
  final String id;
  final String? clientMsgId;
  final String content;
  final String senderId;
  final String? receiverId;
  final String? roomId;
  final String? replyToMessageId;
  final Message? replyToMessage;
  final Map<String, List<String>>? reactions;
  final bool isUnsent;
  final MessageType type;
  final DateTime createdAt;
  final bool isRead;
  final MessageStatus status;
  final DateTime? readAt;
  final List<String> readBy;
  final LinkPreview? linkPreview;
  /// For encrypted audio/image/video messages
  /// Stores the symmetric encryption key (base64 encoded)
  final String? fileKey;
  
  /// 🔐 E2EE Group Media: FileKeysFanout 用於群組媒體加密
  /// 每個成員的 fileKey 用該成員的公鑰加密，格式：{"is_fanout": true, "keys": {userId: encryptedKey, ...}}
  final Map<String, dynamic>? fileKeysFanout;
  
  /// 🔐 E2EE Group Text Messages: EncryptedContentsFanout 用於群組文字訊息加密
  /// 每個成員的訊息內容用該成員的公鑰加密，格式：{userId: encryptedContent, ...}
  /// key = userId, value = 該成員專屬的加密密文（base64 字串）
  final Map<String, String>? encryptedContentsFanout;
  
  /// 🔐 E2EE Auto-Resend: 解密重試計數器
  /// 記錄此訊息已嘗試重新加密的次數（最多 2 次）
  /// null 表示從未失敗過，0 表示第一次失敗
  final int? decryptRetryCount;

  /// 🔐 E2EE Auto-Resend: 解密狀態追蹤（獨立於 is_read）
  /// true 表示訊息已成功解密，false 表示尚未解密或解密失敗
  /// 用於 E2EE Auto-Resend 判斷是否需要發送 re_encrypt_request
  final bool isDecrypted;

  const Message({
    required this.id,
    this.clientMsgId,
    required this.content,
    required this.senderId,
    this.receiverId,
    this.roomId,
    this.replyToMessageId,
    this.replyToMessage,
    this.reactions,
    this.isUnsent = false,
    this.type = MessageType.text,
    required this.createdAt,
    this.isRead = false,
    this.status = MessageStatus.sent,
    this.readAt,
    this.readBy = const [],
    this.linkPreview,
    this.fileKey,
    this.fileKeysFanout,
    this.encryptedContentsFanout,
    this.decryptRetryCount,  // 🔐 新增
    this.isDecrypted = false,  // 🔐 新增：預設為 false
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    Map<String, List<String>>? reactions;
    final reactionsRaw = json['reactions'];
    if (reactionsRaw is Map) {
      reactions = reactionsRaw.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        ),
      );
    }
    return Message(
      id: json['id'] ?? '',
      clientMsgId: json['client_msg_id'],
      content: json['content'] ?? '',
      senderId: json['sender_id'] ?? '',
      receiverId: json['receiver_id'],
      roomId: json['room_id'],
      replyToMessageId: json['reply_to_message_id'],
      reactions: reactions,
      isUnsent: json['is_unsent'] ?? false,
      type: _parseType(json['type']),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      isRead: json['is_read'] ?? false,
      // 优先從後端回傳的 status 字串解析，否則用 is_read 推斷
      status:
          _parseStatus(json['status']) ??
          ((json['is_read'] == true) ? MessageStatus.read : MessageStatus.sent),
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'])
          : null,
      readBy:
          (json['read_by'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      linkPreview: json['link_preview'] is Map
          ? LinkPreview.fromJson(
              Map<String, dynamic>.from(json['link_preview']),
            )
          : null,
      fileKey: json['file_key'],
      fileKeysFanout: json['file_keys_fanout'] is Map
          ? Map<String, dynamic>.from(json['file_keys_fanout'])
          : null,
      encryptedContentsFanout: json['encrypted_contents_fanout'] is Map
          ? (json['encrypted_contents_fanout'] as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            )
          : null,
      decryptRetryCount: json['decrypt_retry_count'],  // 🔐 新增
      isDecrypted: json['is_decrypted'] == 1 || json['is_decrypted'] == true,  // 🔐 新增
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'client_msg_id': clientMsgId,
      'content': content,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'room_id': roomId,
      'reply_to_message_id': replyToMessageId,
      'reactions': reactions,
      'is_unsent': isUnsent,
      'type': type.name,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'read_by': readBy,
      'link_preview': linkPreview?.toJson(),
      'file_key': fileKey,
      'file_keys_fanout': fileKeysFanout,
      'encrypted_contents_fanout': encryptedContentsFanout,
      'decrypt_retry_count': decryptRetryCount,  // 🔐 新增
      'is_decrypted': isDecrypted,  // 🔐 新增
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client_msg_id': clientMsgId,
      'content': content,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'room_id': roomId,
      'reply_to_message_id': replyToMessageId,
      'reactions': reactions != null ? jsonEncode(reactions) : null,
      'is_unsent': isUnsent ? 1 : 0,
      'type': type.name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'is_read': isRead ? 1 : 0,
      'read_at': readAt?.millisecondsSinceEpoch,
      'read_by': jsonEncode(readBy),
      // 新増：將 status 持久化到 SQLite
      'status': status.name,
      // 修正：將 linkPreview 轉成 JSON 字串存入本地資料庫
      'link_preview': linkPreview != null
          ? jsonEncode(linkPreview!.toJson())
          : null,
      'file_key': fileKey,
      'file_keys_fanout': fileKeysFanout != null
          ? jsonEncode(fileKeysFanout!)
          : null,
      'encrypted_contents_fanout': encryptedContentsFanout != null
          ? jsonEncode(encryptedContentsFanout!)
          : null,
      'decrypt_retry_count': decryptRetryCount,  // 🔐 新增
      'is_decrypted': isDecrypted ? 1 : 0,  // 🔐 新增：轉換為 INTEGER
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    final readByRaw = map['read_by'];
    final readByList = readByRaw is String && readByRaw.isNotEmpty
        ? (jsonDecode(readByRaw) as List<dynamic>)
              .map((e) => e.toString())
              .toList()
        : const <String>[];

    final reactionsRaw = map['reactions'];
    Map<String, List<String>>? reactions;
    if (reactionsRaw is String && reactionsRaw.isNotEmpty) {
      final decoded = jsonDecode(reactionsRaw);
      if (decoded is Map) {
        reactions = decoded.map(
          (key, value) => MapEntry(
            key.toString(),
            (value as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
          ),
        );
      }
    }

    // 修正：解析從本地資料庫讀取出來的 link_preview JSON 字串
    LinkPreview? parsedLinkPreview;
    final linkPreviewRaw = map['link_preview'];
    if (linkPreviewRaw is String && linkPreviewRaw.isNotEmpty) {
      try {
        parsedLinkPreview = LinkPreview.fromJson(jsonDecode(linkPreviewRaw));
      } catch (e) {
        // 解析失敗時忽略
      }
    } else if (linkPreviewRaw is Map) {
      parsedLinkPreview = LinkPreview.fromJson(
        Map<String, dynamic>.from(linkPreviewRaw),
      );
    }

    // 🔐 解析 file_keys_fanout JSON 字串
    Map<String, dynamic>? parsedFileKeysFanout;
    final fileKeysFanoutRaw = map['file_keys_fanout'];
    if (fileKeysFanoutRaw is String && fileKeysFanoutRaw.isNotEmpty) {
      try {
        parsedFileKeysFanout = Map<String, dynamic>.from(jsonDecode(fileKeysFanoutRaw));
      } catch (e) {
        // 解析失敗時忽略
      }
    } else if (fileKeysFanoutRaw is Map) {
      parsedFileKeysFanout = Map<String, dynamic>.from(fileKeysFanoutRaw);
    }

    // 🔐 解析 encrypted_contents_fanout JSON 字串
    Map<String, String>? parsedEncryptedContentsFanout;
    final encryptedContentsFanoutRaw = map['encrypted_contents_fanout'];
    if (encryptedContentsFanoutRaw is String && encryptedContentsFanoutRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(encryptedContentsFanoutRaw);
        if (decoded is Map) {
          parsedEncryptedContentsFanout = decoded.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
      } catch (e) {
        // 解析失敗時忽略
      }
    } else if (encryptedContentsFanoutRaw is Map) {
      parsedEncryptedContentsFanout = encryptedContentsFanoutRaw.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    }

    return Message(
      id: map['id'] ?? '',
      clientMsgId: map['client_msg_id'],
      content: map['content'] ?? '',
      senderId: map['sender_id'] ?? '',
      receiverId: map['receiver_id'],
      roomId: map['room_id'],
      replyToMessageId: map['reply_to_message_id'],
      reactions: reactions,
      isUnsent: (map['is_unsent'] ?? 0) == 1,
      type: _parseType(map['type']),
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : DateTime.now(),
      isRead: (map['is_read'] ?? 0) == 1,
      // 优先讀取 SQLite 中儲存的 status 字串，有效支援 pending 狀態
      status:
          _parseStatus(map['status']) ??
          ((map['is_read'] ?? 0) == 1
              ? MessageStatus.read
              : MessageStatus.sent),
      readAt: map['read_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['read_at'] as int)
          : null,
      readBy: readByList,
      linkPreview: parsedLinkPreview,
      fileKey: map['file_key'],
      fileKeysFanout: parsedFileKeysFanout,
      encryptedContentsFanout: parsedEncryptedContentsFanout,
      decryptRetryCount: map['decrypt_retry_count'],  // 🔐 新增
      isDecrypted: (map['is_decrypted'] ?? 0) == 1,  // 🔐 新增
    );
  }

  static MessageType _parseType(String? type) {
    switch (type) {
      case 'audio':
        return MessageType.voice;
      case 'image':
        return MessageType.image;
      case 'voice':
        return MessageType.voice;
      case 'video':
        return MessageType.video;
      case 'file':
        return MessageType.file;
      case 'document':
        return MessageType.document;
      case 'link':
        return MessageType.link;
      // 🔐 E2EE Auto-Resend Control Messages
      case 're_encrypt_request':
        return MessageType.reEncryptRequest;
      case 're_encrypt_response':
        return MessageType.reEncryptResponse;
      default:
        return MessageType.text;
    }
  }

  /// 解析 status 字串為枚裄，未知則回傳 null
  static MessageStatus? _parseStatus(String? s) {
    switch (s) {
      case 'pending':
        return MessageStatus.pending;
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      case 'decrypting_retry':  // 🔐 新增
        return MessageStatus.decryptingRetry;
      default:
        return null;
    }
  }

  @override
  List<Object?> get props => [
    id,
    clientMsgId,
    content,
    senderId,
    receiverId,
    roomId,
    replyToMessageId,
    reactions,
    isUnsent,
    type,
    createdAt,
    isRead,
    status,
    readAt,
    readBy,
    linkPreview,
    fileKey,
    fileKeysFanout,
    encryptedContentsFanout,
    decryptRetryCount,  // 🔐 新增
    isDecrypted,  // 🔐 新增
  ];

  Message copyWith({
    String? id,
    String? clientMsgId,
    String? content,
    String? senderId,
    String? receiverId,
    String? roomId,
    String? replyToMessageId,
    Message? replyToMessage,
    Map<String, List<String>>? reactions,
    bool? isUnsent,
    MessageType? type,
    DateTime? createdAt,
    bool? isRead,
    MessageStatus? status,
    DateTime? readAt,
    List<String>? readBy,
    LinkPreview? linkPreview,
    String? fileKey,
    Map<String, dynamic>? fileKeysFanout,
    Map<String, String>? encryptedContentsFanout,
    int? decryptRetryCount,  // 🔐 新增
    bool? isDecrypted,  // 🔐 新增
  }) {
    return Message(
      id: id ?? this.id,
      clientMsgId: clientMsgId ?? this.clientMsgId,
      content: content ?? this.content,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      roomId: roomId ?? this.roomId,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      reactions: reactions ?? this.reactions,
      isUnsent: isUnsent ?? this.isUnsent,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      status: status ?? this.status,
      readAt: readAt ?? this.readAt,
      readBy: readBy ?? this.readBy,
      linkPreview: linkPreview ?? this.linkPreview,
      fileKey: fileKey ?? this.fileKey,
      fileKeysFanout: fileKeysFanout ?? this.fileKeysFanout,
      encryptedContentsFanout: encryptedContentsFanout ?? this.encryptedContentsFanout,
      decryptRetryCount: decryptRetryCount ?? this.decryptRetryCount,  // 🔐 新增
      isDecrypted: isDecrypted ?? this.isDecrypted,  // 🔐 新增
    );
  }
}
