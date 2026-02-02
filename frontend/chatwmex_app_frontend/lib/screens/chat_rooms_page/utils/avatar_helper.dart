import 'package:flutter/material.dart';

/// 根據名稱獲取頭像顯示的文字
String getAvatarText(String name) {
  if (name.isEmpty) return '?';
  // 如果是 Email，取第一個字母
  if (name.contains('@')) {
    return name.substring(0, 1).toUpperCase();
  }
  final words = name.split(' ');
  // 如果有多個單詞，取前兩個單詞的首字母
  if (words.length >= 2 && words[0].isNotEmpty && words[1].isNotEmpty) {
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
  // 否則取第一個字母
  return name.substring(0, 1).toUpperCase();
}

/// 根據名稱的哈希值獲取一個固定的顏色
Color getAvatarColor(String name) {
  final colors = [
    const Color(0xFF6366F1), // Indigo
    const Color(0xFF8B5CF6), // Purple
    const Color(0xFF06B6D4), // Cyan
    const Color(0xFF10B981), // Emerald
    const Color(0xFFF59E0B), // Amber
    const Color(0xFFEF4444), // Red
    const Color(0xFF3B82F6), // Blue
    const Color(0xFF84CC16), // Lime
  ];
  return colors[name.hashCode % colors.length];
}
