import 'package:flutter/material.dart';
import '../../../config/version_config.dart';
import '../../../services/chat_service.dart';
import '../../profile_page.dart';

void showAppOptionsDialog({
  required BuildContext context,
  required bool isConnected,
  required ChatService chatService,
}) {
  showModalBottomSheet(
    context: context,
    builder: (context) => Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('設定'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('關於'),
            onTap: () {
              Navigator.pop(context);
              showAboutDialog(
                context: context,
                applicationName: VersionConfig.appName,
                applicationVersion: VersionConfig.version,
                applicationIcon: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.chat_bubble, color: Colors.white, size: 32),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(
              isConnected ? Icons.wifi : Icons.wifi_off,
              color: isConnected ? Colors.green : Colors.red,
            ),
            title: Text('連接狀態: ${isConnected ? "已連接" : "未連接"}'),
            subtitle: Text(chatService.getConnectionStats().toString()),
            onTap: () {
              Navigator.pop(context);
              if (!isConnected) {
                chatService.reconnect();
              }
            },
          ),
        ],
      ),
    ),
  );
}