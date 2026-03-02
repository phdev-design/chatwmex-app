import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
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

class _ChatDetailPageState extends ConsumerState<ChatDetailPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isRecording = false;
  int _lastMessageCount = 0;
  bool _showNewMessageBanner = false;
  int _unreadCount = 0;
  bool _hasInitialized = false;
  bool _isAtBottom = true;
  late final AnimationController _arrowController;
  late final Animation<Offset> _arrowOffset;

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
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _arrowOffset =
        Tween<Offset>(
          begin: const Offset(0, 0),
          end: const Offset(0, 0.2),
        ).animate(
          CurvedAnimation(parent: _arrowController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _arrowController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final state = ref.read(chatRoomProvider(_params));
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    _isAtBottom = current >= max - 20;
    if (_isAtBottom && _showNewMessageBanner) {
      if (mounted) {
        setState(() {
          _showNewMessageBanner = false;
          _unreadCount = 0;
        });
      }
    }
    if (current == max && !state.isLoading) {
      if (_showNewMessageBanner) {
        if (mounted) {
          setState(() {
            _showNewMessageBanner = false;
            _unreadCount = 0;
          });
        }
      }
      ref
          .read(chatRoomProvider(_params).notifier)
          .loadHistory(offset: state.messages.length);
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
      ref
          .read(chatRoomProvider(_params).notifier)
          .sendMedia(file, MessageType.image);
    }
  }

  void _toggleRecording() async {
    final mediaService = ref.read(mediaServiceProvider);
    if (_isRecording) {
      final path = await mediaService.stopRecording();
      setState(() => _isRecording = false);
      if (path != null) {
        ref
            .read(chatRoomProvider(_params).notifier)
            .sendMedia(File(path), MessageType.voice);
      }
    } else {
      final path = await mediaService.getTemporaryAudioPath();
      try {
        await mediaService.startRecording(path);
        setState(() => _isRecording = true);
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatRoomProvider(_params));
    if (!_hasInitialized && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _hasInitialized = true;
            _lastMessageCount = state.messages.length;
            _unreadCount = 0;
            _showNewMessageBanner = false;
          });
        }
      });
    } else if (_hasInitialized) {
      final hasNewMessage = state.messages.length > _lastMessageCount;
      final isLatestFromMe =
          hasNewMessage &&
          state.messages.isNotEmpty &&
          state.messages.last.senderId == widget.currentUserId;
      final addedCount = state.messages.length - _lastMessageCount;
      if (addedCount > 0 && !isLatestFromMe && !_isAtBottom) {
        _unreadCount += addedCount;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _showNewMessageBanner = true);
          }
        });
      }
      if (isLatestFromMe) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
          if (mounted && _showNewMessageBanner) {
            setState(() {
              _showNewMessageBanner = false;
              _unreadCount = 0;
            });
          }
        });
      }
      if (_isAtBottom && _showNewMessageBanner) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _showNewMessageBanner = false;
              _unreadCount = 0;
            });
          }
        });
      }
      _lastMessageCount = state.messages.length;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text(
              state.isConnected ? 'Connected' : 'Disconnected',
              style: TextStyle(
                fontSize: 12,
                color: state.isConnected
                    ? Colors.greenAccent
                    : Colors.redAccent,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: state.messages.isEmpty && state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: false,
                          itemCount:
                              state.messages.length + (state.isLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == state.messages.length) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final msg = state.messages[index];
                            final isMe = msg.senderId == widget.currentUserId;
                            return _buildMessageBubble(msg, isMe);
                          },
                        ),
                ),
                if (_showNewMessageBanner)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: Center(
                      child: GestureDetector(
                        onTap: () {
                          if (mounted) {
                            setState(() {
                              _showNewMessageBanner = false;
                              _unreadCount = 0;
                            });
                          }
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_scrollController.hasClients) {
                              _scrollController.animateTo(
                                _scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                              );
                            }
                          });
                        },
                        child: AnimatedOpacity(
                          opacity: _showNewMessageBanner ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SlideTransition(
                                  position: _arrowOffset,
                                  child: const Icon(
                                    Icons.arrow_downward,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '新訊息 ${_unreadCount > 99 ? '99+' : _unreadCount}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (state.typingUsers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 4.0,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedOpacity(
                        opacity: state.typingUsers.isNotEmpty ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          '對方輸入中...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
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
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                          ),
                          onSubmitted: (_) => _sendMessage(),
                          onChanged: (_) {
                            ref
                                .read(chatRoomProvider(_params).notifier)
                                .startTyping();
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
        children: [const Icon(Icons.play_arrow), const Text('Voice Message')],
      );
    } else {
      content = Text(
        msg.content,
        style: TextStyle(color: isMe ? Colors.white : Colors.black),
      );
    }

    final statusWidget = isMe ? _buildStatusIcon(msg) : const SizedBox();
    final statusText = isMe ? _buildStatusText(msg) : const SizedBox();

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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                statusWidget,
                statusText,
                Text(
                  "${msg.createdAt.hour}:${msg.createdAt.minute}",
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white70 : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(Message msg) {
    if (msg.status == MessageStatus.sending) {
      return const Padding(
        padding: EdgeInsets.only(right: 4),
        child: Icon(Icons.access_time, size: 12, color: Colors.white70),
      );
    }
    if (msg.status == MessageStatus.failed) {
      return GestureDetector(
        onTap: () =>
            ref.read(chatRoomProvider(_params).notifier).retrySend(msg),
        child: const Padding(
          padding: EdgeInsets.only(right: 4),
          child: Icon(Icons.refresh, size: 12, color: Colors.redAccent),
        ),
      );
    }
    if (msg.status == MessageStatus.sent) {
      return const Padding(
        padding: EdgeInsets.only(right: 4),
        child: Icon(Icons.check, size: 12, color: Colors.white70),
      );
    }
    if (msg.status == MessageStatus.delivered) {
      return const Padding(
        padding: EdgeInsets.only(right: 4),
        child: Icon(Icons.done_all, size: 12, color: Colors.white70),
      );
    }
    if (msg.status == MessageStatus.read) {
      return const Padding(
        padding: EdgeInsets.only(right: 4),
        child: Icon(Icons.done_all, size: 12, color: Colors.lightBlueAccent),
      );
    }
    return const SizedBox(width: 0, height: 0);
  }

  Widget _buildStatusText(Message msg) {
    if (msg.status == MessageStatus.sending) {
      return const Padding(
        padding: EdgeInsets.only(right: 4),
        child: Text(
          'Sending',
          style: TextStyle(fontSize: 10, color: Colors.white70),
        ),
      );
    }
    if (msg.status == MessageStatus.failed) {
      return const Padding(
        padding: EdgeInsets.only(right: 4),
        child: Text(
          'Failed',
          style: TextStyle(fontSize: 10, color: Colors.redAccent),
        ),
      );
    }
    if (msg.status == MessageStatus.read) {
      final time = msg.readAt ?? msg.createdAt;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Text(
          '已讀 ${_formatTime(time)}',
          style: const TextStyle(fontSize: 10, color: Colors.lightBlueAccent),
        ),
      );
    }
    return const SizedBox(width: 0, height: 0);
  }

  String _formatTime(DateTime time) {
    return DateFormat('yyyy/MM/dd HH:mm').format(time);
  }
}
