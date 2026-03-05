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
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/features/friend/providers/friend_provider.dart';

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

Future<void> _navigateToContactInfo() async {
    final state = ref.read(chatRoomProvider(_params));
    final effectiveAvatarUrl = state.roomAvatarUrl.isNotEmpty
        ? state.roomAvatarUrl
        : widget.avatarUrl;

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

    String? contactEmail;

    // 👉 2. 如果是單人私訊，在跳轉前主動去抓 Email
    if (!widget.isRoom) {
      // 顯示載入中的圈圈，避免使用者覺得卡頓
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // 方法 A：先嘗試從好友快取中找
        final friends = ref.read(friendViewModelProvider).friends;
        for (final f in friends) {
          if (f.id == widget.roomId) {
            contactEmail = f.email;
            break;
          }
        }

        // 方法 B：如果快取沒有，強制觸發載入一次好友清單再找找看
        if (contactEmail == null) {
          await ref.read(friendViewModelProvider.notifier).loadAll();
          final updatedFriends = ref.read(friendViewModelProvider).friends;
          for (final f in updatedFriends) {
            if (f.id == widget.roomId) {
              contactEmail = f.email;
              break;
            }
          }
        }

        // 方法 C：如果還是沒有，才嘗試調用 search API (目前後端可能無此 API 返回 404)
        if (contactEmail == null) {
          try {
            final users = await ref.read(chatRepositoryProvider).searchUsers(widget.title);
            for (final u in users) {
              if (u.id == widget.roomId) {
                contactEmail = u.email;
                break;
              }
            }
          } catch (e) {
            debugPrint('搜尋 API 失敗 (可能後端未實作 /users/search): $e');
          }
        }
      } catch (e) {
        debugPrint('取得 Email 失敗: $e');
      } finally {
        // 資料要到了，關閉載入框
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }

    // 👉 3. 確保畫面還在，再進行路由跳轉
    if (mounted) {
      context.push(
        '/contact-info',
        extra: {
          'roomId': widget.roomId,
          'title': widget.title,
          'isRoom': widget.isRoom,
          'avatarUrl': effectiveAvatarUrl,
          'mediaCount': mediaCount, 
          'email': contactEmail, // 成功帶入 Email
        },
      );
    }
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
