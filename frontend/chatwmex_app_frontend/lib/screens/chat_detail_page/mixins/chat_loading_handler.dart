// lib/screens/chat_detail_page/mixins/chat_loading_handler.dart
import 'package:flutter/material.dart';
import '../../../models/message.dart' as chat_msg;
import '../../../services/chat_api_service.dart' as api_service;
import '../../../services/message_cache_service.dart';
import '../../../services/database_helper.dart';

/// 處理消息載入、分頁、緩存等操作的 Mixin
mixin ChatLoadingHandler<T extends StatefulWidget> on State<T> {
  // --- 抽象屬性：需要由 State 提供 ---
  List<chat_msg.Message> get messages;
  Set<String> get knownMessageIds;
  String get currentRoomId;
  bool get hasMoreMessages;
  bool get isLoadingMoreMessages;
  int get currentPage;
  BuildContext get buildContext;

  // --- 抽象 Setter ---
  set messages(List<chat_msg.Message> value);
  set knownMessageIds(Set<String> value);
  set hasMoreMessages(bool value);
  set isLoadingMoreMessages(bool value);
  set currentPage(int value);
  set isNewChatRoom(bool value);
  set hasLoadingError(bool value);

  static const int messagesPerPage = 20;

  /// 使用緩存優先策略載入聊天記錄
  Future<void> loadChatHistoryWithFallback() async {
    if (!mounted) return;
    hasLoadingError = false;

    // 步驟 1: 從緩存快速載入以提供即時反饋
    final loadedFromCache = await _loadFromCache();

    // 步驟 2: 無論緩存是否存在，都從伺服器獲取最新數據
    try {
      final serverMessages = await api_service.ChatApiService.getChatHistory(
          currentRoomId,
          page: 1,
          limit: messagesPerPage);

      if (!mounted) return;

      // 🔥 修正：使用內部方法而不是直接 setState
      _replaceMessages(serverMessages);

      hasMoreMessages = serverMessages.length >= messagesPerPage;
      currentPage = 1;

      // 更新緩存
      await MessageCacheService().cacheRoomMessages(currentRoomId, messages);
    } catch (e) {
      debugPrint('從伺服器載入歷史記錄失敗: $e');
      if (mounted) {
        hasLoadingError = true;

        // 🔥 忽略 401 錯誤
        if (e.toString().contains('401') ||
            e.toString().contains('Unauthorized')) {
          return;
        }

        if (!loadedFromCache) {
          // 如果連緩存都沒有，才顯示錯誤
          ScaffoldMessenger.of(buildContext).showSnackBar(
            SnackBar(content: Text('載入失敗: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  /// 從緩存載入
  Future<bool> _loadFromCache() async {
    try {
      final cachedMessages =
          await MessageCacheService().getCachedRoomMessages(currentRoomId);
      if (cachedMessages.isNotEmpty && mounted) {
        _replaceMessages(cachedMessages);
        debugPrint('從緩存載入 ${cachedMessages.length} 條消息');
        return true;
      }
    } catch (e) {
      debugPrint('從緩存載入失敗: $e');
    }
    return false;
  }

  /// 載入更多歷史消息（分頁）
  Future<void> loadMoreMessages() async {
    if (isLoadingMoreMessages || !hasMoreMessages || !mounted) return;

    // 🔥 修正：通過 setter 觸發更新，由主 State 的 setter 處理 setState
    isLoadingMoreMessages = true;

    try {
      final nextPage = currentPage + 1;
      final moreMessages = await api_service.ChatApiService.getChatHistory(
        currentRoomId,
        page: nextPage,
        limit: messagesPerPage,
      );

      if (!mounted) return;

      if (moreMessages.isNotEmpty) {
        _appendMessages(moreMessages);
        currentPage = nextPage;
      }

      hasMoreMessages = moreMessages.length >= messagesPerPage;
    } catch (e) {
      debugPrint('載入更多訊息時出錯: $e');
      if (mounted) {
        // 🔥 忽略 401 錯誤
        if (e.toString().contains('401') ||
            e.toString().contains('Unauthorized')) {
          return;
        }

        ScaffoldMessenger.of(buildContext).showSnackBar(
          SnackBar(content: Text('載入更多失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        isLoadingMoreMessages = false;
      }
    }
  }

  /// 強制重新整理
  Future<void> forceReloadMessages() async {
    currentPage = 1;
    hasMoreMessages = true;
    isLoadingMoreMessages = false;
    await loadChatHistoryWithFallback();
  }

  /// 🔥 新增：替換消息列表（完全重置）
  void _replaceMessages(List<chat_msg.Message> newMessages) {
    if (!mounted) return;

    final updatedMessages = <chat_msg.Message>[];
    final updatedIds = <String>{};

    for (final message in newMessages) {
      if (updatedIds.add(message.id)) {
        updatedMessages.add(message);
      }
    }
    updatedMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // 通過 setter 觸發更新
    messages = updatedMessages;
    knownMessageIds = updatedIds;
  }

  /// 🔥 新增：追加消息到列表
  void _appendMessages(List<chat_msg.Message> newMessages) {
    if (!mounted) return;

    final currentMessages = List<chat_msg.Message>.from(messages);
    final currentIds = Set<String>.from(knownMessageIds);

    for (final message in newMessages) {
      if (currentIds.add(message.id)) {
        currentMessages.add(message);
      }
    }
    currentMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // 通過 setter 觸發更新
    messages = currentMessages;
    knownMessageIds = currentIds;
  }
}
