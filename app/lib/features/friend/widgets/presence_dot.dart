import 'package:flutter/material.dart';

/// 綠點在線指示器，疊加在頭像右下角
class PresenceDot extends StatelessWidget {
  final bool isOnline;
  final double size;
  final Color borderColor;

  const PresenceDot({
    super.key,
    required this.isOnline,
    this.size = 12,
    this.borderColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOnline) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF4CD964), // iOS 系統綠
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
    );
  }
}

/// 格式化最後上線時間為人類可讀字串
String formatLastSeen(DateTime? lastSeen) {
  if (lastSeen == null) return '';
  final now = DateTime.now();
  final diff = now.difference(lastSeen.toLocal());

  if (diff.inSeconds < 60) return '剛剛上線';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前上線';
  if (diff.inHours < 24) return '${diff.inHours} 小時前上線';
  if (diff.inDays == 1) return '昨天上線';
  if (diff.inDays < 7) return '${diff.inDays} 天前上線';

  final local = lastSeen.toLocal();
  return '${local.month}/${local.day} 上線';
}
