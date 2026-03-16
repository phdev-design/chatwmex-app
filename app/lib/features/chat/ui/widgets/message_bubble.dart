import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/pdf_preview_screen.dart';
import 'package:app/features/chat/ui/photo_screen.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:app/features/chat/ui/audio_message_bubble.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:app/models/message.dart';
import 'package:app/core/media/cached_network_image_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
// 加入 emoji_picker_flutter 匯入
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:app/features/chat/ui/widgets/message_read_info_sheet.dart';

class MessageBubble extends ConsumerStatefulWidget {
  final Message msg;
  final bool isMe;
  final ChatRoomState state;
  final ChatRoomParams params;
  final bool isRoom;
  final String currentUserId;
  final String title;
  final Future<void> Function(String messageId) onScrollToMessage;

  const MessageBubble({
    super.key,
    required this.msg,
    required this.isMe,
    required this.state,
    required this.params,
    required this.isRoom,
    required this.currentUserId,
    required this.title,
    required this.onScrollToMessage,
  });

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  bool _isDeleting = false;
  bool _isCollapsing = false;
  // 滑動已讀資訊
  double _swipeOffset = 0.0;

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final isMe = widget.isMe;
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: Theme.of(context).brightness,
    );

    // 👇 根據是否為自己發送的，決定文字顏色
    final textColor = isMe ? tokens.bubbleOutgoingText : tokens.bubbleText;
    final subtleTextColor = isMe
        ? tokens.bubbleOutgoingSubtleText
        : tokens.subtleText;

    Widget content;
    
    // 🔐 E2EE Auto-Resend: 檢查是否正在重試解密
    final isDecryptingRetry = msg.status == MessageStatus.decryptingRetry;

    // 增強型密文偵測：如果長度大於 40 且符合 base64 特徵（無空白），視為未解密的密文
    // 已成功解密的訊息不做密文判斷
    final looksLikeCiphertext = !msg.isDecrypted &&
                                msg.content.length > 40 && 
                                !msg.content.contains(' ') && 
                                RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(msg.content.trim());

    // 檢查解密失敗：包含 🔒 前綴、狀態為 failed 或看起來像原始密文
    const decryptionFailurePrefix = '🔒';
    final isDecryptionFailure = msg.content.startsWith(decryptionFailurePrefix) || 
                                msg.status == MessageStatus.failed || 
                                looksLikeCiphertext;
    
    if (isDecryptingRetry) {
      // 顯示解密中的訊息
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(textColor),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '⏳ 解密中…',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: subtleTextColor,
              ),
            ),
          ),
        ],
      );
    } else if (isDecryptionFailure) {
      // 處理所有訊息類型的解密失敗
      // 顯示鎖頭圖示和錯誤文字，取代嘗試渲染加密內容
      final errorText = msg.content.startsWith(decryptionFailurePrefix) 
          ? '🔒 無法解密 點擊重試 ↺'
          : '🔒 無法解密 點擊重試 ↺';
          
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 16,
            color: subtleTextColor,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              errorText,
              style: TextStyle(
                fontSize: 13,
                color: subtleTextColor,
              ),
            ),
          ),
        ],
      );
    } else if (msg.type == MessageType.image) {
      final imageUrl = resolveFullUrl(msg.content);
      final heroTag = msg.id.isNotEmpty ? msg.id : imageUrl;
      content = GestureDetector(
        onTap: imageUrl.isEmpty
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PhotoScreen(imageUrl: imageUrl, heroTag: heroTag),
                  ),
                );
              },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Hero(
            tag: heroTag,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.6,
                maxHeight: 250,
              ),
              child: CachedNetworkImageWidget(
                imageUrl: imageUrl,
                fileKey: msg.fileKey, // 🔐 傳遞 fileKey 用於解密
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                placeholder: const SizedBox(
                  width: 120,
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: SizedBox(
                  width: 120,
                  height: 120,
                  child: Center(
                    child: Icon(
                      Icons.broken_image,
                      color: colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else if (msg.type == MessageType.voice) {
      content = AudioMessageBubble(message: msg);
    } else if (msg.type == MessageType.video) {
      // 🔐 E2EE Video: 簡單的影片訊息顯示（未來可擴展為完整播放器）
      content = GestureDetector(
        onTap: () {
          // TODO: 實作影片播放器
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('影片播放功能開發中')),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe
                ? tokens.bubbleOutgoingBackground.withValues(alpha: 0.5)
                : tokens.bubbleIncomingBackground.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 40,
                color: textColor,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '影片訊息',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '點擊播放',
                      style: TextStyle(
                        color: subtleTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else if (msg.type == MessageType.file) {
      final fileUrl = resolveFullUrl(msg.content);
      final parsed = Uri.tryParse(fileUrl);
      final fileName = (parsed != null && parsed.pathSegments.isNotEmpty)
          ? parsed.pathSegments.last
          : 'Document';
      final lowerName = fileName.toLowerCase();
      final isPdf = lowerName.endsWith('.pdf');
      content = GestureDetector(
        onTap: () async {
          if (isPdf) {
            try {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PdfPreviewScreen(pdfUrl: fileUrl, fileName: fileName),
                ),
              );
            } catch (_) {
              final uri = Uri.tryParse(fileUrl);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
            return;
          }
          final uri = Uri.tryParse(fileUrl);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
          ),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isMe
                  ? tokens.bubbleOutgoingBackground
                  : tokens.bubbleIncomingBackground,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                  color: isPdf ? Colors.redAccent : subtleTextColor,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPdf ? 'PDF 文件' : '檔案',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subtleTextColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      content = Text(msg.content, style: const TextStyle(fontSize: 15));
    }
    
    final preview = msg.linkPreview;
    // 嚴格防止 Link Preview 在未解密、錯誤或重試狀態下被觸發
    final hasPreview =
        !msg.isUnsent &&
        !isDecryptionFailure &&
        !isDecryptingRetry &&
        preview != null &&
        (preview.url.isNotEmpty ||
            preview.title.isNotEmpty ||
            preview.description.isNotEmpty);
    
    Widget? linkPreviewCard;
    if (hasPreview) {
      final previewUrl = resolveFullUrl(preview.url);
      
      final rawImageUrl = preview.imageUrl;
      final previewImageUrl = (rawImageUrl != null && rawImageUrl.isNotEmpty)
          ? resolveFullUrl(rawImageUrl)
          : '';
      
      linkPreviewCard = GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(previewUrl);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.6,
          ),
          child: Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tokens.replyBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tokens.composerBackground,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: previewImageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImageWidget(
                            imageUrl: previewImageUrl,
                            fit: BoxFit.cover,
                            width: 44,
                            height: 44,
                            errorWidget: Icon(Icons.link, color: colorScheme.primary),
                          ),
                        )
                      : Icon(Icons.link, color: colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (preview.title.isNotEmpty)
                        Text(
                          preview.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (preview.title.isNotEmpty && preview.description.isNotEmpty)
                        const SizedBox(height: 3),
                      if (preview.description.isNotEmpty)
                        Text(
                          preview.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: subtleTextColor,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final replyMessage = msg.isUnsent ? null : msg.replyToMessage;
    Widget? replyContent;
    if (replyMessage != null) {
      final isReplyImage = replyMessage.type == MessageType.image;
      final replyText = isReplyImage ? '[圖片]' : replyMessage.content;
      replyContent = InkWell(
        onTap: () => widget.onScrollToMessage(replyMessage.id),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: tokens.replyBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: tokens.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _resolveReplySenderName(replyMessage),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isReplyImage) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              resolveFullUrl(replyMessage.content),
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 28,
                                  height: 28,
                                  color: tokens.imageFallbackBackground,
                                  child: Icon(
                                    Icons.broken_image,
                                    size: 14,
                                    color: tokens.subtleText,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            replyText,
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.subtleText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final timeText = DateFormat('a h:mm').format(msg.createdAt);

    // 訊息狀態顏色：已閱讀為主顏色，其餘為次要文字色
    final statusColor = msg.status == MessageStatus.read
        ? tokens.accent
        : subtleTextColor;

    // 訊息狀態圖示
    IconData statusIcon;
    switch (msg.status) {
      case MessageStatus.pending:
        statusIcon = Icons.schedule;
        break;
      case MessageStatus.sending:
        statusIcon = Icons.access_time;
        break;
      case MessageStatus.sent:
        statusIcon = Icons.check;
        break;
      case MessageStatus.delivered:
        statusIcon = Icons.done_all;
        break;
      case MessageStatus.read:
        statusIcon = Icons.done_all;
        break;
      case MessageStatus.failed:
        statusIcon = Icons.error_outline;
        break;
      case MessageStatus.decryptingRetry:
        statusIcon = Icons.sync;
        break;
    }
    
    final statusWidget = isMe
        ? Icon(
            statusIcon,
            size: 14,
            color: msg.status == MessageStatus.failed
                ? Colors.redAccent
                : statusColor,
          )
        : const SizedBox.shrink();
        
    final reactions = msg.isUnsent
        ? <String, List<String>>{}
        : (msg.reactions ?? {});
    final double paddingBottom = reactions.isNotEmpty ? 22.0 : 4.0;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 60 : 44,
          right: isMe ? 12 : 60,
          bottom: paddingBottom,
        ),
        child: GestureDetector(
          onHorizontalDragUpdate: isMe && !msg.isUnsent
              ? (details) {
                  // 只允許向左滑（負方向）
                  if (details.delta.dx < 0 || _swipeOffset < 0) {
                    setState(() {
                      _swipeOffset = (_swipeOffset + details.delta.dx).clamp(-80.0, 0.0);
                    });
                  }
                }
              : null,
          onHorizontalDragEnd: isMe && !msg.isUnsent
              ? (details) {
                  if (_swipeOffset < -40) {
                    // 觸發已讀資訊彈窗
                    _showReadInfoSheet(context, msg);
                  }
                  setState(() => _swipeOffset = 0.0);
                }
              : null,
          child: AnimatedContainer(
            duration: _swipeOffset == 0
                ? const Duration(milliseconds: 200)
                : Duration.zero,
            transform: Matrix4.translationValues(_swipeOffset, 0, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 滑動時顯示的箭頭提示
                if (isMe && _swipeOffset < -10)
                  Positioned(
                    right: -24,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.grey.withValues(alpha: (-_swipeOffset / 80).clamp(0.0, 1.0)),
                      ),
                    ),
                  ),
                AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _isCollapsing
              ? const SizedBox.shrink()
              : AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _isDeleting ? 0.0 : 1.0,
                  child: IgnorePointer(
                    ignoring: _isDeleting,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (!isMe)
                          Positioned(
                            left: -32,
                            top: 0,
                            child: _buildGroupSenderAvatar(msg),
                          ),
                        Builder(
                          builder: (bubbleContext) {
                            return GestureDetector(
                              onTap: (isDecryptionFailure && !isDecryptingRetry)
                                  ? () {
                                      ref
                                          .read(chatRoomProvider(widget.params).notifier)
                                          .retryDecryptMessage(msg.id);
                                    }
                                  : null,
                              onLongPress: msg.isUnsent
                                  ? null
                                  : () {
                                      HapticFeedback.mediumImpact();
                                      _showMessageActions(
                                        msg,
                                        bubbleContext,
                                        isMe,
                                      );
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? tokens.bubbleOutgoingBackground
                                      : tokens.bubbleIncomingBackground,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isDecryptionFailure
                                      ? Border.all(color: Colors.orange, width: 2)
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (replyContent != null) ...[
                                      replyContent,
                                      const SizedBox(height: 6),
                                    ],
                                    msg.isUnsent
                                        ? Text(
                                            '此訊息已收回',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic,
                                              color: subtleTextColor,
                                            ),
                                          )
                                        : DefaultTextStyle.merge(
                                            style: TextStyle(color: textColor),
                                            child: content,
                                          ),
                                    if (linkPreviewCard != null) linkPreviewCard,
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          timeText,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: subtleTextColor,
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          statusWidget,
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        if (reactions.isNotEmpty)
                          Positioned(
                            bottom: -16,
                            right: isMe ? 4 : null,
                            left: isMe ? null : 4,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: _buildReactionsBar(reactions, msg.id),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
              ],  // Stack children for swipe wrapper
            ),  // AnimatedContainer
          ),  // GestureDetector for swipe
        ),  // Padding
      ),  // Align
    );
  }

  void _showReadInfoSheet(BuildContext context, Message msg) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => MessageReadInfoSheet(
        msg: msg,
        isRoom: widget.isRoom,
        roomId: widget.params.roomId,
        userAvatarUrls: widget.state.userAvatarUrls,
      ),
    );
  }

  Widget _buildGroupSenderAvatar(Message msg) {
    final avatarUrl = widget.isRoom
        ? widget.state.userAvatarUrls[msg.senderId]
        : (widget.state.roomAvatarUrl.isNotEmpty
              ? widget.state.roomAvatarUrl
              : null);
    final fallbackText = widget.isRoom
        ? (msg.senderId.isNotEmpty ? msg.senderId[0].toUpperCase() : '?')
        : (widget.title.isNotEmpty ? widget.title[0].toUpperCase() : '?');
    return ChatAvatar(
      radius: 14,
      avatarUrl: avatarUrl,
      fallbackText: fallbackText,
      logTag: 'chat_bubble',
    );
  }

  void _showFullEmojiPicker(BuildContext context, Message msg) {
    final tokens = resolveChatSurfaceTokens(
      colorScheme: Theme.of(context).colorScheme,
      brightness: Theme.of(context).brightness,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: tokens.menuBackground,
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.45,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    Navigator.of(context).pop(); 
                    ref
                        .read(chatRoomProvider(widget.params).notifier)
                        .toggleReaction(msg.id, emoji.emoji);
                  },
                  config: Config(
                    height: 256,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: tokens.menuBackground,
                      columns: 7,
                      emojiSizeMax:
                          28 *
                          (foundation.defaultTargetPlatform ==
                                  TargetPlatform.iOS
                              ? 1.30
                              : 1.0),
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: tokens.menuBackground,
                      indicatorColor: tokens.accent,
                      iconColorSelected: tokens.accent,
                      iconColor: tokens.subtleText,
                      dividerColor: Colors.transparent,
                    ),
                    bottomActionBarConfig: BottomActionBarConfig(
                      backgroundColor: tokens.menuBackground,
                      buttonColor: tokens.menuBackground,
                      buttonIconColor: tokens.subtleText,
                    ),
                    searchViewConfig: SearchViewConfig(
                      backgroundColor: tokens.menuBackground,
                      buttonIconColor: tokens.subtleText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMessageActions(Message msg, BuildContext bubbleContext, bool isMe) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢'];
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: Theme.of(context).brightness,
    );
    final RenderBox renderBox = bubbleContext.findRenderObject() as RenderBox;
    final bubbleSize = renderBox.size;
    final bubbleOffset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    const menuWidth = 240.0;
    double menuHeight = 155.0;
    if (msg.senderId == widget.currentUserId && !msg.isUnsent) {
      menuHeight = 199.0;
    }
    bool showAbove = true;
    double top = bubbleOffset.dy - menuHeight - 8.0;
    final topSafeArea = MediaQuery.of(context).padding.top + kToolbarHeight;
    if (top < topSafeArea) {
      showAbove = false;
      top = bubbleOffset.dy + bubbleSize.height + 8.0;
    }
    if (!showAbove && top + menuHeight > screenSize.height - 30) {
      top = screenSize.height - menuHeight - 30;
    }
    double left;
    if (isMe) {
      left = (bubbleOffset.dx + bubbleSize.width) - menuWidth;
    } else {
      left = bubbleOffset.dx;
    }
    if (left < 16) left = 16;
    if (left + menuWidth > screenSize.width - 16) {
      left = screenSize.width - menuWidth - 16;
    }
    final animationAlignment = showAbove
        ? (isMe ? Alignment.bottomRight : Alignment.bottomLeft)
        : (isMe ? Alignment.topRight : Alignment.topLeft);

    showGeneralDialog(
      context: context,
      barrierColor: Colors.black12,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Container(color: Colors.transparent),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      alignment: animationAlignment,
                      child: Opacity(
                        opacity: scale.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: menuWidth,
                      decoration: BoxDecoration(
                        color: tokens.menuBackground,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ...emojis.map((emoji) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.of(context).pop();
                                          ref
                                              .read(
                                                chatRoomProvider(
                                                  widget.params,
                                                ).notifier,
                                              )
                                              .toggleReaction(msg.id, emoji);
                                        },
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: tokens.menuEmojiBackground,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            emoji,
                                            style: const TextStyle(
                                              fontSize: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        _showFullEmojiPicker(context, msg);
                                      },
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: tokens.menuEmojiBackground,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.add,
                                          color: tokens.subtleText,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          _buildMenuAction(
                            icon: Icons.reply,
                            label: '回覆',
                            onTap: () {
                              Navigator.of(context).pop();
                              ref
                                  .read(
                                    chatRoomProvider(widget.params).notifier,
                                  )
                                  .setReplyingTo(msg);
                            },
                          ),
                          _buildMenuAction(
                            icon: Icons.delete_outline,
                            label: '刪除 (Delete for me)',
                            onTap: () {
                              Navigator.of(context).pop();
                              _confirmDeleteMessage(msg);
                            },
                          ),
                          if (msg.senderId == widget.currentUserId &&
                              !msg.isUnsent)
                            _buildMenuAction(
                              icon: Icons.undo,
                              label: '收回 (Unsend)',
                              onTap: () {
                                Navigator.of(context).pop();
                                ref
                                    .read(
                                      chatRoomProvider(widget.params).notifier,
                                    )
                                    .unsendMessage(msg);
                              },
                            ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteMessage(Message msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('刪除訊息'),
          content: const Text('確定要刪除這則訊息嗎？此訊息僅會從您的設備中刪除，對方仍可看見。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('確定'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || _isDeleting) return;
    setState(() => _isDeleting = true);
    await Future.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    setState(() => _isCollapsing = true);
    await Future.delayed(const Duration(milliseconds: 180));
    try {
      await ref
          .read(chatRoomProvider(widget.params).notifier)
          .deleteMessage(msg.id);
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _isCollapsing = false;
        });
      }
    }
  }

  Widget _buildMenuAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: iconColor, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionsBar(
    Map<String, List<String>> reactions,
    String messageId,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = reactions.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries.map((entry) {
        final emoji = entry.key;
        final users = entry.value;
        final reacted = users.contains(widget.currentUserId);

        return InkWell(
          onTap: () => ref
              .read(chatRoomProvider(widget.params).notifier)
              .toggleReaction(messageId, emoji),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                if (users.length > 1) ...[
                  const SizedBox(width: 4),
                  Text(
                    '${users.length}',
                    style: TextStyle(
                      fontSize: 13,
                      color: reacted
                          ? const Color(0xFF53BDEB)
                          : colorScheme.onSurfaceVariant,
                      fontWeight: reacted ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String _resolveReplySenderName(Message replyMessage) {
    if (replyMessage.senderId == widget.currentUserId) {
      return '你';
    }
    if (!widget.isRoom && widget.title.isNotEmpty) {
      return widget.title;
    }
    return '回覆訊息';
  }
}