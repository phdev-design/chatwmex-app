import 'package:flutter/material.dart';

class ConnectionStatusBar extends StatelessWidget {
  final bool isConnected;
  final VoidCallback onReconnect;

  const ConnectionStatusBar({
    super.key,
    required this.isConnected,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    if (isConnected) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.withOpacity(0.1),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 16, color: Colors.orange[700]),
          const SizedBox(width: 8),
          Text('離線模式', style: TextStyle(fontSize: 12, color: Colors.orange[700])),
          const Spacer(),
          IconButton(
            onPressed: onReconnect,
            icon: Icon(Icons.refresh, size: 16, color: Colors.orange[700]),
            tooltip: '重新連接',
          ),
        ],
      ),
    );
  }
}
