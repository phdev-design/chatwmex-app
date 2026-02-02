import 'package:flutter/material.dart';

Future<void> showDebugInfoDialog({
  required BuildContext context,
  required bool isConnected,
  required int messageCount,
  required String? currentUserId,
  required String? currentRoomId,
  required int knownMessageIdsCount,
}) async {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('調試信息'),
      content: SingleChildScrollView(
        child: ListBody(
          children: <Widget>[
            _buildInfoRow('連接狀態:', isConnected ? '已連接' : '已斷開', dialogContext),
            _buildInfoRow('當前消息數:', '$messageCount', dialogContext),
            _buildInfoRow('已知消息 ID 數:', '$knownMessageIdsCount', dialogContext),
            _buildInfoRow('用戶 ID:', currentUserId ?? 'N/A', dialogContext),
            _buildInfoRow('房間 ID:', currentRoomId ?? 'N/A', dialogContext),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('關閉'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

Widget _buildInfoRow(String label, String value, BuildContext context) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
              text: label, style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: ' $value'),
        ],
      ),
    ),
  );
}
