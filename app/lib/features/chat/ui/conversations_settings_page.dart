import 'package:flutter/material.dart';
import 'package:app/features/chat/ui/backup_conversations_page.dart';

class ConversationsSettingsPage extends StatelessWidget {
  const ConversationsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Match dark theme
      appBar: AppBar(
        title: const Text('對話 (Conversations)'),
        backgroundColor: const Color(0xFF000000),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Text(
              '備份',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            color: const Color(0xFF1C1C1E), // Darker list background
            child: ListTile(
              leading: const Icon(
                Icons.cloud_upload_outlined,
                color: Colors.blueAccent,
              ),
              title: const Text('備份對話', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BackupConversationsPage(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
