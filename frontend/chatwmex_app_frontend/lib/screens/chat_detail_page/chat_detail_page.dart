// lib/screens/chat_detail_page/chat_detail_page.dart (完全修正版)
import 'package:flutter/material.dart';
import '../../models/chat_room.dart';
import '../../models/message.dart' as chat_msg;
import '../../models/voice_message.dart' as voice_msg;
import '../../services/chat_service.dart';
import '../../services/chat_api_service.dart' as api_service;
import '../../utils/token_storage.dart';
import 'package:chat2mex_app_frontend/services/api_client_service.dart';
import 'dart:io';

// Mixins
import 'mixins/chat_message_handler.dart';
import 'mixins/chat_loading_handler.dart';
import 'mixins/chat_lifecycle_handler.dart';
import 'mixins/chat_audio_handler.dart';

// Widgets
import 'widgets/chat_input_area.dart';
import 'widgets/chat_app_bar.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/chat_selection_app_bar.dart';
import 'widgets/chat_selection_bottom_bar.dart';

// Dialogs
import 'dialogs/debug_info_dialog.dart';
import 'dialogs/group_info_dialog.dart';
import 'dialogs/user_info_dialog.dart';

class ChatDetailPage extends StatefulWidget {
  final ChatRoom chatRoom;

  const ChatDetailPage({super.key, required this.chatRoom});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage>
    with
        TickerProviderStateMixin,
        WidgetsBindingObserver,
        ChatMessageHandler,
        ChatLoadingHandler,
        ChatLifecycleHandler,
        ChatAudioHandler {
  // === 控制器和服務 ===
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  @override
  final ChatService chatService = ChatService();

  // === 私有狀態變數 ===
  final ValueNotifier<List<chat_msg.Message>> _messagesNotifier =
      ValueNotifier<List<chat_msg.Message>>([]);
  final Set<String> _knownMessageIds = {};
  final Set<String> _pendingTempMessages = {};

  // 🔥 新增：多選模式相關
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = {};

  // 🔥 Typing 狀態
  final Set<String> _typingUsers = {};

  bool _isLoading = true;
  bool _isTyping = false;
  bool _isRecordingVoice = false;
  bool _isConnected = false;
  bool _isLoadingMoreMessages = false;
  bool _hasMoreMessages = true;
  int _currentPage = 1;
  bool _isNewChatRoom = false;
  bool _hasLoadingError = false;

  String? _currentUserId;
  String? _currentUserName;
  String _chatDisplayName = '';

  // 🔥 新增：封鎖狀態
  bool _isBlocked = false;

  Future<void> _checkBlockStatus() async {
    if (widget.chatRoom.isGroup || _currentUserId == null) return;

    try {
      final blockedUsers = await api_service.ChatApiService.getBlockedUsers();
      final otherUserId = widget.chatRoom.participants
          .firstWhere((id) => id != _currentUserId, orElse: () => '');

      if (otherUserId.isNotEmpty) {
        if (mounted) {
          setState(() {
            _isBlocked = blockedUsers.any((u) => u.id == otherUserId);
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to check block status: $e');
    }
  }

  Future<void> _toggleBlockUser() async {
    if (widget.chatRoom.isGroup || _currentUserId == null) return;
    final otherUserId = widget.chatRoom.participants
        .firstWhere((id) => id != _currentUserId, orElse: () => '');
    if (otherUserId.isEmpty) return;

    try {
      if (_isBlocked) {
        await api_service.ChatApiService.unblockUser(otherUserId);
        if (mounted) setState(() => _isBlocked = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已解除封鎖用戶')));
      } else {
        // Confirm block
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('封鎖用戶'),
            content: const Text('確定要封鎖此用戶嗎？您將無法收到對方的訊息。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('封鎖', style: TextStyle(color: Colors.red))),
            ],
          ),
        );

        if (confirm == true) {
          await api_service.ChatApiService.blockUser(otherUserId);
          if (mounted) setState(() => _isBlocked = true);
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('已封鎖用戶')));
        }
      }
    } catch (e) {
      // 🔥 忽略 401 錯誤
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新封鎖狀態失敗: $e')));
    }
  }

  // === 動畫 ===
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // === Mixin Getters ===
  @override
  List<chat_msg.Message> get messages => _messagesNotifier.value;
  @override
  Set<String> get knownMessageIds => _knownMessageIds;
  @override
  Set<String> get pendingTempMessages => _pendingTempMessages;
  @override
  bool get isConnected => _isConnected;
  @override
  bool get isLoadingMoreMessages => _isLoadingMoreMessages;
  @override
  bool get hasMoreMessages => _hasMoreMessages;
  @override
  int get currentPage => _currentPage;
  @override
  bool get isNewChatRoom => _isNewChatRoom;
  @override
  bool get hasLoadingError => _hasLoadingError;
  @override
  String? get currentUserId => _currentUserId;
  @override
  String? get currentUserName => _currentUserName;
  @override
  String get currentRoomId => widget.chatRoom.id;
  @override
  String get chatRoomId => widget.chatRoom.id;
  @override
  VoidCallback get onAppResumed => _handleAppResume;
  @override
  VoidCallback get onAppPaused => _handleAppPause;
  @override
  BuildContext get buildContext => context;

  // === Mixin Setters ===
  @override
  set messages(List<chat_msg.Message> value) {
    if (!mounted) return;
    _messagesNotifier.value = List<chat_msg.Message>.from(value);
  }

  @override
  set knownMessageIds(Set<String> value) {
    _knownMessageIds.clear();
    _knownMessageIds.addAll(value);
  }

  @override
  set pendingTempMessages(Set<String> value) {
    _pendingTempMessages.clear();
    _pendingTempMessages.addAll(value);
  }

  @override
  set hasMoreMessages(bool value) => setState(() => _hasMoreMessages = value);
  @override
  set isLoadingMoreMessages(bool value) =>
      setState(() => _isLoadingMoreMessages = value);
  @override
  set currentPage(int value) => _currentPage = value;
  @override
  set isNewChatRoom(bool value) => _isNewChatRoom = value;
  @override
  set hasLoadingError(bool value) => setState(() => _hasLoadingError = value);

  @override
  void initState() {
    super.initState();
    _initializePage();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.removeListener(_onFocusChanged);
    _messageFocusNode.dispose();
    _animationController.dispose();
    _messagesNotifier.dispose();

    disposeAudioHandler();
    disposeLifecycleHandler();
    cleanupMessageState();

    chatService.unregisterMessageReadListener('chat_detail_page');
    chatService.unregisterMessageListener('chat_detail_page');
    chatService.unregisterConnectionListener('chat_detail_page');
    chatService.unregisterTypingListener(widget.chatRoom.id); // 🔥 新增：取消註冊

    super.dispose();
  }

  Future<void> _initializePage() async {
    initializeLifecycleHandler();
    initializeAudioHandler();

    _animationController = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _chatDisplayName = widget.chatRoom.name;
    _messageFocusNode.addListener(_onFocusChanged);

    await _initializeChat();
    if (mounted) _animationController.forward();
  }

  Future<void> _initializeChat() async {
    try {
      if (mounted) setState(() => _isLoading = true);

      // 1. 获取当前用户ID (如果还没获取)
      if (_currentUserId == null) {
        final userId = await TokenStorage.getUserId();
        final userName = await TokenStorage.getUsername();
        if (mounted) {
          setState(() {
            _currentUserId = userId;
            _currentUserName = userName;
          });
        }
      }

      // 2. 初始化Socket服务
      await chatService.initialize();

      // 2.5 檢查封鎖狀態
      if (!widget.chatRoom.isGroup) {
        _checkBlockStatus();
      }

      // 3. 注册消息监听
      chatService.registerMessageListener(
          widget.chatRoom.id, _onMessageReceived);

      // 注册连接状态监听
      final connectionKey = 'chat_detail_connection_${widget.chatRoom.id}';
      chatService.registerConnectionListener(
          connectionKey, _onConnectionChanged);

      // 註冊 Reaction 更新監聽
      chatService.registerReactionUpdateListener(
          widget.chatRoom.id, _onReactionUpdate);

      // 註冊已讀監聽
      final readKey = 'chat_detail_read_${widget.chatRoom.id}';
      chatService.registerMessageReadListener(
          readKey, _onMessageRead);

      // 🔥 新增：註冊 Typing 監聽
      chatService.registerTypingListener(
          widget.chatRoom.id, _onTypingStatusChanged);

      // 4. 加入房间
      chatService.joinRoom(widget.chatRoom.id);

      // 5. 初始加载消息
      await forceReloadMessages();

      // 6. 發送已讀標記
      api_service.ChatApiService.markAsRead(widget.chatRoom.id);
      chatService.markAsRead(widget.chatRoom.id);
    } catch (e) {
      debugPrint('Chat initialization error: $e');
      if (mounted) {
        // 🔥 忽略 401 錯誤
        if (e.toString().contains('401') ||
            e.toString().contains('Unauthorized')) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('聊天初始化失敗: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onMessageReceived(chat_msg.Message message) {
    if (!mounted) return;
    handleNewMessageReceived(message);
    final currentMessages = _messagesNotifier.value;
    if (currentMessages.isNotEmpty) {
      playNotificationSound(currentMessages.first);
    }
  }

  void _onMessageRead(String roomId, String userId) {
    if (!mounted || roomId != widget.chatRoom.id) return;

    // Update local messages state
    final currentMessages =
        List<chat_msg.Message>.from(_messagesNotifier.value);
    bool changed = false;

    for (int i = 0; i < currentMessages.length; i++) {
      final msg = currentMessages[i];
      if (msg.senderId == _currentUserId) {
        // My message, check if I need to add userId to readBy
        if (!msg.readBy.contains(userId)) {
          final updatedReadBy = List<String>.from(msg.readBy)..add(userId);
          currentMessages[i] = msg.copyWith(readBy: updatedReadBy);
          changed = true;
        }
      }
    }

    if (changed) {
      _messagesNotifier.value = currentMessages;
    }
  }

  // 🔥 新增：Reaction 更新回調 (空實現，避免報錯)
  void _onReactionUpdate(
      String messageId, Map<String, List<String>> reactions) {
    // TODO: 實現 Reaction 更新邏輯
  }

  // 🔥 新增：Typing 狀態更新回調
  void _onTypingStatusChanged(String roomId, String username, bool isTyping) {
    if (!mounted || roomId != widget.chatRoom.id) return;
    // 不顯示自己的輸入狀態
    if (username == _currentUserName) return;

    setState(() {
      if (isTyping) {
        _typingUsers.add(username);
      } else {
        _typingUsers.remove(username);
      }
    });
  }

  void _onConnectionChanged(bool conn) {
    if (mounted) setState(() => _isConnected = conn);
  }

  void _onFocusChanged() {
    debugPrint('焦點狀態變化: ${_messageFocusNode.hasFocus}');
  }

  void _handleAppResume() {
    debugPrint("App Resumed");
    if (!_isConnected) chatService.initialize();
    api_service.ChatApiService.markAsRead(widget.chatRoom.id);
    chatService.markAsRead(widget.chatRoom.id);
  }

  void _handleAppPause() {
    debugPrint("App Paused");
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    sendTextMessage(content);
    _messageController.clear();
    _messageFocusNode.requestFocus();
  }

  Future<void> _handleVoiceRecordingComplete(
      String filePath, int durationSeconds) async {
    debugPrint('語音錄製完成: $filePath, 時長: $durationSeconds seconds');

    if (durationSeconds < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('錄音時間太短'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    sendVoiceMessage(filePath, durationSeconds);
  }

  // 🔥 新增：進入/退出多選模式
  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedMessageIds.clear();
      }
    });
  }

  // 🔥 新增：選擇/取消選擇消息
  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        // 如果沒有選中任何消息，自動退出多選模式
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  // 🔥 新增：全選
  void _selectAll() {
    setState(() {
      _selectedMessageIds.clear();
      _selectedMessageIds.addAll(_messagesNotifier.value.map((m) => m.id));
    });
  }

  // 🔥 新增：刪除選中的消息
  void _deleteSelectedMessages() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除消息'),
        content: Text('確定要刪除 ${_selectedMessageIds.length} 條消息嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                final updatedMessages =
                    List<chat_msg.Message>.from(_messagesNotifier.value)
                      ..removeWhere((m) => _selectedMessageIds.contains(m.id));
                _messagesNotifier.value = updatedMessages;
                _selectedMessageIds.clear();
                _isSelectionMode = false;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('消息已刪除'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 🔥 新增：轉發選中的消息
  void _forwardSelectedMessages() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('轉發 ${_selectedMessageIds.length} 條消息（功能開發中）'),
      ),
    );
  }

  // 🔥 新增：分享選中的消息
  void _shareSelectedMessages() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('分享 ${_selectedMessageIds.length} 條消息（功能開發中）'),
      ),
    );
  }

  // 🔥 新增：处理媒体选择和发送 (图片/视频)
  Future<void> _handleMediaSelected(File file, String type) async {
    try {
      if (type == 'image') {
        await chatService.sendImageMessage(currentRoomId, file.path);
      } else if (type == 'video') {
        await chatService.sendVideoMessage(currentRoomId, file.path);
      }
    } catch (e) {
      debugPrint('發送媒體失敗: $e');
      if (mounted) {
        // 🔥 忽略 401 錯誤
        if (e.toString().contains('401') ||
            e.toString().contains('Unauthorized')) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發送失敗: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectionMode
          ? ChatSelectionAppBar(
              selectedCount: _selectedMessageIds.length,
              onCancel: _toggleSelectionMode,
              onSelectAll: _selectAll,
              onDelete: _deleteSelectedMessages,
              onForward: _forwardSelectedMessages,
            ) as PreferredSizeWidget
          : ChatAppBar(
              chatDisplayName: _chatDisplayName,
              isConnected: _isConnected,
              chatRoom: widget.chatRoom,
              currentUserId: _currentUserId,
              typingStatus: _typingUsers.isNotEmpty
                  ? '${_typingUsers.join(", ")} 正在輸入...'
                  : null,
              isBlocked: _isBlocked,
              onToggleBlock: widget.chatRoom.isGroup ? null : _toggleBlockUser,
              onShowDebugInfo: () => showDebugInfoDialog(
                context: context,
                isConnected: _isConnected,
                messageCount: _messagesNotifier.value.length,
                currentUserId: _currentUserId,
                currentRoomId: widget.chatRoom.id,
                knownMessageIdsCount: _knownMessageIds.length,
              ),
              onShowGroupInfo: () {
                if (widget.chatRoom.isGroup) {
                  showGroupInfoDialog(context, widget.chatRoom);
                } else {
                  showUserInfoDialog(
                    context: context,
                    chatRoom: widget.chatRoom,
                    currentUserId: _currentUserId,
                    isBlocked: _isBlocked,
                    onToggleBlock: _toggleBlockUser,
                  );
                }
              },
            ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ValueListenableBuilder<List<chat_msg.Message>>(
                    valueListenable: _messagesNotifier,
                    builder: (context, messageList, _) {
                      return ChatMessageList(
                        messages: messageList,
                        currentUserId: _currentUserId ?? '',
                        isGroup: widget.chatRoom.isGroup,
                        currentUserName: _currentUserName,
                        fadeAnimation: _fadeAnimation,
                        onLoadMore: () {
                          if (mounted) loadMoreMessages();
                        },
                        isLoadingMore: _isLoadingMoreMessages,
                        hasMoreMessages: _hasMoreMessages,
                        hasLoadingError: _hasLoadingError,
                        onRetryLoad: () async {
                          if (mounted) setState(() => _isLoading = true);
                          await forceReloadMessages();
                          if (mounted) setState(() => _isLoading = false);
                        },
                        onDeleteMessage: (message) {
                          deleteMessage(message);
                        },
                        onReactionAdded: (message, emoji) {
                          toggleReaction(message, emoji);
                        },
                        isSelectionMode: _isSelectionMode,
                        selectedMessageIds: _selectedMessageIds,
                        onMessageTap: (message) {
                          if (_isSelectionMode) {
                            _toggleMessageSelection(message.id);
                          }
                        },
                        onEnterSelectionMode: _toggleSelectionMode,
                      );
                    },
                  ),
          ),
          // 🔥 多選模式時顯示底部操作欄，否則顯示輸入框或封鎖提示
          if (_isSelectionMode)
            ChatSelectionBottomBar(
              selectedCount: _selectedMessageIds.length,
              onDelete: _deleteSelectedMessages,
              onShare: _shareSelectedMessages,
              onForward: _forwardSelectedMessages,
            )
          else if (_isBlocked)
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Text(
                  '您已封鎖此用戶',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else
            ChatInputArea(
              messageController: _messageController,
              messageFocusNode: _messageFocusNode,
              isConnected: _isConnected,
              isRecordingVoice: _isRecordingVoice,
              onSendMessage: _sendMessage,
              onTextChanged: (text) {
                if (mounted) setState(() => _isTyping = text.isNotEmpty);
              },
              onVoiceRecordingComplete: _handleVoiceRecordingComplete,
              onVoiceRecordingCancelled: () => debugPrint('語音錄製已取消'),
              onVoiceRecordingStateChanged: (isRecording) {
                if (mounted) setState(() => _isRecordingVoice = isRecording);
              },
              onMediaSelected: _handleMediaSelected, // 🔥 连接回调
              onTypingStart: () =>
                  chatService.sendTypingStart(widget.chatRoom.id),
              onTypingEnd: () => chatService.sendTypingEnd(widget.chatRoom.id),
            ),
        ],
      ),
    );
  }
}
