import 'package:flutter/material.dart';
import '../../../models/chat_room.dart';
import 'chat_room_tile.dart';

class ChatRoomListView extends StatelessWidget {
  final bool isLoading;
  final List<ChatRoom> rooms;
  final String searchQuery;
  final AnimationController animationController;
  final Function(ChatRoom) onRoomTap;
  final Function(ChatRoom) onRoomLongPress;
  final Future<void> Function() onRefresh;

  const ChatRoomListView({
    super.key,
    required this.isLoading,
    required this.rooms,
    required this.searchQuery,
    required this.animationController,
    required this.onRoomTap,
    required this.onRoomLongPress,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildLoadingState();
    }

    if (rooms.isEmpty) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: 40,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80), // 為 FAB 留出空間
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          return ChatRoomTile(
            room: room,
            onTap: () => onRoomTap(room),
            onLongPress: () => onRoomLongPress(room),
            animation: CurvedAnimation(
              parent: animationController,
              curve: Interval(
                (index * 0.1).clamp(0.0, 0.8), 
                1.0, 
                curve: Curves.easeOut,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('載入聊天室中...'),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isSearching = searchQuery.isNotEmpty;
    
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 圖標
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSearching ? Icons.search_off : Icons.chat_bubble_outline,
                      size: 40,
                      color: theme.colorScheme.primary.withOpacity(0.7),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // 主要文字
                  Text(
                    isSearching ? '找不到相關聊天室' : '還沒有聊天室',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // 副標題
                  Text(
                    isSearching 
                        ? '嘗試搜尋其他關鍵字' 
                        : '點擊右下角按鈕開始聊天',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  if (isSearching) ...[
                    const SizedBox(height: 16),
                    Text(
                      '搜尋建議：\n• 檢查拼寫是否正確\n• 嘗試使用較短的關鍵字\n• 搜尋用戶名或訊息內容',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    const SizedBox(height: 32),
                    // 引導按鈕
                    ElevatedButton.icon(
                      onPressed: () {
                        // 這裡可以觸發創建聊天的操作
                        // 通常會通過回調函數實現
                      },
                      icon: const Icon(Icons.add_comment),
                      label: const Text('開始第一個聊天'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24, 
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}