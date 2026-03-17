class ChatSetting {
  final String chatId;
  final int disappearingTimer;
  final int? muteUntil; // 新增：Unix timestamp（秒），null=不靜音，-1=永久靜音
  final int saveToCameraRoll; // 0=依全域設定, 1=永遠開啟, 2=永遠關閉
  final int autoDownload; // 0=依全域設定, 1=永遠, 2=僅Wi-Fi, 3=永不
  final int mediaQuality; // 0=依全域設定, 1=高畫質HD, 2=節省數據
  final bool? readReceiptsEnabled; // null=使用全域設定, true/false=覆蓋全域

  const ChatSetting({
    required this.chatId,
    required this.disappearingTimer,
    this.muteUntil,
    this.saveToCameraRoll = 0,
    this.autoDownload = 0,
    this.mediaQuality = 0,
    this.readReceiptsEnabled,
  });

  factory ChatSetting.fromJson(Map<String, dynamic> json) {
    return ChatSetting(
      chatId: json['chat_id'] ?? '',
      disappearingTimer: json['disappearing_timer'] ?? 0,
      muteUntil: json['mute_until'] as int?,
      saveToCameraRoll: json['save_to_camera_roll'] ?? 0,
      autoDownload: json['auto_download'] ?? 0,
      mediaQuality: json['media_quality'] ?? 0,
      readReceiptsEnabled: json['read_receipts_enabled'] as bool?,
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
