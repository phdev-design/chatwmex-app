// lib/screens/chat_detail_page/widgets/chat_message_list.dart (支持多選)
import 'package:flutter/material.dart';
import '../../../models/message.dart' as chat_msg;
import 'message_bubble.dart';
import 'voice_message_bubble.dart';
import 'load_more_indicator.dart';
import '../dialogs/message_options_dialog.dart';

class ChatMessageList extends StatelessWidget {
  final List<chat_msg.Message> messages;
  final String currentUserId;
  final bool isGroup;
  final String? currentUserName;
  final Animation<double> fadeAnimation;
  final bool isLoadingMore;
  final bool hasMoreMessages;
  final bool hasLoadingError;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryLoad;
  final Function(chat_msg.Message) onDeleteMessage;
  final Function(chat_msg.Message, String) onReactionAdded;
  
  // 🔥 新增：多選模式相關參數
  final bool isSelectionMode;
  final Set<String> selectedMessageIds;
  final Function(chat_msg.Message) onMessageTap;
  final VoidCallback onEnterSelectionMode;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.currentUserId,
    required this.isGroup,
    this.currentUserName,
    required this.fadeAnimation,
    required this.isLoadingMore,
    required this.hasMoreMessages,
    required this.hasLoadingError,
    required this.onLoadMore,
    required this.onRetryLoad,
    required this.onDeleteMessage,
    required this.onReactionAdded,
    // 🔥 新增參數
    this.isSelectionMode = false,
    this.selectedMessageIds = const {},
    required this.onMessageTap,
    required this.onEnterSelectionMode,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !isLoadingMore) {
      return _buildEmptyState(context);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMoreMessages &&
            !isLoadingMore &&
            notification is ScrollUpdateNotification &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200) {
          onLoadMore();
        }
        return false;
      },
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        itemCount: messages.length + (hasMoreMessages ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return LoadMoreIndicator(
              isLoading: isLoadingMore,
              hasMore: hasMoreMessages,
              onLoadMore: onLoadMore,
            );
          }

          final message = messages[index];
          final isMe = message.senderId == currentUserId;
          final isSelected = selectedMessageIds.contains(message.id);

          Widget messageWidget;
          switch (message.type) {
            case chat_msg.MessageType.voice:
              final voiceMessage = message.toVoiceMessage();
              if (voiceMessage != null) {
                // 🔥 在多選模式下，不要包裹語音消息的 Row（避免雙重嵌套）
                messageWidget = VoiceMessageBubble(
                  voiceMessage: voiceMessage,
                  isMe: isMe,
                  fadeAnimation: fadeAnimation,
                  onLongPress: () {
                    if (!isSelectionMode) {
                      showMessageOptionsDialog(
                        context,
                        message: message,
                        isMe: isMe,
                        onDelete: onDeleteMessage,
                      );
                    }
                  },
                  isCompact: isSelectionMode, // 🔥 新增：在多選模式下使用緊湊模式
                );
              } else {
                messageWidget = _buildErrorMessage(context, '語音消息格式錯誤');
              }
              break;
            case chat_msg.MessageType.text:
            default:
              messageWidget = MessageBubble(
                message: message,
                isMe: isMe,
                isGroup: isGroup,
                currentUserName: currentUserName,
                currentUserId: currentUserId,
                fadeAnimation: fadeAnimation,
                onLongPress: () {
                  if (!isSelectionMode) {
                    showMessageOptionsDialog(
                      context,
                      message: message,
                      isMe: isMe,
                      onDelete: onDeleteMessage,
                    );
                  }
                },
                onReactionAdded: (emoji) {
                  onReactionAdded(message, emoji);
                },
                // 🔥 新增：多選模式相關回調
                onEnterSelectionMode: onEnterSelectionMode,
              );
          }

          // 🔥 包裹消息以支持多選
          return KeyedSubtree(
            key: ValueKey(message.id),
            child: _buildSelectableMessage(
              context,
              message,
              messageWidget,
              isSelected,
              isMe,
            ),
          );
        },
      ),
    );
  }

  // 🔥 新增：可選擇的消息包裹器（修正：所有選擇框都在左邊）
  Widget _buildSelectableMessage(
    BuildContext context,
    chat_msg.Message message,
    Widget messageWidget,
    bool isSelected,
    bool isMe,
  ) {
    if (!isSelectionMode) {
      return messageWidget;
    }

    return GestureDetector(
      onTap: () => onMessageTap(message),
      child: Container(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
            : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // 🔥 選擇框永遠在左側（不管是誰的消息）
              _buildSelectionCircle(context, isSelected),
              const SizedBox(width: 12),
              
              // 🔥 消息內容（使用 Flexible 而不是 Expanded，避免語音消息溢出）
              Flexible(
                child: Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: messageWidget,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔥 新增：選擇圓圈（模仿 Telegram 風格）
  Widget _buildSelectionCircle(BuildContext context, bool isSelected) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: isSelected
          ? const Icon(
              Icons.check,
              size: 16,
              color: Colors.white,
            )
          : null,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasLoadingError ? Icons.cloud_off : Icons.chat_bubble_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            hasLoadingError ? '載入失敗' : '開始聊天吧！',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
          ),
          if (hasLoadingError) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              onPressed: onRetryLoad,
              label: const Text('重試'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorMessage(BuildContext context, String errorText) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Text(
            errorText,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
    );
  }
}