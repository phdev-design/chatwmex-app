/// 格式化消息時間
String formatMessageTime(DateTime timestamp) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

  final timeStr =
      '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

  if (messageDate == today) {
    return timeStr;
  } else if (messageDate == yesterday) {
    return '昨天 $timeStr';
  } else if (timestamp.year == now.year) {
    return '${timestamp.month}/${timestamp.day} $timeStr';
  } else {
    return '${timestamp.year}/${timestamp.month}/${timestamp.day}';
  }
}
