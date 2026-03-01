import 'package:equatable/equatable.dart';

enum MessageType { text, image, voice, video, file }

class Message extends Equatable {
  final String id;
  final String content;
  final String senderId;
  final String? receiverId;
  final String? roomId;
  final MessageType type;
  final DateTime createdAt;
  final bool isRead;

  const Message({
    required this.id,
    required this.content,
    required this.senderId,
    this.receiverId,
    this.roomId,
    this.type = MessageType.text,
    required this.createdAt,
    this.isRead = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      senderId: json['sender_id'] ?? '',
      receiverId: json['receiver_id'],
      roomId: json['room_id'],
      type: _parseType(json['type']),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      isRead: json['is_read'] ?? false,
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
  List<Object?> get props => [id, content, senderId, receiverId, roomId, type, createdAt, isRead];
}
