class VoiceMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String roomId;
  final String fileUrl;
  final int duration; // 语音时长（秒）
  final int fileSize; // 文件大小（字节）
  final DateTime timestamp;
  final MessageType type;

  VoiceMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.roomId,
    required this.fileUrl,
    required this.duration,
    required this.fileSize,
    required this.timestamp,
    this.type = MessageType.voice,
  });

  factory VoiceMessage.fromJson(Map<String, dynamic> json) {
    return VoiceMessage(
      id: json['id'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderName: json['sender_name'] ?? '',
      roomId: json['room'] ?? '',
      fileUrl: json['file_url'] ?? '',
      duration: json['duration'] ?? 0,
      fileSize: json['file_size'] ?? 0,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'sender_name': senderName,
      'room': roomId,
      'file_url': fileUrl,
      'duration': duration,
      'file_size': fileSize,
      'timestamp': timestamp.toIso8601String(),
      'type': 'voice',
    };
  }
}

// 扩展现有的 MessageType 枚举
enum MessageType {
  text,
  image,
  file,
  system,
  voice, // 新增语音类型
}