import 'package:flutter/material.dart';

/// 根據名稱生成一個穩定的顏色
Color getAvatarColor(String name) {
  final colors = [
    const Color(0xFF6366F1), // Indigo
    const Color(0xFF8B5CF6), // Violet
    const Color(0xFF06B6D4), // Cyan
    const Color(0xFF10B981), // Emerald
    const Color(0xFFF59E0B), // Amber
    const Color(0xFFEF4444), // Red
    const Color(0xFF3B82F6), // Blue
    const Color(0xFF84CC16), // Lime
  ];
  // 使用 hashCode確保同一個名字總是對應同一個顏色
  return colors[name.hashCode % colors.length];
}
