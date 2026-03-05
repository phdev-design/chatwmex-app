import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/widgets/chat_app_bar_title_block.dart';
import 'package:app/features/chat/ui/widgets/chat_date_divider.dart';
import 'package:app/features/chat/ui/widgets/chat_input_bar.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/features/chat/ui/widgets/chat_typing_indicator.dart';
import 'package:app/features/chat/ui/widgets/chat_unread_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart'; // 👉 新增引入
import 'package:app/models/message.dart';

class ChatDetailPage extends ConsumerStatefulWidget {
  final String roomId;
  final String title;
  final bool isRoom;
  final String currentUserId;
  final String token;
  final String? avatarUrl;

  const ChatDetailPage({
    super.key,
    required this.roomId,
    required this.title,
    this.isRoom = false,
    required this.currentUserId,
    required this.token,
    this.avatarUrl,
  });

  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage>
    with TickerProviderStateMixin {
  late final AutoScrollController _scrollController;
  bool _showNewMessageBanner = false;
  int _unreadCount = 0;
  bool _isAtBottom = true;
  late final AnimationController _arrowController;
  late final Animation<Offset> _arrowOffset;

  ChatRoomParams get _params => ChatRoomParams(
    roomId: widget.roomId,
    currentUserId: widget.currentUserId,
    isRoom: widget.isRoom,
    token: widget.token,
  );

  @override
  void initState() {
    super.initState();
    _scrollController = AutoScrollController(
      axis: Axis.vertical,
      suggestedRowHeight: 76,
    )..addListener(_onScroll);
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _arrowOffset =
        Tween<Offset>(
          begin: const Offset(0, 0),
          end: const Offset(0, 0.25),
        ).animate(
          CurvedAnimation(parent: _arrowController, curve: Curves.easeInOut),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatRoomProvider(_params).notifier).loadHistory();
      ref.read(chatRoomProvider(_params).notifier).markConversationAsRead();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _arrowController.dispose();
    super.dispose();
  }

  void _navigateToContactInfo() {
    final state = ref.read(chatRoomProvider(_params));
    final effectiveAvatarUrl = state.roomAvatarUrl.isNotEmpty
        ? state.roomAvatarUrl
        : widget.avatarUrl;

    // 👉 新增這段：計算目前的媒體、文件與連結數量
    int mediaCount = state.messages.where((m) {
      final typeName = m.type.name;
      final isMediaOrFile =
          m.type == MessageType.image ||
          m.type == MessageType.video ||
          m.type == MessageType.file ||
          typeName == 'document';
      final hasLinks = extractAllUrls(m.content).isNotEmpty;
      return isMediaOrFile || hasLinks;
    }).length;

    context.push(
      '/contact-info',
      extra: {
        'roomId': widget.roomId,
        'title': widget.title,
        'isRoom': widget.isRoom,
        'avatarUrl': effectiveAvatarUrl,
        'mediaCount': mediaCount, // 👉 將計算好的數量傳過去
      },
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = (_scrollController.offset <= 40);
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
      });
    }
    if (atBottom && (_showNewMessageBanner || _unreadCount > 0)) {
      setState(() {
        _showNewMessageBanner = false;
        _unreadCount = 0;
      });
      ref.read(chatRoomProvider(_params).notifier).markConversationAsRead();
    }
  }

  void _goToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    setState(() {
      _showNewMessageBanner = false;
      _unreadCount = 0;
      _isAtBottom = true;
    });
    ref.read(chatRoomProvider(_params).notifier).markConversationAsRead();
  }

  Future<void> _scrollToMessage(String messageId) async {
    final state = ref.read(chatRoomProvider(_params));
    final idx = state.messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    await _scrollController.scrollToIndex(
      idx,
      preferPosition: AutoScrollPosition.middle,
    );
    await _scrollController.highlight(idx);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatRoomProvider(_params));
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveAvatarUrl = state.roomAvatarUrl.isNotEmpty
        ? state.roomAvatarUrl
        : widget.avatarUrl;

    ref.listen(chatRoomProvider(_params), (prev, next) {
      if (!mounted) return;
      final prevCount = prev?.messages.length ?? 0;
      final nextCount = next.messages.length;
      if (nextCount > prevCount) {
        final newest = next.messages.first;
        final incoming = newest.senderId != widget.currentUserId;
        if (incoming && !_isAtBottom) {
          setState(() {
            _showNewMessageBanner = true;
            _unreadCount += 1;
          });
        }
      }
    });

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B141A) : colorScheme.surface,
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF111B21)
            : colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.onSurface,
        titleSpacing: 0,
        title: ChatAppBarTitleBlock(
          roomId: widget.roomId,
          title: widget.title,
          avatarUrl: effectiveAvatarUrl,
          onTap: _navigateToContactInfo,
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: state.isLoading && state.messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final msg = state.messages[index];
                          final isMe = msg.senderId == widget.currentUserId;
                          final showDate =
                              index == state.messages.length - 1 ||
                              !_isSameDay(
                                msg.createdAt,
                                state.messages[index + 1].createdAt,
                              );
                          return AutoScrollTag(
                            key: ValueKey('msg-${msg.id}'),
                            controller: _scrollController,
                            index: index,
                            child: Column(
                              children: [
                                if (showDate)
                                  ChatDateDivider(date: msg.createdAt),
                                VisibilityDetector(
                                  key: ValueKey('visible-${msg.id}'),
                                  onVisibilityChanged: (info) {
                                    if (!isMe && info.visibleFraction > 0.6) {
                                      ref
                                          .read(
                                            chatRoomProvider(_params).notifier,
                                          )
                                          .markAsRead(msg.id);
                                    }
                                  },
                                  child: MessageBubble(
                                    msg: msg,
                                    isMe: isMe,
                                    state: state,
                                    params: _params,
                                    isRoom: widget.isRoom,
                                    currentUserId: widget.currentUserId,
                                    title: widget.title,
                                    onScrollToMessage: _scrollToMessage,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (state.typingUsers.isNotEmpty) const ChatTypingIndicator(),
              ChatInputBar(
                params: _params,
                isRoom: widget.isRoom,
                title: widget.title,
                currentUserId: widget.currentUserId,
              ),
            ],
          ),
          if (_showNewMessageBanner && !_isAtBottom)
            Positioned(
              right: 16,
              bottom: 96,
              child: ChatUnreadBanner(
                unreadCount: _unreadCount,
                arrowOffset: _arrowOffset,
                onTap: _goToBottom,
              ),
            ),
        ],
      ),
    );
  }
}
