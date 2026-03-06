import 'package:flutter/material.dart';
import 'package:app/features/chat/ui/conversations_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _buildSection([
            ListTile(
              leading: const Icon(
                Icons.chat_bubble_outline,
                color: Colors.white,
              ),
              title: const Text(
                '對話 (Conversations)',
                style: TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ConversationsSettingsPage(),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}
