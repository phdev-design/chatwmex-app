import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatDateDivider extends StatelessWidget {
  final DateTime date;

  const ChatDateDivider({
    super.key,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('yyyy/MM/dd').format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2A3942),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
          ),
        ),
      ),
    );
  }
}
