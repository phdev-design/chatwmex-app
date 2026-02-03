// lib/pages/chat/mixins/chat_message_handler.dart
import 'package:flutter/material.dart';
import 'dart:io'; // 🔥 新增：用于 File 类
import '../../../models/message.dart' as chat_msg;
import '../../../models/voice_message.dart' as voice_msg; // 🔥 新增：用于 VoiceMessage
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

    print('收到新消息: ${message.content}');

    // 檢查是否為已知消息
    if (knownMessageIds.contains(message.id)) {
      print('消息 ${message.id} 已存在，跳過重複處理');
      return;
    }

    // 檢查是否為臨時消息的真實版本
    final updatedMessages = _copyMessages();
    final tempMessageIndex = updatedMessages.indexWhere((m) =>
        m.id.startsWith('temp_') &&
        m.content == message.content &&
        m.senderId == message.senderId &&
        m.timestamp.difference(message.timestamp).abs().inSeconds < 5);

    if (tempMessageIndex != -1) {
      final tempMessage = updatedMessages[tempMessageIndex];
      print('替換臨時消息 ${tempMessage.id} 為真實消息 ${message.id}');

      updatedMessages[tempMessageIndex] = message;
      _setMessages(updatedMessages);
      pendingTempMessages.remove(tempMessage.id);
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
      print('檢測到內容重複的消息，跳過');
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

    final tempId =
        'temp_${DateTime.now().millisecondsSinceEpoch}_${content.hashCode}';

    final tempMessage = chat_msg.Message(
      id: tempId,
      senderId: currentUserId ?? '',
      senderName: currentUserName ?? '我',
      content: content,
      timestamp: DateTime.now(),
      roomId: currentRoomId,
      type: chat_msg.MessageType.text,
    );

    if (isConnected) {
      final updatedMessages = _copyMessages()..insert(0, tempMessage);
      _setMessages(updatedMessages);
      pendingTempMessages.add(tempId);
      knownMessageIds.add(tempId);

      chatService.sendMessage(currentRoomId, content);

      // 設置臨時消息過期清理
      Future.delayed(const Duration(seconds: 10), () {
        if (pendingTempMessages.contains(tempId)) {
          final updatedMessages =
              _copyMessages()..removeWhere((m) => m.id == tempId);
          _setMessages(updatedMessages);
          pendingTempMessages.remove(tempId);
          knownMessageIds.remove(tempId);
        }
      });
    } else {
      // Socket 未連接，使用 API
      api_service.ChatApiService.sendMessage(currentRoomId, content)
          .then((sentMessage) {
        if (mounted && !knownMessageIds.contains(sentMessage.id)) {
          final updatedMessages = _copyMessages()..insert(0, sentMessage);
          knownMessageIds.add(sentMessage.id);
          updatedMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          _setMessages(updatedMessages);
        }
      }).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('發送失敗: $error'), backgroundColor: Colors.red),
          );
        }
      });
    }
  }

  /// 刪除消息
  void deleteMessage(chat_msg.Message message) {
    final updatedMessages =
        _copyMessages()..removeWhere((m) => m.id == message.id);
    _setMessages(updatedMessages);
    knownMessageIds.remove(message.id);
    // TODO: 調用後端 API 刪除消息
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
      debugPrint('ChatMessageHandler: 開始上傳語音消息');
      debugPrint('ChatMessageHandler: 文件路徑: $filePath');
      debugPrint('ChatMessageHandler: 時長: $durationSeconds 秒');

      // 創建臨時語音消息（立即顯示在界面上）
      final tempId = 'temp_voice_${DateTime.now().millisecondsSinceEpoch}';
      final tempMessage = chat_msg.Message(
        id: tempId,
        senderId: currentUserId ?? '',
        senderName: currentUserName ?? '我',
        content: '[語音消息]',
        timestamp: DateTime.now(),
        roomId: currentRoomId,
        type: chat_msg.MessageType.voice,
        fileUrl: filePath, // 臨時使用本地路徑
        duration: durationSeconds,
        fileSize: await File(filePath).length(),
      );

      // 添加到消息列表
      final updatedMessages = _copyMessages()..insert(0, tempMessage);
      _setMessages(updatedMessages);
      pendingTempMessages.add(tempId);
      knownMessageIds.add(tempId);

      debugPrint('ChatMessageHandler: 臨時語音消息已添加到界面');

      // 背景上傳到服務器
      final uploaded = await VoiceApiService.uploadVoiceMessage(
        roomId: currentRoomId,
        filePath: filePath,
        duration: durationSeconds,
      );

      debugPrint('ChatMessageHandler: 語音上傳成功');
      debugPrint('ChatMessageHandler: 服務器返回 ID: ${uploaded.id}');
      debugPrint('ChatMessageHandler: 服務器 URL: ${uploaded.fileUrl}');

      // 用服務器返回的正式語音消息替換臨時消息
      final uploadedMsg = chat_msg.Message(
        id: uploaded.id,
        senderId: uploaded.senderId,
        senderName: uploaded.senderName,
        content: '[語音消息]',
        timestamp: uploaded.timestamp,
        roomId: uploaded.roomId,
        type: chat_msg.MessageType.voice,
        fileUrl: uploaded.fileUrl,
        duration: uploaded.duration,
        fileSize: uploaded.fileSize,
      );

      if (mounted) {
        final updatedMessages = _copyMessages();
        final idx = updatedMessages.indexWhere((m) => m.id == tempId);
        if (idx != -1) {
          updatedMessages[idx] = uploadedMsg;
          _setMessages(updatedMessages);
          pendingTempMessages.remove(tempId);
          knownMessageIds.remove(tempId);
          knownMessageIds.add(uploadedMsg.id);
          debugPrint('ChatMessageHandler: 臨時消息已替換為正式消息');
        }
      }

      // 通過 WebSocket 廣播（如果連接可用）
      if (isConnected) {
        chatService.sendVoiceMessage(currentRoomId, uploaded);
        debugPrint('ChatMessageHandler: 語音消息已通過 WebSocket 廣播');
      }

      // 清理臨時文件
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('ChatMessageHandler: 臨時文件已刪除');
        }
      } catch (e) {
        debugPrint('ChatMessageHandler: 刪除臨時文件失敗: $e');
      }
    } catch (e) {
      debugPrint('ChatMessageHandler: 發送語音消息失敗: $e');

      // 移除臨時消息
      if (mounted) {
        final updatedMessages = _copyMessages()
          ..removeWhere((m) => m.id.startsWith('temp_voice_'));
        _setMessages(updatedMessages);
      }

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
