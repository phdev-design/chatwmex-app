class ChatSetting {
  final String chatId;
  final int disappearingTimer;
  final int? muteUntil; // 新增：Unix timestamp（秒），null=不靜音，-1=永久靜音

  const ChatSetting({
    required this.chatId,
    required this.disappearingTimer,
    this.muteUntil,
  });

  factory ChatSetting.fromJson(Map<String, dynamic> json) {
    return ChatSetting(
      chatId: json['chat_id'] ?? '',
      disappearingTimer: json['disappearing_timer'] ?? 0,
      muteUntil: json['mute_until'] as int?,
    );
  }

  /// 當前是否處於靜音狀態
  bool get isMuted {
    if (muteUntil == null) return false;
    if (muteUntil == -1) return true;
    return DateTime.now().millisecondsSinceEpoch < muteUntil! * 1000;
  }

  /// 靜音狀態的顯示文字（用於 subtitle）
  String get muteDescription {
    if (!isMuted) return '';
    if (muteUntil == -1) return '已靜音（保持關閉）';
    final until = DateTime.fromMillisecondsSinceEpoch(muteUntil! * 1000);
    final diff = until.difference(DateTime.now());
    if (diff.inHours >= 24) return '靜音至 ${diff.inDays + 1} 天後';
    return '靜音至 ${diff.inHours + 1} 小時後';
  }
}
