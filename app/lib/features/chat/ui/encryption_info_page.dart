import 'package:flutter/material.dart';
import 'package:app/features/chat/ui/security_code_page.dart';

class EncryptionInfoPage extends StatelessWidget {
  final String contactId;
  final String contactName;
  final String currentUserId;

  const EncryptionInfoPage({
    super.key,
    required this.contactId,
    required this.contactName,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryTextColor = colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color bgColor = isDark ? const Color(0xFF0B141A) : colorScheme.surface;
    
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('端對端加密'),
        backgroundColor: bgColor,
        scrolledUnderElevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Text(
              '你和 $contactName 的訊息和通話都受到端對端加密保護，即使是 ChatWmex 也無法讀取。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: primaryTextColor,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 60),
            Icon(
              Icons.lock,
              size: 100,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 60),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SecurityCodePage(
                      contactId: contactId,
                      contactName: contactName,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                '檢視安全碼',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
