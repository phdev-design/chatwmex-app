import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import '../models/chat_room.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/chat_api_service.dart' as api_service;
import '../services/background_sync_service.dart';
import '../services/notification_service.dart';
import '../utils/token_storage.dart';
import '../config/version_config.dart';
import 'chat_detail_page/chat_detail_page.dart';
import 'profile_page.dart';
import '../services/app_lifecycle_service.dart';

class ChatRoomsPage extends StatefulWidget {
  final User? currentUser;

  const ChatRoomsPage({super.key, this.currentUser});

  @override
  State<ChatRoomsPage> createState() => _ChatRoomsPageState();
}

class _ChatRoomsPageState extends State<ChatRoomsPage>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final List<ChatRoom> _chatRooms = [];
  final List<ChatRoom> _filteredChatRooms = [];
  final ChatService _chatService = ChatService();
  final NotificationService _notificationService = NotificationService();

  bool _isLoading = true;
  bool _isConnected = false;
  String? _currentUserId;
  String? _currentUsername;
  Timer? _refreshTimer;
  String? _lastVisitedRoomId;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // 資源追蹤
  final List<StreamSubscription> _subscriptions = [];
  bool _isDisposed = false;

  // 🔥 修正：將 _joinedRooms 的定義移至 class 頂部，解決變數未定義的問題
  final Set<String> _joinedRooms = <String>{};

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _initializeApp();
    _animationController.forward();
    _chatService.setCurrentActiveChatRoom(null);
    _startBackgroundSync();
  }

  @override
  void dispose() {
    // 設置標記，防止異步操作在 dispose 後執行
    _isDisposed = true;

    // 1. 清理動畫控制器
    _animationController.dispose();

    // 2. 清理文字控制器
    _searchController.dispose();

    // 3. 取消所有 Timer
    _refreshTimer?.cancel();
    _refreshTimer = null;

    // 4. 清理聊天服務監聽器
    _chatService.unregisterConnectionListener('chat_rooms_page');
    _chatService.unregisterMessageListener('chat_rooms_page');

    // 5. 清理已加入的聊天室記錄
    _cleanupJoinedRooms();

    // 6. 取消所有 Stream 訂閱
    _cancelAllSubscriptions();

    // 7. 清理通知服務的聊天室引用
    _notificationService.clearAllNotifications();

    // 8. 停止背景同步（如果只有這個頁面在使用）
    _stopBackgroundSyncIfNeeded();

    super.dispose();
  }

  // 清理已加入的聊天室
  void _cleanupJoinedRooms() {
    // 從聊天服務中離開所有聊天室
    for (final roomId in _joinedRooms) {
      _chatService.leaveRoom(roomId);
    }

    // 清空 Set
    _joinedRooms.clear();
  }

  // 取消所有訂閱
  void _cancelAllSubscriptions() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  // 如果需要，停止背景同步
  void _stopBackgroundSyncIfNeeded() {
    try {} catch (e) {}
  }

  // 安全的狀態更新方法，防止在已銷毀的 Widget 上調用 setState
  void _safeSetState(VoidCallback callback) {
    if (!_isDisposed && mounted) {
      setState(callback);
    }
  }

  // 訂閱服務的 Stream（如果有的話）
  void _subscribeToServices() {
    // 這裡可以添加需要監聽的 Stream，例如網路狀態
    // final networkSubscription = NetworkMonitorService().onNetworkChange.listen((isConnected) { ... });
    // _subscriptions.add(networkSubscription);
  }

  // 🔥 新增：顯示權限被永久拒絕的對話框
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 用戶必須做出選擇
      builder: (context) => AlertDialog(
        title: const Text('需要通知權限'),
        content: const Text('為了讓您及時收到新消息通知，請在設置中開啟通知權限。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('暫不開啟', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _notificationService.openAppSettings();
            },
            child: const Text('前往設置'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeApp() async {
    try {
      // 初始化通知服務
      await _notificationService.initialize();

      // 🔥 改進權限檢查邏輯
      var status = await Permission.notification.status;

      if (status.isGranted) {
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          _showPermissionDeniedDialog();
        }
      } else {
        // 其他狀態（如 denied, restricted），嘗試請求權限
        status = await _notificationService.requestNotificationPermission();

        if (status.isPermanentlyDenied) {
          if (mounted) {
            _showPermissionDeniedDialog();
          }
        }
      }

      final userInfo = await TokenStorage.getUser();
      if (mounted) {
        setState(() {
          _currentUserId = userInfo?['id']?.toString();
          _currentUsername = userInfo?['username']?.toString();
        });
      }

      _setupChatServiceCallbacks();

      if (!_chatService.isConnected) {
        await _chatService.initialize();
      } else {
        _onConnectionChanged(true);
      }

      await _loadChatRooms();

      _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
        if (!_isConnected) {
          _loadChatRooms();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('初始化失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 啟動背景同步
  Future<void> _startBackgroundSync() async {
    try {
      await BackgroundSyncService().startBackgroundSync();
    } catch (e) {}
  }

  // 🔥 修正：合併重複的函數定義，並確保先清理舊監聽器，防止重複註冊
  void _setupChatServiceCallbacks() {
    // 先清理舊的監聽器
    _chatService.unregisterConnectionListener('chat_rooms_page');
    _chatService.unregisterMessageListener('chat_rooms_page');

    // 註冊新的監聽器
    _chatService.registerConnectionListener(
        'chat_rooms_page', _onConnectionChanged);
    _chatService.registerMessageListener(
        'chat_rooms_page', _onNewMessageReceived);

    _subscribeToServices();
    _joinAllChatRooms();
  }

  // 改進的聊天室加入邏輯，避免重複加入
  void _joinAllChatRooms() {
    if (_isDisposed || !_chatService.isConnected) {
      return;
    }

    if (_chatService.isConnected) {
      for (final room in _chatRooms) {
        if (!_joinedRooms.contains(room.id)) {
          _chatService.joinRoom(room.id);
          _joinedRooms.add(room.id);
        }
      }
    } else {
      Timer(const Duration(seconds: 2), () {
        if (!_isDisposed && _chatService.isConnected) {
          _joinAllChatRooms();
        }
      });
    }
  }

  // 🔥 修正：提取消息更新邏輯為獨立方法，避免在 _onNewMessageReceived 中產生重複代碼
  void _updateRoomWithNewMessage(int roomIndex, Message message) {
    final currentRoom = _chatRooms[roomIndex];
    String expectedDisplayContent = message.content;
    if (message.type == 'voice') {
      expectedDisplayContent = '[語音消息]';
    }

    // 檢查是否為重複消息
    if (currentRoom.lastMessage == expectedDisplayContent &&
        currentRoom.lastMessageTime.isAtSameMomentAs(message.timestamp)) {
      return;
    }

    String displayContent = message.content;
    if (message.type == 'voice') {
      displayContent = '[語音消息]';
    }

    final updatedRoom = currentRoom.copyWith(
      lastMessage: displayContent,
      lastMessageTime: message.timestamp,
      unreadCount: _isMyMessage(message)
          ? currentRoom.unreadCount
          : currentRoom.unreadCount + 1,
    );

    _chatRooms.removeAt(roomIndex);
    _chatRooms.insert(0, updatedRoom);
    _filterChatRooms(_searchController.text);
  }

  // 🔥 修正：改進消息接收處理流程，移除重複的 setState 調用
  void _onNewMessageReceived(Message message) {
    if (_isDisposed || !mounted) {
      return;
    }

    if (message.id.isEmpty || message.content.isEmpty) {
      return;
    }

    // 🔥 修復：確保聊天室名稱映射是最新的
    _chatService.updateChatRoomNames(_chatRooms);

    // 使用安全的狀態更新，並將所有 UI 變更集中在此
    _safeSetState(() {
      final roomIndex =
          _chatRooms.indexWhere((room) => room.id == message.roomId);
      if (roomIndex != -1) {
        _updateRoomWithNewMessage(roomIndex, message);
      } else {
        _loadChatRooms();
      }
    });

    // 在狀態更新之外處理通知
    if (!_isMyMessage(message)) {
      _showNewMessageNotification(message);
    }
  }

  bool _isMyMessage(Message message) {
    return _currentUserId != null && message.senderId == _currentUserId;
  }

  // 顯示新消息通知
  Future<void> _showNewMessageNotification(Message message) async {
    try {
      final roomIndex =
          _chatRooms.indexWhere((room) => room.id == message.roomId);
      String chatRoomName = '聊天室';

      if (roomIndex != -1) {
        chatRoomName = _chatRooms[roomIndex].name;
      } else {
        chatRoomName =
            message.senderName.isNotEmpty ? message.senderName : '未知聊天室';
      }

      await _notificationService.showChatNotification(
        message: message,
        chatRoomName: chatRoomName,
      );
    } catch (e) {}
  }

  // 🔥 修正：改進的載入聊天室方法，添加異步安全檢查
  Future<void> _loadChatRooms() async {
    if (_isDisposed || !mounted) {
      return;
    }

    if (_chatRooms.isEmpty) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final rooms = await api_service.ChatApiService.getChatRooms();

      if (_isDisposed || !mounted) return;

      final processedRooms = await _processRoomNames(rooms);

      if (_isDisposed || !mounted) return;

      final updatedRooms = <ChatRoom>[];
      for (final room in processedRooms) {
        if (_isDisposed || !mounted) return;

        try {
          final messages = await api_service.ChatApiService.getChatHistory(
              room.id,
              limit: 1);

          if (_isDisposed || !mounted) return;

          if (messages.isNotEmpty) {
            final lastMessage = messages.first;
            String displayContent = lastMessage.content;
            if (lastMessage.type == 'voice') {
              displayContent = '[語音消息]';
            }
            updatedRooms.add(room.copyWith(
              lastMessage: displayContent,
              lastMessageTime: lastMessage.timestamp,
            ));
          } else {
            updatedRooms.add(room);
          }
        } catch (e) {
          updatedRooms.add(room);
        }
      }

      if (mounted && !_isDisposed) {
        setState(() {
          _chatRooms.clear();
          _chatRooms.addAll(updatedRooms.map((r) {
            if (_lastVisitedRoomId != null && r.id == _lastVisitedRoomId) {
              return r.copyWith(unreadCount: 0);
            }
            return r;
          }).toList());
          _filterChatRooms(_searchController.text);
          _isLoading = false;
        });

        _chatService.updateChatRoomNames(_chatRooms);

        if (_chatService.isConnected) {
          Timer(const Duration(milliseconds: 500), () {
            if (mounted && _chatService.isConnected && !_isDisposed) {
              _joinAllChatRooms();
            }
          });
        }
        _lastVisitedRoomId = null;
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isLoading = false;
        });

        // 🔥 忽略 401 錯誤，因為 ApiClientService 會處理登出邏輯
        if (e.toString().contains('401') ||
            e.toString().contains('Unauthorized')) {
          return;
        }

        if (e.toString().contains('SocketException') ||
            e.toString().contains('NetworkException') ||
            e.toString().contains('timeout')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('網路連接失敗: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('載入聊天室失敗: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<List<ChatRoom>> _processRoomNames(List<ChatRoom> rooms) async {
    if (_currentUserId == null || _currentUsername == null) {
      return rooms;
    }
    List<Future<ChatRoom>> correctionFutures = [];
    List<ChatRoom> correctRooms = [];
    for (final room in rooms) {
      if (!room.isGroup &&
          room.name == _currentUsername &&
          room.participants.length >= 2) {
        correctionFutures.add(_getCorrectedRoom(room, _currentUserId!));
      } else {
        correctRooms.add(room);
      }
    }
    if (correctionFutures.isNotEmpty) {
      final correctedRooms = await Future.wait(correctionFutures);
      return [...correctRooms, ...correctedRooms];
    } else {
      return correctRooms;
    }
  }

  Future<ChatRoom> _getCorrectedRoom(
      ChatRoom room, String currentUserId) async {
    try {
      final messages =
          await api_service.ChatApiService.getChatHistory(room.id, limit: 5);
      final otherUserMessage = messages.firstWhere(
        (msg) => msg.senderId != currentUserId,
        orElse: () => Message(
            id: '',
            senderId: '',
            senderName: '',
            content: '',
            timestamp: DateTime.now(),
            roomId: ''),
      );
      if (otherUserMessage.senderName.isNotEmpty) {
        return room.copyWith(name: otherUserMessage.senderName);
      }
    } catch (e) {}
    return room;
  }

  void _onConnectionChanged(bool isConnected) {
    if (mounted && !_isDisposed) {
      setState(() {
        _isConnected = isConnected;
      });
      if (isConnected && _chatRooms.isNotEmpty) {
        _joinAllChatRooms();
      }
    }
  }

  void _filterChatRooms(String query) {
    if (_isDisposed || !mounted) return;

    setState(() {
      if (query.isEmpty) {
        _filteredChatRooms.clear();
        _filteredChatRooms.addAll(_chatRooms);
      } else {
        _filteredChatRooms.clear();
        _filteredChatRooms.addAll(
          _chatRooms.where(
            (room) =>
                room.name.toLowerCase().contains(query.toLowerCase()) ||
                room.lastMessage.toLowerCase().contains(query.toLowerCase()),
          ),
        );
      }
      _filteredChatRooms
          .sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    });
  }

  void _markRoomAsRead(String roomId) {
    if (!mounted || _isDisposed) return;
    setState(() {
      final roomIndex = _chatRooms.indexWhere((room) => room.id == roomId);
      if (roomIndex != -1) {
        _chatRooms[roomIndex] = _chatRooms[roomIndex].copyWith(unreadCount: 0);
        _filterChatRooms(_searchController.text);
      }
    });
    api_service.ChatApiService.markAsRead(roomId);
  }

  void _openTraditionalChatPage(ChatRoom room) {
    _markRoomAsRead(room.id);
    _notificationService.clearChatNotifications(room.id);

    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => ChatDetailPage(chatRoom: room),
      ),
    ).then((_) {
      _lastVisitedRoomId = room.id;
      _loadChatRooms();
      _chatService.setCurrentActiveChatRoom(null);
    });
  }

  // --- Widgets ---

  Widget _buildConnectionStatus() {
    if (_isConnected) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(
            Icons.wifi_off,
            size: 16,
            color: Colors.orange[700],
          ),
          const SizedBox(width: 8),
          Text(
            '離線模式',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange[700],
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 16),
                      Text('正在重新連接...'),
                    ],
                  ),
                  duration: Duration(seconds: 3),
                ),
              );

              try {
                await AppLifecycleService().manualRecover();
                await _loadChatRooms();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('重新連接成功'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('重新連接失敗: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: Icon(
              Icons.refresh,
              size: 16,
              color: Colors.orange[700],
            ),
            tooltip: '重新連接',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _filterChatRooms,
        decoration: InputDecoration(
          hintText: '搜尋聊天室或訊息',
          prefixIcon: Icon(
            Icons.search,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _filterChatRooms('');
                  },
                  icon: const Icon(Icons.clear),
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  Widget _buildChatRoomTile(ChatRoom room, int index) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, 0.3 + (index * 0.1)),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            (index * 0.1).clamp(0.0, 0.8),
            1.0,
            curve: Curves.easeOut,
          ),
        )),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: room.unreadCount > 0
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openTraditionalChatPage(room),
              onLongPress: () {
                _showRoomOptions(room);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _getAvatarColor(room.name),
                          ),
                          child: Center(
                            child: Text(
                              _getAvatarText(room.name),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (room.isGroup)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.surface,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.group,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  room.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: room.unreadCount > 0
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                _formatTime(room.lastMessageTime),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: room.unreadCount > 0
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.6),
                                      fontWeight: room.unreadCount > 0
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  room.lastMessage,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: room.unreadCount > 0
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.8),
                                        fontWeight: room.unreadCount > 0
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (room.unreadCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    room.unreadCount > 99
                                        ? '99+'
                                        : room.unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showRoomOptions(ChatRoom room) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.mark_chat_read),
              title: const Text('標記為已讀'),
              onTap: () {
                Navigator.pop(context);
                api_service.ChatApiService.markAsRead(room.id);
                _markRoomAsRead(room.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off),
              title: const Text('靜音通知'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('靜音功能開發中...')),
                );
              },
            ),
            if (room.isGroup)
              ListTile(
                leading: Icon(Icons.exit_to_app, color: Colors.red[600]),
                title: Text('離開群組', style: TextStyle(color: Colors.red[600])),
                onTap: () {
                  Navigator.pop(context);
                  _confirmLeaveRoom(room);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _confirmLeaveRoom(ChatRoom room) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('離開聊天室'),
        content: Text('您確定要離開「${room.name}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await api_service.ChatApiService.leaveRoom(room.id);
                _loadChatRooms();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已離開聊天室')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('離開失敗: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('離開'),
          ),
        ],
      ),
    );
  }

  String _getAvatarText(String name) {
    if (name.isEmpty) return '?';
    if (name.contains('@')) {
      return name.substring(0, 1).toUpperCase();
    }
    final words = name.split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF10B981), // Emerald
      const Color(0xFFF59E0B), // Amber
      const Color(0xFFEF4444), // Red
      const Color(0xFF3B82F6), // Blue
      const Color(0xFF84CC16), // Lime
    ];
    return colors[name.hashCode % colors.length];
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 365) {
      return '${time.year}年${time.month}月${time.day}日';
    } else if (difference.inDays > 0) {
      return '${time.month}月${time.day}日';
    } else if (now.day != time.day) {
      return '昨天';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  void _showAppOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('設定'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfilePage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('關於'),
              onTap: () {
                Navigator.pop(context);
                showAboutDialog(
                  context: context,
                  applicationName: VersionConfig.appName,
                  applicationVersion: VersionConfig.version,
                  applicationIcon: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.chat_bubble,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                _isConnected ? Icons.wifi : Icons.wifi_off,
                color: _isConnected ? Colors.green : Colors.red,
              ),
              title: Text('連接狀態: ${_isConnected ? "已連接" : "未連接"}'),
              subtitle: Text(_chatService.getConnectionStats().toString()),
              onTap: () {
                Navigator.pop(context);
                if (!_isConnected) {
                  _chatService.reconnect();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateChatDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '新增聊天',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.person_add,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                '開始私人聊天',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                '與單一用戶聊天',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () {
                Navigator.pop(context);
                _showStartPrivateChat();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.group_add,
                color: Theme.of(context).colorScheme.secondary,
              ),
              title: Text(
                '建立群組',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                '建立多人聊天群組',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              onTap: () {
                Navigator.pop(context);
                _showCreateGroup();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showStartPrivateChat() {
    final searchController = TextEditingController();
    List<User> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setBottomSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '開始私人聊天',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: '搜尋用戶名或 Email',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (query) async {
                    if (query.length >= 2) {
                      setBottomSheetState(() {
                        isSearching = true;
                      });

                      try {
                        final users =
                            await api_service.ChatApiService.searchUsers(query);
                        setBottomSheetState(() {
                          searchResults = users
                              .where((user) => user.id != _currentUserId)
                              .toList();
                          isSearching = false;
                        });
                      } catch (e) {
                        setBottomSheetState(() {
                          isSearching = false;
                        });
                      }
                    } else {
                      setBottomSheetState(() {
                        searchResults.clear();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : searchResults.isEmpty
                        ? const Center(
                            child: Text('輸入用戶名搜索用戶'),
                          )
                        : ListView.builder(
                            itemCount: searchResults.length,
                            itemBuilder: (context, index) {
                              final user = searchResults[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      _getAvatarColor(user.username),
                                  child: Text(
                                    user.initials,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(user.username),
                                subtitle: Text(user.email),
                                onTap: () async {
                                  Navigator.pop(context);
                                  await _createPrivateChat(user);
                                },
                              );
                            },
                          ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 🔥 修正：完成 _showCreateGroup 函數的 UI 和邏輯
  void _showCreateGroup() {
    final nameController = TextEditingController();
    final searchController = TextEditingController();
    List<User> selectedMembers = [];
    List<User> searchResults = [];
    bool isSearching = false;
    Timer? _debounce;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setBottomSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '建立群組',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '群組名稱',
                        prefixIcon: Icon(Icons.group),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        hintText: '搜尋用戶以邀請',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (query) {
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce =
                            Timer(const Duration(milliseconds: 500), () async {
                          if (query.length >= 2) {
                            setBottomSheetState(() {
                              isSearching = true;
                            });
                            try {
                              final users =
                                  await api_service.ChatApiService.searchUsers(
                                      query);
                              setBottomSheetState(() {
                                searchResults = users
                                    .where((user) =>
                                        user.id != _currentUserId &&
                                        !selectedMembers
                                            .any((m) => m.id == user.id))
                                    .toList();
                                isSearching = false;
                              });
                            } catch (e) {
                              setBottomSheetState(() {
                                isSearching = false;
                              });
                            }
                          } else {
                            setBottomSheetState(() {
                              searchResults.clear();
                            });
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              if (selectedMembers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedMembers.length,
                      itemBuilder: (context, index) {
                        final member = selectedMembers[index];
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text(member.username),
                            avatar: CircleAvatar(
                              backgroundColor: _getAvatarColor(member.username),
                              child: Text(member.initials,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ),
                            onDeleted: () {
                              setBottomSheetState(() {
                                selectedMembers.removeAt(index);
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              Expanded(
                child: isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final user = searchResults[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getAvatarColor(user.username),
                              child: Text(user.initials,
                                  style: const TextStyle(color: Colors.white)),
                            ),
                            title: Text(user.username),
                            subtitle: Text(user.email),
                            onTap: () {
                              setBottomSheetState(() {
                                selectedMembers.add(user);
                                searchResults.removeAt(index);
                              });
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () {
                      final name = nameController.text.trim();
                      if (name.isNotEmpty && selectedMembers.isNotEmpty) {
                        Navigator.pop(context);
                        _createGroupWithMembers(name, selectedMembers);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('請輸入群組名稱並至少選擇一位成員')),
                        );
                      }
                    },
                    child: const Text('建立群組'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createPrivateChat(User user) async {
    try {
      final room = await api_service.ChatApiService.createChatRoom(
        name: user.username,
        participants: [user.id],
        isGroup: false,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(chatRoom: room),
          ),
        ).then((_) => _loadChatRooms());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('建立聊天失敗: $e')),
        );
      }
    }
  }

  Future<void> _createGroupWithMembers(String name, List<User> members) async {
    try {
      final room = await api_service.ChatApiService.createChatRoom(
        name: name,
        participants: members.map((user) => user.id).toList(),
        isGroup: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('群組「$name」建立成功'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailPage(chatRoom: room),
          ),
        ).then((_) => _loadChatRooms());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('建立群組失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('所有聊天'),
            if (_isConnected) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Text(
              _currentUsername?.isNotEmpty == true
                  ? _currentUsername![0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfilePage(),
                ),
              );
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () {
              _showAppOptions();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildConnectionStatus(),
          _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadChatRooms,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredChatRooms.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isNotEmpty
                                    ? '找不到相關聊天室'
                                    : '還沒有聊天室',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                              ),
                              if (_searchController.text.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '點擊右下角按鈕開始聊天',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredChatRooms.length,
                          itemBuilder: (context, index) {
                            return _buildChatRoomTile(
                                _filteredChatRooms[index], index);
                          },
                        ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showCreateChatDialog();
        },
        child: const Icon(Icons.edit),
      ),
    );
  }
}
