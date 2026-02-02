import 'package:intl/intl.dart';

/// 格式化時間以便在聊天室列表顯示
String formatTime(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);

  // 如果是今天
  if (now.year == time.year && now.month == time.month && now.day == time.day) {
    return DateFormat('HH:mm').format(time);
  }
  // 如果是昨天
  final yesterday = now.subtract(const Duration(days: 1));
  if (yesterday.year == time.year && yesterday.month == time.month && yesterday.day == time.day) {
    return '昨天';
  }
  // 如果在同一年
  if (now.year == time.year) {
    return DateFormat('M月d日').format(time);
  }
  // 如果是更早
  return DateFormat('yyyy年M月d日').format(time);
}
