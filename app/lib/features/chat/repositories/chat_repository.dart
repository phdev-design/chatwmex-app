import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/storage/local_db_service.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/core/websocket/websocket_service.dart';
import 'package:app/features/chat/models/room.dart';
import 'package:app/models/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class PaginatedMessages {
  final List<Message> messages;
  final String nextCursor;
  final bool hasMore;

  const PaginatedMessages({
    required this.messages,
    required this.nextCursor,
    required this.hasMore,
  });
}

class ChatRepository {
  final NetworkService _networkService;
  final LocalDbService _localDb;
  final CryptoService _cryptoService;
  final WebSocketService _webSocketService;
  final StorageService _storageService;

  ChatRepository(
    this._networkService,
    this._localDb,
    this._cryptoService,
    this._webSocketService,
    this._storageService,
  );

  Future<List<Room>> getMyRooms({String query = ''}) async {
    try {
      final Map<String, dynamic> queryParams = {};
      if (query.isNotEmpty) {
        queryParams['q'] = query;
      }

      final response = await _networkService.client.get(
        '/rooms/my',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      final List<dynamic> list = response.data['data'] ?? [];
      return list.map((e) => Room.fromJson(e)).toList();
    } catch (e) {
      rethrow; // 實務上建議使用自訂 Exception
    }
  }

  Future<List<User>> searchUsers(String query) async {
    try {
      final response = await _networkService.client.get(
        '/users/search',
        queryParameters: {'q': query},
      );
      final List<dynamic> list = response.data['data'] ?? [];
      return list.map((e) => User.fromJson(e)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<User>> getRoomMemberProfiles(String roomId) async {
    if (roomId.isEmpty) return const [];
    try {
      final response = await _networkService.client.get(
        '/rooms/$roomId/member-profiles',
      );
      final List<dynamic> list = response.data['data'] ?? [];
      return list
          .whereType<Map>()
          .map((e) => User.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<String> uploadMedia(File file, String type) async {
    return await _networkService.uploadFile(file, type);
  }

  Future<void> updateRoom(
    String roomId, {
    String? name,
    String? avatarUrl,
  }) async {
    if (roomId.isEmpty) return;
    try {
      final Map<String, dynamic> data = {};
      if (name != null) data['name'] = name;
      if (avatarUrl != null) data['avatar_url'] = avatarUrl;

      if (data.isEmpty) return;

      await _networkService.client.patch('/rooms/$roomId', data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> kickMember(String roomId, String memberId) async {
    if (roomId.isEmpty || memberId.isEmpty) return;
    try {
      await _networkService.client.delete('/rooms/$roomId/members/$memberId');
    } catch (e) {
      rethrow;
    }
  }

  Future<PaginatedMessages> getRoomResources(
    String roomId, {
    String type = 'media',
    String cursor = '',
    int limit = 20,
  }) async {
    if (roomId.isEmpty) {
      return const PaginatedMessages(
        messages: [],
        nextCursor: '',
        hasMore: false,
      );
    }

    List<Message> apiMessages = [];
    String nextCursor = '';
    bool hasMore = false;

    try {
      final response = await _networkService.client.get(
        '/rooms/$roomId/media',
        queryParameters: {'type': type, 'cursor': cursor, 'limit': limit},
      );
      final payload = Map<String, dynamic>.from(
        response.data['data'] as Map? ?? {},
      );
      final list = payload['data'] as List<dynamic>? ?? [];

      apiMessages = list.map((e) {
        final msg = Message.fromJson(Map<String, dynamic>.from(e));
        if (msg.roomId == null || msg.roomId!.isEmpty) {
          return msg.copyWith(roomId: roomId);
        }
        return msg;
      }).toList();

      nextCursor = payload['next_cursor']?.toString() ?? '';
      hasMore = payload['has_more'] == true;
    } catch (e) {
      debugPrint('⚠️ API 發生錯誤: $e');
    }

    if (apiMessages.isEmpty && cursor.isEmpty) {
      debugPrint('⚠️ API 回傳空資料，嘗試從 LocalDB 撈取...');
      final cached = await _localDb.getMessagesByRoom(roomId, limit: 1000);
      final deduped = _dedupeMessages(cached);
      for (final id in deduped.removedIds) {
        await _localDb.deleteMessageLocal(id);
      }
      apiMessages = deduped.messages.where((msg) {
        if (type == 'media') {
          return msg.type == MessageType.image || msg.type == MessageType.video;
        } else if (type == 'doc') {
          return msg.type == MessageType.file;
        } else if (type == 'link') {
          return msg.content.contains('http://') ||
              msg.content.contains('https://');
        }
        return false;
      }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return PaginatedMessages(
      messages: apiMessages,
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  Future<void> markMessagesAsRead(List<String> messageIds) async {
    if (messageIds.isEmpty) return; // 避免空陣列浪費 API 請求
    try {
      await _networkService.client.post(
        '/messages/read/batch',
        data: {'message_ids': messageIds},
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<String> uploadImage(File imageFile) async {
    final fileName = imageFile.path.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: fileName),
    });
    try {
      final response = await _networkService.client.post(
        '/media/upload',
        data: formData,
      );
      return response.data['data']['url'] ?? response.data['url'];
    } catch (e) {
      rethrow;
    }
  }

  Future<void> toggleReaction(String messageId, String emoji) async {
    if (messageId.isEmpty || emoji.isEmpty) return;
    try {
      await _networkService.client.post(
        '/messages/$messageId/reactions',
        data: {'emoji': emoji},
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> unsendMessage(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      await _networkService.client.patch('/messages/$messageId/unsend');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMessage(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      await _networkService.client.delete('/messages/$messageId');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Message>> getMessages(
    String roomId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      // 1. 永遠優先呼叫後端 API，確保能拿到「最新」的訊息
      final response = await _networkService.client.get(
        '/messages/history',
        queryParameters: {
          'contact_id': roomId,
          'limit': limit,
          'offset': offset,
        },
      );

      final List<dynamic> list = response.data['data'] ?? [];

      // 2. 轉換 JSON 並手動補上 roomId (超級關鍵 🔑)
      final latest = list.map((e) {
        final msg = Message.fromJson(e);
        // 如果後端沒傳 room_id，我們手動幫他補上，這樣 LocalDB 才能正確關聯！
        if (msg.roomId == null || msg.roomId!.isEmpty) {
          return msg.copyWith(roomId: roomId);
        }
        return msg;
      }).toList();

      // 3. 將最新的訊息安全地存入 SQLite，更新本地快取
      if (latest.isNotEmpty) {
        try {
          await _localDb.insertMessages(latest);
          await _cleanupOptimisticDuplicates(latest);
        } catch (dbError) {
          debugPrint('⚠️ 寫入 SQLite 失敗，但不影響畫面顯示: $dbError');
        }
      }

      // 4. 回傳最新訊息給畫面
      return latest;
    } catch (e) {
      // 5. 只有在「斷網」或「API 壞掉」時，才退回使用本地的快取訊息
      debugPrint('⚠️ API 發生錯誤，退回使用本地快取: $e');

      final cached = await _localDb.getMessagesByRoom(
        roomId,
        limit: limit,
        offset: offset,
      );

      if (cached.isNotEmpty) {
        return cached;
      }

      // 如果連快取都沒有，拋出錯誤讓畫面顯示 Error
      rethrow;
    }
  }

  /// 呼叫後端清除指定聊天室的所有歷史訊息
  /// 如果 API 失敗（如後端未實作），會降級為只清本地資料
  Future<void> clearChatHistory(String roomId) async {
    if (roomId.isEmpty) return;
    try {
      await _networkService.client.delete('/rooms/$roomId/messages');
    } catch (e) {
      // API 失敗時降級操作：只清本地，不向上層拋出
      debugPrint('⚠️ clearChatHistory API 失敗，降級為只清本地: $e');
    }
  }

  Future<void> _cleanupOptimisticDuplicates(List<Message> latest) async {
    final idsToDelete = <String>{};
    for (final msg in latest) {
      final clientMsgId = msg.clientMsgId;
      if (clientMsgId == null || clientMsgId.isEmpty) continue;
      if (msg.id == clientMsgId) continue;
      idsToDelete.add(clientMsgId);
    }
    for (final id in idsToDelete) {
      await _localDb.deleteMessageLocal(id);
    }
  }

  Future<String?> getUserPublicKey(String userId) async {
    try {
      final response = await _networkService.client.get(
        '/users/$userId/public_key',
      );
      return response.data['data']['public_key'] as String?;
    } catch (e) {
      debugPrint('Failed to get user public key: $e');
      return null;
    }
  }

  _DedupedResult _dedupeMessages(List<Message> input) {
    final working = [...input]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final kept = <Message>[];
    final removedIds = <String>{};
    const tolerance = Duration(seconds: 3);

    for (final msg in working) {
      final index = kept.indexWhere((existing) {
        if (_canonicalKey(existing).isNotEmpty &&
            _canonicalKey(existing) == _canonicalKey(msg)) {
          return true;
        }
        return _isPotentialDuplicate(existing, msg, tolerance);
      });
      if (index == -1) {
        kept.add(msg);
        continue;
      }
      final current = kept[index];
      final preferred = _preferServerRecord(current, msg);
      final dropped = identical(preferred, current) ? msg : current;
      if (dropped.id.isNotEmpty) {
        removedIds.add(dropped.id);
      }
      kept[index] = preferred;
    }

    return _DedupedResult(
      messages: kept..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      removedIds: removedIds,
    );
  }

  String _canonicalKey(Message msg) {
    if (msg.clientMsgId != null && msg.clientMsgId!.isNotEmpty) {
      return 'client:${msg.clientMsgId}';
    }
    if (msg.id.isNotEmpty) {
      return 'id:${msg.id}';
    }
    return '';
  }

  bool _isPotentialDuplicate(Message a, Message b, Duration tolerance) {
    if (a.type != b.type) return false;
    if (a.senderId != b.senderId) return false;
    if ((a.roomId ?? '') != (b.roomId ?? '')) return false;
    if ((a.receiverId ?? '') != (b.receiverId ?? '')) return false;
    if (a.content.trim() != b.content.trim()) return false;
    final diff = a.createdAt.difference(b.createdAt).inMilliseconds.abs();
    return diff <= tolerance.inMilliseconds;
  }

  Message _preferServerRecord(Message current, Message incoming) {
    final currentServer = _isServerRecord(current);
    final incomingServer = _isServerRecord(incoming);
    if (incomingServer && !currentServer) return incoming;
    if (currentServer && !incomingServer) return current;
    if (incoming.createdAt.isAfter(current.createdAt)) return incoming;
    return current;
  }

  bool _isServerRecord(Message msg) {
    if (msg.id.isEmpty) return false;
    if (msg.clientMsgId != null &&
        msg.clientMsgId!.isNotEmpty &&
        msg.id == msg.clientMsgId) {
      return false;
    }
    return RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(msg.id);
  }

  /// Sends an encrypted audio message
  /// 1. Generates random file key
  /// 2. Encrypts audio file
  /// 3. Uploads encrypted file
  /// 4. For group chats: Encrypts fileKey for each member (fanout)
  /// 5. Sends message via WebSocket with URL and encrypted keys
  Future<Message> sendAudioMessage({
    required String audioFilePath,
    required String roomId,
    String? receiverId,
    String? replyToId,
  }) async {
    try {
      // 1. Read audio file bytes
      final audioFile = File(audioFilePath);
      if (!await audioFile.exists()) {
        throw Exception('Audio file not found: $audioFilePath');
      }
      final audioBytes = await audioFile.readAsBytes();

      // 2. Generate random encryption key
      final fileKey = await _cryptoService.generateRandomKey();

      // 3. Encrypt audio bytes
      final encryptedBytes = await _cryptoService.encryptBytes(
        Uint8List.fromList(audioBytes),
        fileKey,
      );

      // 4. Upload encrypted audio
      final audioUrl = await _uploadEncryptedAudio(encryptedBytes);

      // 5. 🔐 群組訊息：為每個成員加密 fileKey (fanout)
      Map<String, dynamic>? fileKeysFanout;
      final isGroupMessage = roomId.isNotEmpty;
      
      if (isGroupMessage) {
        try {
          // 取得群組所有成員
          final members = await getRoomMemberProfiles(roomId);
          // 🔐 Bug #2 防呆：過濾掉 roomId
          final memberIds = members.map((m) => m.id).where((id) => id != roomId).toList();
          
          debugPrint('[sendAudioMessage] 🔐 Encrypting fileKey for ${memberIds.length} members');
          
          // 為每個成員用其公鑰加密 fileKey
          final encryptedKeys = <String, String>{};
          for (final memberId in memberIds) {
            try {
              final memberPublicKey = await getUserPublicKey(memberId);
              if (memberPublicKey != null && memberPublicKey.isNotEmpty) {
                final encryptedKey = await _cryptoService.encryptMessage(
                  fileKey,
                  memberPublicKey,
                );
                encryptedKeys[memberId] = encryptedKey;
                debugPrint('[sendAudioMessage] ✅ Encrypted fileKey for member: $memberId');
              } else {
                debugPrint('[sendAudioMessage] ⚠️ No public key found for member: $memberId');
              }
            } catch (e) {
              debugPrint('[sendAudioMessage] ❌ Failed to encrypt fileKey for member $memberId: $e');
            }
          }
          
          if (encryptedKeys.isNotEmpty) {
            fileKeysFanout = {
              'is_fanout': true,
              'keys': encryptedKeys,
            };
            debugPrint('[sendAudioMessage] 🔐 Created fileKeysFanout with ${encryptedKeys.length} keys');
          }
        } catch (e) {
          debugPrint('[sendAudioMessage] ⚠️ Failed to create fileKeysFanout: $e');
          // 繼續執行，但不使用 fanout（向後兼容）
        }
      }

      // 6. Create message object for local optimistic update
      final clientMsgId = const Uuid().v4();
      final now = DateTime.now();
      
      // 🔐 獲取當前用戶 ID
      final currentUserId = await _storageService.read('user_id') ?? '';
      
      final message = Message(
        id: clientMsgId, // Will be replaced by server ID
        clientMsgId: clientMsgId,
        content: audioUrl,
        senderId: currentUserId,
        receiverId: receiverId,
        roomId: roomId,
        replyToMessageId: replyToId,
        type: MessageType.voice,
        createdAt: now,
        status: MessageStatus.sending,
        fileKey: isGroupMessage ? null : fileKey, // 🔐 群組訊息不使用明文 fileKey
        fileKeysFanout: fileKeysFanout,
      );

      // 7. Store optimistic message in local DB
      try {
        await _localDb.insertMessages([message]);
      } catch (e) {
        debugPrint('⚠️ Failed to store optimistic message: $e');
      }

      // 8. Send message via WebSocket
      final payload = <String, dynamic>{
        'client_msg_id': clientMsgId,
        'type': 'voice',
        'content': audioUrl,
        'room_id': roomId,
        'receiver_id': receiverId,
        if (replyToId != null) 'reply_to_id': replyToId,
      };
      
      // 🔐 群組訊息：使用 file_keys_fanout，不傳明文 file_key
      if (fileKeysFanout != null) {
        payload['file_keys_fanout'] = fileKeysFanout;
        debugPrint('[sendAudioMessage] 🔐 Sending with file_keys_fanout (no plaintext file_key)');
      } else {
        // DM 或 fanout 失敗時，使用明文 fileKey（向後兼容）
        payload['file_key'] = fileKey;
        debugPrint('[sendAudioMessage] 📤 Sending with plaintext file_key (DM or fallback)');
      }
      
      await _webSocketService.send('chat_message', payload);

      debugPrint('✅ Encrypted audio message sent: $audioUrl');
      return message;
    } catch (e) {
      debugPrint('❌ Failed to send audio message: $e');
      rethrow;
    }
  }

  /// Helper: Encrypts and uploads audio file
  Future<String> _uploadEncryptedAudio(Uint8List encryptedBytes) async {
    try {
      // Create temporary file for encrypted audio
      final tempDir = await Directory.systemTemp.createTemp('encrypted_audio_');
      final tempFile = File('${tempDir.path}/encrypted_audio.m4a');
      await tempFile.writeAsBytes(encryptedBytes);

      // Upload using existing uploadMedia method
      final audioUrl = await uploadMedia(tempFile, 'voice');

      // Clean up temporary file
      try {
        await tempFile.delete();
        await tempDir.delete();
      } catch (e) {
        debugPrint('⚠️ Failed to clean up temp file: $e');
      }

      return audioUrl;
    } catch (e) {
      throw Exception('Failed to upload encrypted audio: $e');
    }
  }

  /// 🔐 E2EE Image Message: Encrypts and sends image message
  /// 1. Reads image bytes from file
  /// 2. Generates random fileKey
  /// 3. Encrypts image bytes with AES-GCM
  /// 4. Uploads encrypted bytes to server
  /// 5. For group chats: Encrypts fileKey for each member (fanout)
  /// 6. For DM: Encrypts imageUrl with receiver's public key
  /// 7. Sends message via WebSocket with encrypted URL and keys
  Future<Message> sendImageMessage({
    required String imagePath,
    required String roomId,
    String? receiverId,
  }) async {
    try {
      // 1. Read image file bytes
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $imagePath');
      }
      final imageBytes = await imageFile.readAsBytes();

      // 2. Generate random encryption key
      final fileKey = await _cryptoService.generateRandomKey();

      // 3. Encrypt image bytes
      final encryptedBytes = await _cryptoService.encryptBytes(
        Uint8List.fromList(imageBytes),
        fileKey,
      );

      // 4. Upload encrypted image
      final imageUrl = await _uploadEncryptedImage(encryptedBytes);

      // 5. 🔐 群組訊息：為每個成員加密 content (imageUrl) 和 fileKey (fanout)
      Map<String, dynamic>? fileKeysFanout;
      Map<String, String>? encryptedContentsFanout;
      String? encryptedContent;
      final isGroupMessage = roomId.isNotEmpty;
      
      if (isGroupMessage) {
        try {
          // 取得群組所有成員
          final members = await getRoomMemberProfiles(roomId);
          // 🔐 Bug #2 防呆：過濾掉 roomId
          final memberIds = members.map((m) => m.id).where((id) => id != roomId).toList();
          
          debugPrint('[sendImageMessage] 🔐 Encrypting for ${memberIds.length} members');
          
          // 為每個成員用其公鑰加密 fileKey 和 content
          final encryptedKeys = <String, String>{};
          final encryptedContents = <String, String>{};
          for (final memberId in memberIds) {
            try {
              final memberPublicKey = await getUserPublicKey(memberId);
              if (memberPublicKey != null && memberPublicKey.isNotEmpty) {
                // 加密 fileKey
                final encryptedKey = await _cryptoService.encryptMessage(
                  fileKey,
                  memberPublicKey,
                );
                encryptedKeys[memberId] = encryptedKey;
                
                // 加密 content (imageUrl)
                final encryptedContentForMember = await _cryptoService.encryptMessage(
                  imageUrl,
                  memberPublicKey,
                );
                encryptedContents[memberId] = encryptedContentForMember;
                
                debugPrint('[sendImageMessage] ✅ Encrypted for member: $memberId');
              } else {
                debugPrint('[sendImageMessage] ⚠️ No public key found for member: $memberId');
              }
            } catch (e) {
              debugPrint('[sendImageMessage] ❌ Failed to encrypt for member $memberId: $e');
            }
          }
          
          if (encryptedKeys.isNotEmpty) {
            fileKeysFanout = {
              'is_fanout': true,
              'keys': encryptedKeys,
            };
            encryptedContentsFanout = encryptedContents;
            debugPrint('[sendImageMessage] 🔐 Created fanout with ${encryptedKeys.length} keys');
          }
        } catch (e) {
          debugPrint('[sendImageMessage] ⚠️ Failed to create fanout: $e');
        }
      } else if (receiverId != null && receiverId.isNotEmpty) {
        // DM: 用接收方公鑰加密 imageUrl
        try {
          final receiverPublicKey = await getUserPublicKey(receiverId);
          if (receiverPublicKey != null && receiverPublicKey.isNotEmpty) {
            encryptedContent = await _cryptoService.encryptMessage(
              imageUrl,
              receiverPublicKey,
            );
            debugPrint('[sendImageMessage] 🔐 Encrypted content for DM');
          }
        } catch (e) {
          debugPrint('[sendImageMessage] ⚠️ Failed to encrypt content for DM: $e');
        }
      }

      // 6. Create message object for local optimistic update
      final clientMsgId = const Uuid().v4();
      final now = DateTime.now();
      
      // 🔐 獲取當前用戶 ID
      final currentUserId = await _storageService.read('user_id') ?? '';
      
      // 🔐 對於群組訊息，content 使用第一個成員的加密內容（用於本地顯示）
      // 實際發送時，每個成員會從 encrypted_contents_fanout 取得自己的版本
      String contentForLocal = imageUrl;
      if (encryptedContentsFanout != null && encryptedContentsFanout.isNotEmpty) {
        contentForLocal = encryptedContentsFanout.values.first;
      } else if (encryptedContent != null) {
        contentForLocal = encryptedContent;
      }
      
      final message = Message(
        id: clientMsgId,
        clientMsgId: clientMsgId,
        content: contentForLocal,
        senderId: currentUserId,
        receiverId: receiverId,
        roomId: roomId,
        type: MessageType.image,
        createdAt: now,
        status: MessageStatus.sending,
        fileKey: isGroupMessage ? null : fileKey, // 🔐 群組訊息不使用明文 fileKey
        fileKeysFanout: fileKeysFanout,
        encryptedContentsFanout: encryptedContentsFanout,
      );

      // 7. Store optimistic message in local DB
      try {
        await _localDb.insertMessages([message]);
      } catch (e) {
        debugPrint('⚠️ Failed to store optimistic message: $e');
      }

      // 8. Send message via WebSocket
      final payload = <String, dynamic>{
        'client_msg_id': clientMsgId,
        'type': 'image',
        'room_id': roomId,
        'receiver_id': receiverId,
      };
      
      // 🔐 群組訊息：使用 fanout，content 留空（後端會從 fanout 中處理）
      if (fileKeysFanout != null) {
        payload['file_keys_fanout'] = fileKeysFanout;
        payload['encrypted_contents_fanout'] = encryptedContentsFanout;
        // 群組訊息不傳送 content，後端會從 encrypted_contents_fanout 中取得
        payload['content'] = ''; // 空字串，後端允許 fanout 訊息的 content 為空
        debugPrint('[sendImageMessage] 🔐 Sending with fanout (content empty)');
      } else {
        // DM：傳送加密的 content 和明文 fileKey
        payload['content'] = encryptedContent ?? imageUrl;
        payload['file_key'] = fileKey;
        debugPrint('[sendImageMessage] 📤 Sending DM with encrypted content');
      }
      
      await _webSocketService.send('chat_message', payload);

      debugPrint('✅ Encrypted image message sent: $imageUrl');
      return message;
    } catch (e) {
      debugPrint('❌ Failed to send image message: $e');
      rethrow;
    }
  }

  /// Helper: Encrypts and uploads image file
  Future<String> _uploadEncryptedImage(Uint8List encryptedBytes) async {
    try {
      final tempDir = await Directory.systemTemp.createTemp('encrypted_image_');
      final tempFile = File('${tempDir.path}/encrypted_image.jpg');
      await tempFile.writeAsBytes(encryptedBytes);

      final imageUrl = await uploadMedia(tempFile, 'image');

      try {
        await tempFile.delete();
        await tempDir.delete();
      } catch (e) {
        debugPrint('⚠️ Failed to clean up temp file: $e');
      }

      return imageUrl;
    } catch (e) {
      throw Exception('Failed to upload encrypted image: $e');
    }
  }

  /// 🔐 E2EE Video Message: Encrypts and sends video message
  /// 1. Reads video bytes from file
  /// 2. Generates random fileKey
  /// 3. Encrypts video bytes with AES-GCM
  /// 4. Uploads encrypted bytes to server
  /// 5. For group chats: Encrypts fileKey for each member (fanout)
  /// 6. For DM: Encrypts videoUrl with receiver's public key
  /// 7. Sends message via WebSocket with encrypted URL and keys
  Future<Message> sendVideoMessage({
    required String videoPath,
    required String roomId,
    String? receiverId,
  }) async {
    try {
      // 1. Read video file bytes
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        throw Exception('Video file not found: $videoPath');
      }
      final videoBytes = await videoFile.readAsBytes();

      // 2. Generate random encryption key
      final fileKey = await _cryptoService.generateRandomKey();

      // 3. Encrypt video bytes
      final encryptedBytes = await _cryptoService.encryptBytes(
        Uint8List.fromList(videoBytes),
        fileKey,
      );

      // 4. Upload encrypted video
      final videoUrl = await _uploadEncryptedVideo(encryptedBytes);

      // 5. 🔐 群組訊息：為每個成員加密 content (videoUrl) 和 fileKey (fanout)
      Map<String, dynamic>? fileKeysFanout;
      Map<String, String>? encryptedContentsFanout;
      String? encryptedContent;
      final isGroupMessage = roomId.isNotEmpty;
      
      if (isGroupMessage) {
        try {
          final members = await getRoomMemberProfiles(roomId);
          // 🔐 Bug #2 防呆：過濾掉 roomId
          final memberIds = members.map((m) => m.id).where((id) => id != roomId).toList();
          
          debugPrint('[sendVideoMessage] 🔐 Encrypting for ${memberIds.length} members');
          
          final encryptedKeys = <String, String>{};
          final encryptedContents = <String, String>{};
          for (final memberId in memberIds) {
            try {
              final memberPublicKey = await getUserPublicKey(memberId);
              if (memberPublicKey != null && memberPublicKey.isNotEmpty) {
                final encryptedKey = await _cryptoService.encryptMessage(
                  fileKey,
                  memberPublicKey,
                );
                encryptedKeys[memberId] = encryptedKey;
                
                final encryptedContentForMember = await _cryptoService.encryptMessage(
                  videoUrl,
                  memberPublicKey,
                );
                encryptedContents[memberId] = encryptedContentForMember;
                
                debugPrint('[sendVideoMessage] ✅ Encrypted for member: $memberId');
              } else {
                debugPrint('[sendVideoMessage] ⚠️ No public key found for member: $memberId');
              }
            } catch (e) {
              debugPrint('[sendVideoMessage] ❌ Failed to encrypt for member $memberId: $e');
            }
          }
          
          if (encryptedKeys.isNotEmpty) {
            fileKeysFanout = {
              'is_fanout': true,
              'keys': encryptedKeys,
            };
            encryptedContentsFanout = encryptedContents;
            debugPrint('[sendVideoMessage] 🔐 Created fanout with ${encryptedKeys.length} keys');
          }
        } catch (e) {
          debugPrint('[sendVideoMessage] ⚠️ Failed to create fanout: $e');
        }
      } else if (receiverId != null && receiverId.isNotEmpty) {
        // DM: 用接收方公鑰加密 videoUrl
        try {
          final receiverPublicKey = await getUserPublicKey(receiverId);
          if (receiverPublicKey != null && receiverPublicKey.isNotEmpty) {
            encryptedContent = await _cryptoService.encryptMessage(
              videoUrl,
              receiverPublicKey,
            );
            debugPrint('[sendVideoMessage] 🔐 Encrypted content for DM');
          }
        } catch (e) {
          debugPrint('[sendVideoMessage] ⚠️ Failed to encrypt content for DM: $e');
        }
      }

      // 6. Create message object
      final clientMsgId = const Uuid().v4();
      final now = DateTime.now();
      
      // 🔐 獲取當前用戶 ID
      final currentUserId = await _storageService.read('user_id') ?? '';
      
      // 🔐 對於群組訊息，content 使用第一個成員的加密內容（用於本地顯示）
      String contentForLocal = videoUrl;
      if (encryptedContentsFanout != null && encryptedContentsFanout.isNotEmpty) {
        contentForLocal = encryptedContentsFanout.values.first;
      } else if (encryptedContent != null) {
        contentForLocal = encryptedContent;
      }
      
      final message = Message(
        id: clientMsgId,
        clientMsgId: clientMsgId,
        content: contentForLocal,
        senderId: currentUserId,
        receiverId: receiverId,
        roomId: roomId,
        type: MessageType.video,
        createdAt: now,
        status: MessageStatus.sending,
        fileKey: isGroupMessage ? null : fileKey,
        fileKeysFanout: fileKeysFanout,
        encryptedContentsFanout: encryptedContentsFanout,
      );

      // 7. Store optimistic message
      try {
        await _localDb.insertMessages([message]);
      } catch (e) {
        debugPrint('⚠️ Failed to store optimistic message: $e');
      }

      // 8. Send via WebSocket
      final payload = <String, dynamic>{
        'client_msg_id': clientMsgId,
        'type': 'video',
        'room_id': roomId,
        'receiver_id': receiverId,
      };
      
      // 🔐 群組訊息：使用 fanout，content 留空
      if (fileKeysFanout != null) {
        payload['file_keys_fanout'] = fileKeysFanout;
        payload['encrypted_contents_fanout'] = encryptedContentsFanout;
        payload['content'] = ''; // 空字串，後端允許 fanout 訊息的 content 為空
        debugPrint('[sendVideoMessage] 🔐 Sending with fanout (content empty)');
      } else {
        // DM：傳送加密的 content 和明文 fileKey
        payload['content'] = encryptedContent ?? videoUrl;
        payload['file_key'] = fileKey;
        debugPrint('[sendVideoMessage] 📤 Sending DM with encrypted content');
      }
      
      await _webSocketService.send('chat_message', payload);

      debugPrint('✅ Encrypted video message sent: $videoUrl');
      return message;
    } catch (e) {
      debugPrint('❌ Failed to send video message: $e');
      rethrow;
    }
  }

  /// Helper: Encrypts and uploads video file
  Future<String> _uploadEncryptedVideo(Uint8List encryptedBytes) async {
    try {
      final tempDir = await Directory.systemTemp.createTemp('encrypted_video_');
      final tempFile = File('${tempDir.path}/encrypted_video.mp4');
      await tempFile.writeAsBytes(encryptedBytes);

      final videoUrl = await uploadMedia(tempFile, 'video');

      try {
        await tempFile.delete();
        await tempDir.delete();
      } catch (e) {
        debugPrint('⚠️ Failed to clean up temp file: $e');
      }

      return videoUrl;
    } catch (e) {
      throw Exception('Failed to upload encrypted video: $e');
    }
  }
}

class _DedupedResult {
  final List<Message> messages;
  final Set<String> removedIds;

  const _DedupedResult({required this.messages, required this.removedIds});
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  final crypto = ref.watch(cryptoServiceProvider);
  final webSocket = ref.watch(webSocketServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  return ChatRepository(network, LocalDbService(), crypto, webSocket, storage);
});
