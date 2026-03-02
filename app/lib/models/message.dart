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
  ];
}
