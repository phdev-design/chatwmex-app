// lib/pages/chat/widgets/chat_input_area.dart
import 'package:flutter/material.dart';
import '../../../widgets/voice_recording_widget.dart';

/// 聊天輸入區域組件
class ChatInputArea extends StatefulWidget {
  final TextEditingController messageController;
  final FocusNode messageFocusNode;
  final bool isConnected;
  final bool isRecordingVoice;
  final VoidCallback onSendMessage;
  final ValueChanged<String> onTextChanged;
  final Future<void> Function(String, int) onVoiceRecordingComplete;
  final VoidCallback onVoiceRecordingCancelled;
  final ValueChanged<bool> onVoiceRecordingStateChanged;

  const ChatInputArea({
    super.key,
    required this.messageController,
    required this.messageFocusNode,
    required this.isConnected,
    required this.isRecordingVoice,
    required this.onSendMessage,
    required this.onTextChanged,
    required this.onVoiceRecordingComplete,
    required this.onVoiceRecordingCancelled,
    required this.onVoiceRecordingStateChanged,
  });

  @override
  State<ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<ChatInputArea> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.messageController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.messageController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
    widget.onTextChanged(widget.messageController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: SafeArea(
        child: VoiceRecordingWidget(
          onRecordingComplete: widget.onVoiceRecordingComplete,
          onRecordingCancelled: widget.onVoiceRecordingCancelled,
          onRecordingStateChanged: widget.onVoiceRecordingStateChanged,
          showMicButton: !_hasText, // 🔥 传递是否显示麦克风按钮
          inputWidget: _buildInputRow(context),
        ),
      ),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    return Row(
      children: [
        // 附件按鈕
        if (!widget.isRecordingVoice)
          IconButton(
            onPressed: () {},
            icon: Icon(
              Icons.add,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),

        // 文本輸入框
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.background,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: widget.messageController,
              focusNode: widget.messageFocusNode,
              decoration: const InputDecoration(
                hintText: 'Message...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              enabled: true,
              onTap: () {
                if (!widget.messageFocusNode.hasFocus) {
                  widget.messageFocusNode.requestFocus();
                }
              },
              onSubmitted: (_) {
                if (!widget.isRecordingVoice) {
                  widget.onSendMessage();
                }
              },
            ),
          ),
        ),

        const SizedBox(width: 8),

        // 🔥 发送按钮 - 只在有文字且未录音时显示
        if (_hasText && !widget.isRecordingVoice)
          Container(
            decoration: BoxDecoration(
              color: widget.isConnected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: widget.isConnected && _hasText ? widget.onSendMessage : null,
              icon: const Icon(Icons.send, color: Colors.white),
            ),
          ),
      ],
    );
  }
}