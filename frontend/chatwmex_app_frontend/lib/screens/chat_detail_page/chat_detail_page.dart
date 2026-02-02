// lib/screens/chat_detail_page/chat_detail_page.dart (完全修正版)
import 'package:flutter/material.dart';
import '../../models/chat_room.dart';
import '../../models/message.dart' as chat_msg;
import '../../models/voice_message.dart' as voice_msg;
import '../../services/chat_service.dart';
import '../../services/chat_api_service.dart' as api_service;
import '../../utils/token_storage.dart';

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
  final List<chat_msg.Message> _messages = [];
  final Set<String> _knownMessageIds = {};
  final Set<String> _pendingTempMessages = {};
  
  // 🔥 新增：多選模式相關
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = {};

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

  // === 動畫 ===
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // === Mixin Getters ===
  @override
  List<chat_msg.Message> get messages => _messages;
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
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(value);
      });
    }
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

    disposeAudioHandler();
    disposeLifecycleHandler();
    cleanupMessageState();

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
      final userInfo = await TokenStorage.getUser();
      if (mounted) {
        setState(() {
          _currentUserId = userInfo?['id']?.toString();
          _currentUserName = userInfo?['username']?.toString() ?? '我';
        });
      }

      chatService.registerMessageListener(
          'chat_detail_page', _onMessageReceived);
      chatService.registerConnectionListener(
          'chat_detail_page', _onConnectionChanged);

      if (!chatService.isConnected) {
        await chatService.initialize();
      } else {
        _onConnectionChanged(true);
      }

      chatService.joinRoom(widget.chatRoom.id);
      await loadChatHistoryWithFallback();
      api_service.ChatApiService.markAsRead(widget.chatRoom.id);
    } catch (e) {
      debugPrint('初始化聊天時出錯: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('聊天初始化失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onMessageReceived(chat_msg.Message message) {
    if (!mounted) return;
    setState(() {
      handleNewMessageReceived(message);
    });
    if (_messages.isNotEmpty) {
      playNotificationSound(_messages.first);
    }
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
  }

  void _handleAppPause() {
    debugPrint("App Paused");
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      sendTextMessage(content);
    });
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

    setState(() {
      sendVoiceMessage(filePath, durationSeconds);
    });
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
      _selectedMessageIds.addAll(_messages.map((m) => m.id));
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
                _messages.removeWhere((m) => _selectedMessageIds.contains(m.id));
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
              onShowDebugInfo: () => showDebugInfoDialog(
                context: context,
                isConnected: _isConnected,
                messageCount: _messages.length,
                currentUserId: _currentUserId,
                currentRoomId: currentRoomId,
                knownMessageIdsCount: _knownMessageIds.length,
              ),
              onShowGroupInfo: () => showGroupInfoDialog(context, widget.chatRoom),
            ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ChatMessageList(
                    messages: _messages,
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
                      setState(() {
                        deleteMessage(message);
                      });
                    },
                    onReactionAdded: (message, emoji) {
                      setState(() {
                        toggleReaction(message, emoji);
                      });
                    },
                    // 🔥 新增：多選模式相關參數
                    isSelectionMode: _isSelectionMode,
                    selectedMessageIds: _selectedMessageIds,
                    onMessageTap: (message) {
                      if (_isSelectionMode) {
                        _toggleMessageSelection(message.id);
                      }
                    },
                    onEnterSelectionMode: _toggleSelectionMode,
                  ),
          ),
          // 🔥 多選模式時顯示底部操作欄，否則顯示輸入框
          if (_isSelectionMode)
            ChatSelectionBottomBar(
              selectedCount: _selectedMessageIds.length,
              onDelete: _deleteSelectedMessages,
              onShare: _shareSelectedMessages,
              onForward: _forwardSelectedMessages,
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
            ),
        ],
      ),
    );
  }
}