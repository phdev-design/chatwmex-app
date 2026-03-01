// lib/pages/chat/mixins/chat_message_handler.dart
import 'package:flutter/material.dart';
import 'dart:io'; // 🔥 新增：用于 File 类
import '../../../models/message.dart' as chat_msg;
import '../../../models/voice_message.dart'
    as voice_msg; // 🔥 新增：用于 VoiceMessage
import '../../../services/chat_service.dart';
import '../../../services/chat_api_service.dart' as api_service;
import '../../../services/voice_api_service.dart'; // 🔥 新增：用于 VoiceApiService

/// 處理消息接收、發送、刪除等操作的 Mixin
mixin ChatMessageHandler<T extends StatefulWidget> on State<T> {
  // 需要在使用此 Mixin 的 State 中實現這些 getter
  List<chat_msg.Message> get messages;
  Set<String> get knownMessageIds;
  Set<String> get pendingTempMessages;
  ChatService get chatService;
  String get currentRoomId;
  String? get currentUserId;
  String? get currentUserName;
  bool get isConnected;

  // 需要在使用此 Mixin 的 State 中實現這些 setter
  set messages(List<chat_msg.Message> value);
  set knownMessageIds(Set<String> value);
  set pendingTempMessages(Set<String> value);

  List<chat_msg.Message> _copyMessages() {
    return List<chat_msg.Message>.from(messages);
  }

  void _setMessages(List<chat_msg.Message> value) {
    messages = value;
  }

  /// 處理新消息接收
  void handleNewMessageReceived(chat_msg.Message message) {
    if (message.roomId != currentRoomId || !mounted) return;

    // 檢查是否為已知消息
    if (knownMessageIds.contains(message.id)) {
      return;
    }

    final updatedMessages = _copyMessages(); // Added back

    // 檢查是否為臨時消息的真實版本 (精準替換)
    if (message.tempId != null) {
      final tempId = message.tempId!;
      final tempMessageIndex =
          updatedMessages.indexWhere((m) => m.id == tempId);

      if (tempMessageIndex != -1) {
        updatedMessages[tempMessageIndex] = message;
        _setMessages(updatedMessages);
        pendingTempMessages.remove(tempId);
        knownMessageIds.remove(tempId); // Remove temp ID
        knownMessageIds.add(message.id); // Add real ID
        return;
      }
    }

    // 檢查是否為臨時消息的真實版本 (模糊匹配 - 兼容舊邏輯或無 tempId 情況)
    final tempMessageIndex = updatedMessages.indexWhere((m) =>
        m.id.startsWith('temp_') &&
        m.content == message.content &&
        m.senderId == message.senderId &&
        m.timestamp.difference(message.timestamp).abs().inSeconds < 5);

    if (tempMessageIndex != -1) {
      final tempMessage = updatedMessages[tempMessageIndex];

      updatedMessages[tempMessageIndex] = message;
      _setMessages(updatedMessages);
      pendingTempMessages.remove(tempMessage.id);
      knownMessageIds.remove(tempMessage.id);
      knownMessageIds.add(message.id);
      return;
    }

    // 檢查內容重複
    final duplicateIndex = updatedMessages.indexWhere((m) =>
        m.content == message.content &&
        m.senderId == message.senderId &&
        m.timestamp.difference(message.timestamp).abs().inSeconds < 3 &&
        !m.id.startsWith('temp_'));

    if (duplicateIndex != -1) {
      return;
    }

    // 添加新消息
    updatedMessages.insert(0, message);
    knownMessageIds.add(message.id);
    updatedMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _setMessages(updatedMessages);

    // 標記為已讀
    if (!isMyMessage(message)) {
      api_service.ChatApiService.markAsRead(currentRoomId);
    }
  }

  /// 發送文本消息
  void sendTextMessage(String content) {
    if (content.isEmpty) return;
    chatService.sendMessage(currentRoomId, content);
  }

  /// 刪除消息
  Future<void> deleteMessage(chat_msg.Message message) async {
    // 1. UI 更新
    final updatedMessages = _copyMessages()
      ..removeWhere((m) => m.id == message.id);
    _setMessages(updatedMessages);
    knownMessageIds.remove(message.id);

    // 2. 本地 DB 刪除 (Offline First)
    // 我們需要訪問 DatabaseHelper，但它不是 Mixin 的一部分。
    // 可以通過 ChatService 間接訪問，或者在這裡引入 DatabaseHelper。
    // 這裡我們暫時只依賴 ChatService 應該具備的刪除能力，或者 API。
    // 由於 ChatService 目前沒有公開 deleteMessage，我們直接使用 API 和假設的 DB 操作。

    // TODO: 將來應該在 ChatService 中統一封裝 deleteMessage
    // await chatService.deleteMessage(message.id);
  }

  /// 判斷是否為自己的消息
  bool isMyMessage(chat_msg.Message message) {
    if (currentUserId == null || currentUserId!.isEmpty) return false;
    return message.senderId == currentUserId;
  }

  /// 清理消息狀態
  void cleanupMessageState() {
    pendingTempMessages.clear();
    knownMessageIds.clear();
  }

  /// 添加或移除 Reaction
  void toggleReaction(chat_msg.Message message, String emoji) {
    if (!mounted) return;

    final updatedMessages = _copyMessages();
    final messageIndex = updatedMessages.indexWhere((m) => m.id == message.id);
    if (messageIndex == -1) return;

    final currentReactions = Map<String, List<String>>.from(message.reactions);
    final userIds = currentReactions[emoji] ?? [];

    if (currentUserId != null) {
      if (userIds.contains(currentUserId)) {
        // 移除當前用戶的 reaction
        userIds.remove(currentUserId);
        if (userIds.isEmpty) {
          currentReactions.remove(emoji);
        } else {
          currentReactions[emoji] = userIds;
        }
      } else {
        // 添加當前用戶的 reaction
        userIds.add(currentUserId!);
        currentReactions[emoji] = userIds;
      }

      // 更新消息
      final updatedMessage = message.copyWith(reactions: currentReactions);
      updatedMessages[messageIndex] = updatedMessage;
      _setMessages(updatedMessages);

      // 發送到後端
      _sendReactionToServer(message.id, emoji);
    }
  }

  /// 發送 Reaction 到伺服器
  Future<void> _sendReactionToServer(String messageId, String emoji) async {
    try {
      // 通過 WebSocket 發送
      if (isConnected) {
        chatService.sendReaction(messageId, emoji);
      } else {
        // 通過 API 發送
        await api_service.ChatApiService.addReaction(messageId, emoji);
      }
    } catch (e) {
      debugPrint('發送 reaction 失敗: $e');
    }
  }

  /// 處理從伺服器廣播接收到的 Reaction 更新
  void handleReactionUpdate(
      String messageId, Map<String, List<String>> newReactions) {
    // 1. 確保 State 仍然存在於 widget tree 中
    if (!mounted) {
      debugPrint(
          '[ChatMessageHandler] handleReactionUpdate: Widget is not mounted. Skipping update for message $messageId.');
      return;
    }

    // 2. 在消息列表中尋找目標消息
    final updatedMessages = _copyMessages();
    final messageIndex = updatedMessages.indexWhere((m) => m.id == messageId);

    // 3. 如果找不到消息，則記錄日誌並提前返回
    if (messageIndex == -1) {
      // 這種情況可能發生在消息已被刪除，但 reaction 更新延遲到達
      debugPrint(
          '[ChatMessageHandler] handleReactionUpdate: Message with ID $messageId not found.');
      return;
    }

    // 4. 創建一個更新後的消息對象
    // 我們使用 .copyWith() 來創建一個新的 Message 實例，
    // 這樣可以避免直接修改原始對象，符合不可變數據的實踐。
    final originalMessage = updatedMessages[messageIndex];
    final updatedMessage = originalMessage.copyWith(reactions: newReactions);

    // 5. 更新消息列表中的對象
    // 注意：這裡直接替換列表中的元素。UI 的刷新將由使用此 Mixin 的
    // State Widget 在適當的時機（例如，通過調用 setState）來觸發。
    // 這是此文件中保持一致的模式。
    updatedMessages[messageIndex] = updatedMessage;
    _setMessages(updatedMessages);

    debugPrint(
        '[ChatMessageHandler] handleReactionUpdate: Successfully updated reactions for message $messageId. New reactions: $newReactions');
  }

  /// 發送語音消息
  Future<void> sendVoiceMessage(String filePath, int durationSeconds) async {
    if (!mounted) return;

    try {
      debugPrint('ChatMessageHandler: 開始發送語音消息 (Offline-First)');
      debugPrint('ChatMessageHandler: 文件路徑: $filePath');
      debugPrint('ChatMessageHandler: 時長: $durationSeconds 秒');

      final fileSize = await File(filePath).length();

      // 使用 ChatService 發送 (它會處理 DB 存儲、UI 通知和後台發送)
      await chatService.sendVoiceMessage(
          currentRoomId, filePath, durationSeconds, fileSize);

      debugPrint('ChatMessageHandler: 語音消息已提交給 ChatService 處理');

      // 注意：不要立即刪除文件，因為 ChatService 需要在後台讀取它進行上傳。
      // 文件清理應由 ChatService 在上傳成功後處理，或者依賴系統的臨時文件清理機制。
    } catch (e) {
      debugPrint('ChatMessageHandler: 發送語音消息失敗: $e');

      // 顯示錯誤提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('語音消息發送失敗: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
