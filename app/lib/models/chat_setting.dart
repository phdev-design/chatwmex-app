class ChatSetting {
  final String id;
  final String chatId;
  final int disappearingTimer;
  final DateTime updatedAt;

  ChatSetting({
    required this.id,
    required this.chatId,
    required this.disappearingTimer,
    required this.updatedAt,
  });

  factory ChatSetting.fromJson(Map<String, dynamic> json) {
    return ChatSetting(
      id: json['id'] as String? ?? '',
      chatId: json['chat_id'] as String? ?? '',
      disappearingTimer: json['disappearing_timer'] as int? ?? 0,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'disappearing_timer': disappearingTimer,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
