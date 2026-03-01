import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/models/message.dart';
import 'package:app/core/media/media_service.dart';

class ChatDetailPage extends ConsumerStatefulWidget {
  final String roomId;
  final String title;
  final bool isRoom;
  final String currentUserId;
  final String token;

  const ChatDetailPage({
    super.key,
    required this.roomId,
    required this.title,
    this.isRoom = false,
    required this.currentUserId,
    required this.token,
  });

  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isRecording = false;

  ChatRoomParams get _params => ChatRoomParams(
        roomId: widget.roomId,
        isRoom: widget.isRoom,
        currentUserId: widget.currentUserId,
        token: widget.token,
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      final state = ref.read(chatRoomProvider(_params));
      if (!state.isLoading) {
        ref.read(chatRoomProvider(_params).notifier).loadHistory(offset: state.messages.length);
      }
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      ref.read(chatRoomProvider(_params).notifier).sendMessage(text);
      _textController.clear();
    }
  }

  void _pickImage(ImageSource source) async {
    final mediaService = ref.read(mediaServiceProvider);
    final file = await mediaService.pickImage(source);
    if (file != null) {
      ref.read(chatRoomProvider(_params).notifier).sendMedia(file, MessageType.image);
    }
  }

  void _toggleRecording() async {
    final mediaService = ref.read(mediaServiceProvider);
    if (_isRecording) {
      final path = await mediaService.stopRecording();
      setState(() => _isRecording = false);
      if (path != null) {
        ref.read(chatRoomProvider(_params).notifier).sendMedia(File(path), MessageType.voice);
      }
    } else {
      final path = await mediaService.getTemporaryAudioPath();
      try {
        await mediaService.startRecording(path);
        setState(() => _isRecording = true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatRoomProvider(_params));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text(
              state.isConnected ? 'Connected' : 'Disconnected',
              style: TextStyle(fontSize: 12, color: state.isConnected ? Colors.greenAccent : Colors.redAccent),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty && state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: state.messages.length + (state.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == state.messages.length) {
                        return const Center(child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ));
                      }
                      final msg = state.messages[index];
                      final isMe = msg.senderId == widget.currentUserId;
                      return _buildMessageBubble(msg, isMe);
                    },
                  ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (state.typingUsers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Someone is typing...',
                        style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic, fontSize: 12),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.photo),
                        onPressed: () => _pickImage(ImageSource.gallery),
                      ),
                      IconButton(
                        icon: const Icon(Icons.camera_alt),
                        onPressed: () => _pickImage(ImageSource.camera),
                      ),
                      IconButton(
                        icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                        color: _isRecording ? Colors.red : null,
                        onPressed: _toggleRecording,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: const InputDecoration(hintText: 'Type a message...'),
                          onSubmitted: (_) => _sendMessage(),
                          onChanged: (_) {
                            ref.read(chatRoomProvider(_params).notifier).startTyping();
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message msg, bool isMe) {
    Widget content;
    if (msg.type == MessageType.image) {
      content = Image.network(msg.content);
    } else if (msg.type == MessageType.voice) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow),
          const Text('Voice Message'),
        ],
      );
    } else {
      content = Text(msg.content, style: TextStyle(color: isMe ? Colors.white : Colors.black));
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            content,
            const SizedBox(height: 2),
            Text(
              "${msg.createdAt.hour}:${msg.createdAt.minute}",
              style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
