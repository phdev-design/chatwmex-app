import 'dart:convert';
import 'package:equatable/equatable.dart';

enum MessageType { text, image, voice, video, file }

enum MessageStatus { sending, sent, delivered, read, failed }

class Message extends Equatable {
  final String id;
  final String? clientMsgId;
  final String content;
  final String senderId;
  final String? receiverId;
  final String? roomId;
  final MessageType type;
  final DateTime createdAt;
  final bool isRead;
  final MessageStatus status;
  final DateTime? readAt;
  final List<String> readBy;

  const Message({
    required this.id,
    this.clientMsgId,
    required this.content,
    required this.senderId,
    this.receiverId,
    this.roomId,
    this.type = MessageType.text,
    required this.createdAt,
    this.isRead = false,
    this.status = MessageStatus.sent,
    this.readAt,
    this.readBy = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      clientMsgId: json['client_msg_id'],
      content: json['content'] ?? '',
      senderId: json['sender_id'] ?? '',
      receiverId: json['receiver_id'],
      roomId: json['room_id'],
      type: _parseType(json['type']),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      isRead: json['is_read'] ?? false,
      status: (json['is_read'] == true)
          ? MessageStatus.read
          : MessageStatus.sent,
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'])
          : null,
      readBy:
          (json['read_by'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
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
      'type': type.name,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'read_by': readBy,
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
      'type': type.name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'is_read': isRead ? 1 : 0,
      'read_at': readAt?.millisecondsSinceEpoch,
      'read_by': jsonEncode(readBy),
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    final readByRaw = map['read_by'];
    final readByList = readByRaw is String && readByRaw.isNotEmpty
        ? (jsonDecode(readByRaw) as List<dynamic>)
            .map((e) => e.toString())
            .toList()
        : const <String>[];

    return Message(
      id: map['id'] ?? '',
      clientMsgId: map['client_msg_id'],
      content: map['content'] ?? '',
      senderId: map['sender_id'] ?? '',
      receiverId: map['receiver_id'],
      roomId: map['room_id'],
      type: _parseType(map['type']),
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : DateTime.now(),
      isRead: (map['is_read'] ?? 0) == 1,
      status: (map['is_read'] ?? 0) == 1
          ? MessageStatus.read
          : MessageStatus.sent,
      readAt: map['read_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['read_at'] as int)
          : null,
      readBy: readByList,
    );
  }

  static MessageType _parseType(String? type) {
    switch (type) {
      case 'image':
        return MessageType.image;
      case 'voice':
        return MessageType.voice;
      case 'video':
        return MessageType.video;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
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
    type,
    createdAt,
    isRead,
    status,
    readAt,
    readBy,
  ];
}
