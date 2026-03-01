import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/friend/providers/friend_provider.dart';

class AddFriendPage extends ConsumerStatefulWidget {
  const AddFriendPage({super.key});

  @override
  ConsumerState<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends ConsumerState<AddFriendPage> {
  final _controller = TextEditingController();

  void _sendRequest() async {
    final target = _controller.text.trim();
    if (target.isEmpty) return;

    try {
      await ref.read(friendViewModelProvider.notifier).sendRequest(target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent')));
        _controller.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Friend')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Username or Email',
                hintText: 'Enter username or email',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sendRequest,
                child: const Text('Send Invite'),
              ),
            ),
            const SizedBox(height: 24),
            // Could add QR code scanner here
            const Divider(),
            const Text('Or scan QR code'),
            const SizedBox(height: 16),
            const Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
