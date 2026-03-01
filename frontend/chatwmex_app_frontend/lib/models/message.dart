import 'dart:convert';
import 'voice_message.dart';

enum MessageStatus { sending, sent, failed }

class Message {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final String roomId;
  final MessageType type;
  final Map<String, List<String>> reactions; // ✅ 新增 reactions 屬性

  // 語音訊息相關欄位
  final String? fileUrl;
  final int? duration;
  final int? fileSize;
  final bool
      isDecryptionError; // ✅ Renamed from decryptionFailed per user request
  final List<String> readBy; // 🔥 新增：已讀用戶列表
  final MessageStatus status; // 🔥 新增：消息狀態
  final String? tempId; // 🔥 新增：臨時 ID (用於精準替換)

  Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    required this.roomId,
    this.type = MessageType.text,
    this.fileUrl,
    this.duration,
    this.fileSize,
    this.reactions = const {},
    this.isDecryptionError = false, // ✅ Initialize
    this.readBy = const [], // 🔥 Initialize
    this.status = MessageStatus.sent, // 🔥 Default to sent
    this.tempId, // 🔥 Initialize
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'room_id': roomId,
      'type': type.toString().split('.').last,
      'file_url': fileUrl,
      'duration': duration,
      'file_size': fileSize,
      'reactions': jsonEncode(reactions),
      'read_by': jsonEncode(readBy),
      'status': status.index,
      // temp_id 不一定需要存入本地 DB，因为本地存的是临时消息本身
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      senderId: map['sender_id'],
      senderName: map['sender_name'],
      content: map['content'],
      timestamp: DateTime.parse(map['timestamp']),
      roomId: map['room_id'],
      type: _parseMessageType(map['type']),
      fileUrl: map['file_url'],
      duration: map['duration'],
      fileSize: map['file_size'],
      reactions: map['reactions'] != null
          ? Map<String, List<String>>.from(
              (jsonDecode(map['reactions']) as Map).map(
                (key, value) => MapEntry(
                  key as String,
                  (value as List).map((e) => e.toString()).toList(),
                ),
              ),
            )
          : {},
      readBy: map['read_by'] != null
          ? List<String>.from(jsonDecode(map['read_by']))
          : [],
      status: map['status'] != null
          ? MessageStatus.values[map['status']]
          : MessageStatus.sent,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    try {
      print(
          'Message.fromJson: 開始解析消息 - ID: ${json['id']}, Type: ${json['type']}');

      final messageType = _parseMessageType(json['type']);

      // 🔥 詳細記錄所有消息的解析過程
      print('Message.fromJson: 消息詳情:');
      print('  - ID: ${json['id']}');
      print('  - Type: ${json['type']} -> $messageType');
      print('  - Content: ${json['content']}');
      print('  - Sender: ${json['sender_name']}');
      print('  - Timestamp: ${json['timestamp']}');
      print('  - Room: ${json['room']}');

      // 🔥 語音消息特別處理
      if (messageType == MessageType.voice) {
        print('  - 語音消息額外字段:');
        print('    - FileURL: ${json['file_url']}');
        print('    - Duration: ${json['duration']}');
        print('    - FileSize: ${json['file_size']}');
      }

      // ✅ 解析 reactions
      final reactionsData = json['reactions'] as Map<String, dynamic>?;
      final reactions = <String, List<String>>{};
      if (reactionsData != null) {
        reactionsData.forEach((key, value) {
          if (value is List) {
            reactions[key] = value.map((e) => e.toString()).toList();
          }
        });
      }

      // 🔥 解析 read_by
      final readByData = json['read_by'] as List<dynamic>?;
      final readBy = readByData?.map((e) => e.toString()).toList() ?? [];

      final rawContent = json['content']?.toString() ??
          (messageType == MessageType.voice ? '[語音消息]' : '');
      // Check for both Traditional and Simplified Chinese error messages
      final isDecryptionError =
          rawContent.contains('[讯息無法解密]') || rawContent.contains('[讯息无法解密]');

      final message = Message(
        id: json['id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: json['sender_id']?.toString() ?? '',
        senderName: json['sender_name']?.toString() ?? '未知用戶',
        content: rawContent,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'].toString())
            : DateTime.now(),
        roomId: json['room']?.toString() ?? '',
        type: messageType,
        fileUrl: (messageType == MessageType.voice ||
                messageType == MessageType.image ||
                messageType == MessageType.video)
            ? json['file_url']?.toString()
            : null,
        duration: messageType == MessageType.voice
            ? _parseIntField(json['duration'])
            : null,
        fileSize: messageType == MessageType.voice
            ? _parseIntField(json['file_size'])
            : null,
        reactions: reactions,
        isDecryptionError: isDecryptionError, // ✅ Set flag
        readBy: readBy, // 🔥 Set readBy
        tempId: json['temp_id']?.toString(), // 🔥 Set tempId from Socket data
      );

      // 🔥 嚴格驗證語音消息的完整性
      if (messageType == MessageType.voice) {
        if (message.fileUrl == null || message.fileUrl!.isEmpty) {
          print('Message.fromJson: ⚠️ 語音消息缺少 fileUrl，ID: ${message.id}');
          return Message(
            id: message.id,
            senderId: message.senderId,
            senderName: message.senderName,
            content: '[語音消息文件缺失]',
            timestamp: message.timestamp,
            roomId: message.roomId,
            type: MessageType.text, // 降級為文本消息
            reactions: message.reactions,
          );
        }
        if (message.duration == null || message.duration! <= 0) {
          print(
              'Message.fromJson: ⚠️ 語音消息時長無效，ID: ${message.id}, Duration: ${message.duration}');
          return Message(
            id: message.id,
            senderId: message.senderId,
            senderName: message.senderName,
            content: message.content,
            timestamp: message.timestamp,
            roomId: message.roomId,
            type: message.type,
            fileUrl: message.fileUrl,
            duration: 1, // 默認1秒
            fileSize: message.fileSize ?? 0,
            reactions: message.reactions,
          );
        }
        print(
            'Message.fromJson: ✅ 語音消息解析成功 - ID: ${message.id}, URL: ${message.fileUrl}');
      }

      print(
          'Message.fromJson: ✅ 消息解析完成 - ID: ${message.id}, Type: ${message.type}');
      return message;
    } catch (e) {
      print('Message.fromJson: ❌ 解析失敗 - Error: $e');
      print('Message.fromJson: 原始數據 - $json');

      return Message(
        id: json['id']?.toString() ??
            'error_${DateTime.now().millisecondsSinceEpoch}',
        senderId: json['sender_id']?.toString() ?? '',
        senderName: json['sender_name']?.toString() ?? '未知用戶',
        content: '[消息解析失敗: ${e.toString()}]',
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        roomId: json['room']?.toString() ?? '',
        type: MessageType.text,
      );
    }
  }

  static int? _parseIntField(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      try {
        return int.parse(value);
      } catch (e) {
        print('Message._parseIntField: 無法解析整數: $value, Error: $e');
        return null;
      }
    }
    print('Message._parseIntField: 未知類型: ${value.runtimeType}, Value: $value');
    return null;
  }

  static MessageType _parseMessageType(dynamic typeValue) {
    if (typeValue == null) return MessageType.text;

    final typeString = typeValue.toString().toLowerCase();
    switch (typeString) {
      case 'voice':
        return MessageType.voice;
      case 'video':
        return MessageType.video;
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      case 'system':
        return MessageType.system;
      case 'text':
      default:
        return MessageType.text;
    }
  }

  VoiceMessage? toVoiceMessage() {
    if (type != MessageType.voice) {
      print('toVoiceMessage: 不是語音消息類型: $type');
      return null;
    }

    if (fileUrl == null || fileUrl!.isEmpty) {
      print('toVoiceMessage: 缺少 fileUrl');
      return null;
    }

    if (duration == null) {
      print('toVoiceMessage: 缺少 duration');
      return null;
    }

    print('toVoiceMessage: ✅ 創建語音消息 - URL: $fileUrl, Duration: ${duration}s');

    return VoiceMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      roomId: roomId,
      fileUrl: fileUrl!,
      duration: duration!,
      fileSize: fileSize ?? 0,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'room': roomId,
      'type': type.toString().split('.').last,
      if (fileUrl != null) 'file_url': fileUrl,
      if (duration != null) 'duration': duration,
      if (fileSize != null) 'file_size': fileSize,
      'reactions': reactions,
      'is_decryption_error': isDecryptionError,
    };
  }

  // ✅ 更新 copyWith 方法
  Message copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? content,
    DateTime? timestamp,
    String? roomId,
    MessageType? type,
    String? fileUrl,
    int? duration,
    int? fileSize,
    Map<String, List<String>>? reactions,
    bool? isDecryptionError,
    List<String>? readBy,
    MessageStatus? status,
    String? tempId,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      roomId: roomId ?? this.roomId,
      type: type ?? this.type,
      fileUrl: fileUrl ?? this.fileUrl,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      reactions: reactions ?? this.reactions,
      isDecryptionError: isDecryptionError ?? this.isDecryptionError,
      readBy: readBy ?? this.readBy,
      status: status ?? this.status,
      tempId: tempId ?? this.tempId,
    );
  }

  @override
  String toString() {
    return 'Message(id: $id, senderId: $senderId, senderName: $senderName, content: $content, roomId: $roomId, type: $type, reactions: $reactions, isDecryptionError: $isDecryptionError)';
  }
}

enum MessageType {
  text,
  image,
  file,
  system,
  voice,
  video,
}
