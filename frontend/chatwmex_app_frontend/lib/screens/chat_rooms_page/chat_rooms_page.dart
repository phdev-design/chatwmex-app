import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:async';

// Local Imports
import 'dialogs/app_options_dialog.dart';
import 'dialogs/create_chat_dialogs.dart';
import 'dialogs/room_options_dialogs.dart';
import 'widgets/connection_status_bar.dart';
import 'widgets/search_bar.dart';
import 'widgets/chat_room_list_view.dart';

// Project-level Imports
import '../../models/chat_room.dart';
import '../../models/user.dart';
import '../../models/message.dart';
import '../../services/chat_service.dart';
import '../../services/chat_api_service.dart' as api_service;
import '../../services/background_sync_service.dart';
import '../../services/notification_service.dart';
import '../../utils/token_storage.dart';
import '../chat_detail_page/chat_detail_page.dart';
import '../profile_page.dart';
import '../../services/app_lifecycle_service.dart';

class ChatRoomsPage extends StatefulWidget {
  final User? currentUser;
  const ChatRoomsPage({super.key, this.currentUser});

  @override
  State<ChatRoomsPage> createState() => _ChatRoomsPageState();
}

class _ChatRoomsPageState extends State<ChatRoomsPage> with TickerProviderStateMixin {
  // Controllers and Services
  final _searchController = TextEditingController();
  final _chatService = ChatService();
  final _notificationService = NotificationService();

  // State Variables
  final List<ChatRoom> _chatRooms = [];
  final List<ChatRoom> _filteredChatRooms = [];
  final Set<String> _joinedRooms = <String>{};
  
  bool _isLoading = true;
  bool _isConnected = false;
  String? _currentUserId;
  String? _currentUsername;
  Timer? _refreshTimer;
  String? _lastVisitedRoomId;
  bool _isDisposed = false;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _initializeApp();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _animationController.dispose();
    _searchController.dispose();
    _refreshTimer?.cancel();
    _chatService.unregisterConnectionListener('chat_rooms_page');
    _chatService.unregisterMessageListener('chat_rooms_page');
    _cleanupJoinedRooms();
    _notificationService.clearAllNotifications();
    super.dispose();
  }

  // --- Core Logic ---
  Future<void> _initializeApp() async {
    try {
      await _notificationService.initialize();
      await _notificationService.requestNotificationPermission();

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
      _animationController.forward();

      _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (!_isConnected) {
          _loadChatRooms();
        }
      });
      await BackgroundSyncService().startBackgroundSync();
    } catch (e) {
      print('Error initializing app: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _setupChatServiceCallbacks() {
    _chatService.unregisterConnectionListener('chat_rooms_page');
    _chatService.unregisterMessageListener('chat_rooms_page');
    
    _chatService.registerConnectionListener('chat_rooms_page', _onConnectionChanged);
    _chatService.registerMessageListener('chat_rooms_page', _onNewMessageReceived);
  }

  Future<void> _loadChatRooms() async {
    if (_isDisposed || !mounted) return;
    
    if (_chatRooms.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final rooms = await api_service.ChatApiService.getChatRooms();
      if (_isDisposed || !mounted) return;
      
      final processedRooms = await _processRoomNames(rooms);
      if (_isDisposed || !mounted) return;

      final updatedRooms = await _fetchLastMessages(processedRooms);

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
      print('Error loading chat rooms: $e');
      if (mounted && !_isDisposed) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('載入聊天室失敗: $e'),
            backgroundColor: e.toString().contains('SocketException') || 
                           e.toString().contains('NetworkException') || 
                           e.toString().contains('timeout') 
                ? Colors.orange 
                : Colors.red,
          ),
        );
      }
    }
  }
  
  Future<List<ChatRoom>> _fetchLastMessages(List<ChatRoom> rooms) async {
    List<ChatRoom> updatedRooms = [];
    for (final room in rooms) {
      if (_isDisposed || !mounted) return updatedRooms;
      
      try {
        final messages = await api_service.ChatApiService.getChatHistory(room.id, limit: 1);
        if (_isDisposed || !mounted) return updatedRooms;
        
        if (messages.isNotEmpty) {
          final lastMessage = messages.first;
          String displayContent = lastMessage.type == 'voice' ? '[語音消息]' : lastMessage.content;
          updatedRooms.add(room.copyWith(
            lastMessage: displayContent, 
            lastMessageTime: lastMessage.timestamp
          ));
        } else {
          updatedRooms.add(room);
        }
      } catch (e) {
        print('獲取房間 ${room.id} 最後消息失敗: $e');
        updatedRooms.add(room);
      }
    }
    return updatedRooms;
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

  Future<ChatRoom> _getCorrectedRoom(ChatRoom room, String currentUserId) async {
    try {
      final messages = await api_service.ChatApiService.getChatHistory(room.id, limit: 5);
      final otherUserMessage = messages.firstWhere(
        (msg) => msg.senderId != currentUserId,
        orElse: () => Message(
          id: '',
          senderId: '',
          senderName: '',
          content: '',
          timestamp: DateTime.now(),
          roomId: '',
        ),
      );
      if (otherUserMessage.senderName.isNotEmpty) {
        return room.copyWith(name: otherUserMessage.senderName);
      }
    } catch (e) {
      print("Could not correct room name for ${room.id}: $e");
    }
    return room;
  }

  void _onConnectionChanged(bool isConnected) {
    if (mounted && !_isDisposed) {
      setState(() => _isConnected = isConnected);
      if (isConnected && _chatRooms.isNotEmpty) {
        _joinAllChatRooms();
      }
    }
  }
  
  void _onNewMessageReceived(Message message) {
    if (_isDisposed || !mounted) return;
    
    print('=== ChatRoomsPage 收到消息調試 ===');
    print('消息來源房間: ${message.roomId}, 發送者: ${message.senderName}');
    print('是否為自己的消息: ${_isMyMessage(message)}');
    print('================================');
    
    if (message.id.isEmpty || message.content.isEmpty) {
      print('ChatRoomsPage: 收到無效訊息，跳過');
      return;
    }

    _chatService.updateChatRoomNames(_chatRooms);
    
    _safeSetState(() {
      final roomIndex = _chatRooms.indexWhere((room) => room.id == message.roomId);
      if (roomIndex != -1) {
        final room = _chatRooms[roomIndex];
        String displayContent = message.type == 'voice' ? '[語音消息]' : message.content;
        
        // 檢查是否為重複消息
        if (room.lastMessage == displayContent &&
            room.lastMessageTime.isAtSameMomentAs(message.timestamp)) {
          print('ChatRoomsPage: 檢測到重複訊息，跳過');
          return;
        }
        
        final updatedRoom = room.copyWith(
          lastMessage: displayContent,
          lastMessageTime: message.timestamp,
          unreadCount: _isMyMessage(message) ? room.unreadCount : room.unreadCount + 1,
        );
        
        _chatRooms.removeAt(roomIndex);
        _chatRooms.insert(0, updatedRoom);
        _filterChatRooms(_searchController.text);
        
        print('ChatRoomsPage: 更新聊天室: ${updatedRoom.name}, 新消息: ${updatedRoom.lastMessage}, 未讀數: ${updatedRoom.unreadCount}');
      } else {
        print('ChatRoomsPage: 未找到對應聊天室 ${message.roomId}，重新載入列表');
        _loadChatRooms();
      }
    });

    if (!_isMyMessage(message)) {
      _showNewMessageNotification(message);
    }
  }

  bool _isMyMessage(Message message) => _currentUserId != null && message.senderId == _currentUserId;

  void _filterChatRooms(String query) {
    if (_isDisposed || !mounted) return;
    
    setState(() {
      _filteredChatRooms.clear();
      if (query.isEmpty) {
        _filteredChatRooms.addAll(_chatRooms);
      } else {
        _filteredChatRooms.addAll(_chatRooms.where((room) =>
            room.name.toLowerCase().contains(query.toLowerCase()) ||
            room.lastMessage.toLowerCase().contains(query.toLowerCase())));
      }
      _filteredChatRooms.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    });
  }

  // --- UI Actions & Navigation ---
  void _openChatDetail(ChatRoom room) {
    _handleMarkAsRead(room.id);
    _notificationService.clearChatNotifications(room.id);
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => ChatDetailPage(chatRoom: room)),
    ).then((_) {
      _lastVisitedRoomId = room.id;
      _loadChatRooms();
      _chatService.setCurrentActiveChatRoom(null);
    });
  }

  void _handleLeaveRoom(ChatRoom room) async {
    try {
      await api_service.ChatApiService.leaveRoom(room.id);
      await _loadChatRooms();
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
  }
  
  void _handleMarkAsRead(String roomId) {
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

  void _handleReconnect() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
      print('ChatRoomsPage: 手動恢復失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('重新連接失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Helper Methods ---
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }
  
  void _joinAllChatRooms() {
    if (_isDisposed || !_chatService.isConnected) {
      print('ChatRoomsPage: 頁面已銷毀或服務未連接，跳過加入聊天室');
      return;
    }
    
    if (_chatService.isConnected) {
      for (final room in _chatRooms) {
        if (!_joinedRooms.contains(room.id)) {
          _chatService.joinRoom(room.id);
          _joinedRooms.add(room.id);
          print('ChatRoomsPage: 加入聊天室 ${room.name} (${room.id})');
        }
      }
    } else {
      print('ChatRoomsPage: Socket 未連接，延遲加入聊天室');
      Timer(const Duration(seconds: 2), () {
        if (!_isDisposed && _chatService.isConnected) {
          _joinAllChatRooms();
        }
      });
    }
  }
  
  void _cleanupJoinedRooms() {
    print('ChatRoomsPage: 清理 ${_joinedRooms.length} 個已加入的聊天室');
    for (final roomId in _joinedRooms) {
      _chatService.leaveRoom(roomId);
    }
    _joinedRooms.clear();
    print('ChatRoomsPage: 聊天室清理完成');
  }

  void _showNewMessageNotification(Message message) async {
    try {
      final roomIndex = _chatRooms.indexWhere((room) => room.id == message.roomId);
      String chatRoomName = '聊天室';

      if (roomIndex != -1) {
        chatRoomName = _chatRooms[roomIndex].name;
      } else {
        chatRoomName = message.senderName.isNotEmpty ? message.senderName : '未知聊天室';
      }

      print('ChatRoomsPage: 準備顯示通知 - 來自 ${message.senderName} 在 $chatRoomName');
      print('ChatRoomsPage: 當前活躍聊天室: ${_notificationService.currentActiveChatRoom}');
      
      await _notificationService.showChatNotification(
        message: message,
        chatRoomName: chatRoomName,
      );
      print('ChatRoomsPage: 通知已顯示');
    } catch (e) {
      print('ChatRoomsPage: 顯示通知失敗: $e');
    }
  }

  // --- Widget Build Methods ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          ConnectionStatusBar(isConnected: _isConnected, onReconnect: _handleReconnect),
          SearchBarWidget(controller: _searchController, onChanged: _filterChatRooms),
          Expanded(
            child: ChatRoomListView(
              isLoading: _isLoading,
              rooms: _filteredChatRooms,
              searchQuery: _searchController.text,
              animationController: _animationController,
              onRefresh: _loadChatRooms,
              onRoomTap: _openChatDetail,
              onRoomLongPress: (room) => showRoomOptionsDialog(
                context,
                room,
                () => _handleMarkAsRead(room.id),
                () => _handleLeaveRoom(room),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCreateChatDialog(context, _currentUserId, (newRoom) {
          _loadChatRooms().then((_) => _openChatDetail(newRoom));
        }),
        child: const Icon(Icons.edit),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
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
              MaterialPageRoute(builder: (context) => const ProfilePage()),
            );
          },
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_horiz),
          onPressed: () => showAppOptionsDialog(
            context: context,
            isConnected: _isConnected,
            chatService: _chatService,
          ),
        ),
      ],
    );
  }
}