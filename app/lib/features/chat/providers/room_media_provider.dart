import 'dart:convert';
import 'package:app/features/chat/repositories/chat_repository.dart';
import 'package:app/models/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/chat/services/public_key_cache_service.dart';
import 'package:app/core/storage/storage_service.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';

class RoomMediaState {
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String nextCursor;
  final List<Message> messages;
  final String? error;

  const RoomMediaState({
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.nextCursor = '',
    this.messages = const [],
    this.error,
  });

  RoomMediaState copyWith({
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextCursor,
    List<Message>? messages,
    String? error,
  }) {
    return RoomMediaState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: nextCursor ?? this.nextCursor,
      messages: messages ?? this.messages,
      error: error ?? this.error,
    );
  }
}

class RoomMediaNotifier
    extends FamilyNotifier<RoomMediaState, ({String roomId, String type})> {
  late final ChatRepository _repository;
  String? _currentUserId;

  @override
  RoomMediaState build(({String roomId, String type}) arg) {
    _repository = ref.watch(chatRepositoryProvider);
    _initCurrentUserId();
    return const RoomMediaState();
  }

  Future<void> _initCurrentUserId() async {
    final storage = ref.read(storageServiceProvider);
    _currentUserId = await storage.read('user_id');
  }

  Map<String, List<Message>> get groupedMessages {
    final sorted = [...state.messages]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final groups = <String, List<Message>>{};
    for (final message in sorted) {
      final key = DateFormat('yyyy年M月').format(message.createdAt);
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(message);
    }
    return groups;
  }

  /// 判斷字串是否看起來像 E2EE 密文
  bool _looksLikeE2EECiphertext(String content) {
    if (content.length < 40) return false;
    final base64Regex = RegExp(r'^[A-Za-z0-9+/]+=*$');
    return base64Regex.hasMatch(content.trim());
  }

  /// 🔐 解密媒體訊息內容（支援群組 fanout + 一對一 ECDH）
  Future<List<Message>> _decryptMediaContent(List<Message> messages) async {
    final cryptoService = ref.read(cryptoServiceProvider);
    final cacheService = ref.read(publicKeyCacheServiceProvider);

    if (_currentUserId == null) {
      await _initCurrentUserId();
    }

    print('📦 [RoomMedia] _decryptMediaContent: 收到 ${messages.length} 筆訊息, currentUserId=$_currentUserId');

    final result = <Message>[];
    for (final msg in messages) {
      final content = msg.content;
      // 🔧 修正：link 類型也需要解密，不只是 image/video
      final isMedia = msg.type == MessageType.image || msg.type == MessageType.video;
      final isLink = msg.type == MessageType.link || msg.type == MessageType.text;
      final needsDecrypt = isMedia || isLink;

      print('📦 [RoomMedia] 處理訊息 id=${msg.id} type=${msg.type} contentLen=${content.length} content=${content.length > 60 ? '${content.substring(0, 60)}...' : content}');

      // ========== 明文內容直接通過 ==========
      if (content.startsWith('http://') || content.startsWith('https://')) {
        print('📦 [RoomMedia] ✅ 明文 URL，直接通過: ${msg.id}');
        result.add(msg);
        continue;
      }
      if (content.startsWith('/uploads/')) {
        print('📦 [RoomMedia] ✅ 相對路徑，直接通過: ${msg.id}');
        result.add(msg);
        continue;
      }
      // MongoDB ObjectID
      if (content.length == 24 && RegExp(r'^[a-f0-9]{24}$', caseSensitive: false).hasMatch(content)) {
        print('📦 [RoomMedia] ✅ ObjectID，直接通過: ${msg.id}');
        result.add(msg);
        continue;
      }

      // ========== 判斷是否為真正的群組訊息 ==========
      // 🔧 修正：不能只靠 roomId 判斷，因為 getRoomResources 會把 DM 的 roomId 設成 contactId
      // 真正的群組訊息：有 roomId 且沒有 receiverId
      // DM 訊息：有 receiverId（即使 roomId 被強制設定）
      final hasDedicatedRoom = msg.roomId != null && msg.roomId!.isNotEmpty;
      final hasReceiver = msg.receiverId != null && msg.receiverId!.isNotEmpty;
      final isGroupMsg = hasDedicatedRoom && !hasReceiver;

      print('📦 [RoomMedia] 路由判斷: id=${msg.id} roomId=${msg.roomId} receiverId=${msg.receiverId} → isGroupMsg=$isGroupMsg');

      if (isGroupMsg) {
        var updated = msg;
        bool decrypted = false;

        // 1. 嘗試從 encryptedContentsFanout 解密
        // 🔧 修正：不再限制只有 isMedia 才走 fanout，link/text 也需要
        if (needsDecrypt && msg.encryptedContentsFanout != null &&
            _currentUserId != null &&
            (content.isEmpty || _looksLikeE2EECiphertext(content))) {
          final myEncryptedContent = msg.encryptedContentsFanout![_currentUserId!];
          print('📦 [RoomMedia] 群組 fanout 解密: id=${msg.id} hasMyContent=${myEncryptedContent != null}');
          if (myEncryptedContent != null && myEncryptedContent.isNotEmpty) {
            try {
              final senderPubKey = await cacheService.getPublicKey(msg.senderId);
              if (senderPubKey != null) {
                final decryptedContent = await cryptoService.decryptMessage(
                  myEncryptedContent,
                  senderPubKey,
                );
                print('📦 [RoomMedia] ✅ 群組 fanout 解密成功: id=${msg.id} result=${decryptedContent.length > 60 ? '${decryptedContent.substring(0, 60)}...' : decryptedContent}');
                updated = updated.copyWith(content: decryptedContent);
                decrypted = true;
              }
            } catch (e) {
              print('⚠️ [RoomMedia] 群組 fanout 解密失敗: ${msg.id} error=$e');
            }
          }
        }

        // 2. content 是密文（Go routeMessage 裁切後的 raw ciphertext）
        // 🔧 修正：不再限制只有 isMedia 才解密
        if (!decrypted && needsDecrypt && msg.encryptedContentsFanout == null &&
            _looksLikeE2EECiphertext(content)) {
          print('📦 [RoomMedia] 群組 raw ciphertext 解密: id=${msg.id}');
          final senderPubKey = await cacheService.getPublicKey(msg.senderId);
          if (senderPubKey != null) {
            try {
              final decryptedContent = await cryptoService.decryptMessage(
                content,
                senderPubKey,
              );
              if (decryptedContent != content) {
                print('📦 [RoomMedia] ✅ 群組 raw 解密成功: id=${msg.id} result=${decryptedContent.length > 60 ? '${decryptedContent.substring(0, 60)}...' : decryptedContent}');
                updated = updated.copyWith(content: decryptedContent);
                decrypted = true;
              }
            } catch (e) {
              // fallback: 嘗試舊格式 JSON fanout
              try {
                final payload = jsonDecode(content);
                if (payload is Map && payload['is_fanout'] == true) {
                  final ciphertexts = payload['ciphertexts'] as Map<String, dynamic>?;
                  final myCiphertext = ciphertexts?[_currentUserId];
                  if (myCiphertext != null) {
                    final plaintext = await cryptoService.decryptMessage(
                      myCiphertext.toString(),
                      senderPubKey,
                    );
                    updated = updated.copyWith(content: plaintext);
                    decrypted = true;
                  }
                }
              } catch (_) {
                print('⚠️ [RoomMedia] 群組舊格式解密也失敗: ${msg.id}');
              }
            }
          }
        }

        // 3. 提取 fileKey from fanout
        if (msg.fileKeysFanout != null && msg.fileKey == null && _currentUserId != null) {
          try {
            final senderPubKey = await cacheService.getPublicKey(msg.senderId);
            if (senderPubKey != null) {
              final decryptedFileKey = await cryptoService.extractFileKeyFromFanout(
                msg.fileKeysFanout!,
                _currentUserId!,
                senderPubKey,
              );
              if (decryptedFileKey != null) {
                updated = updated.copyWith(fileKey: decryptedFileKey);
              }
            }
          } catch (e) {
            print('⚠️ [RoomMedia] fileKey fanout 提取失敗: ${msg.id}');
          }
        }

        if (!decrypted) {
          print('📦 [RoomMedia] ⚠️ 群組訊息未能解密: id=${msg.id} type=${msg.type}');
        }
        result.add(updated);
        continue;
      }

      // ========== 一對一聊天解密 ==========

      if (content.length < 40) {
        print('📦 [RoomMedia] 短內容，跳過解密: ${msg.id}');
        result.add(msg);
        continue;
      }

      final isHexOnly = RegExp(r'^[a-f0-9]+$', caseSensitive: false).hasMatch(content);
      if (isHexOnly) {
        print('📦 [RoomMedia] 純 hex，跳過解密: ${msg.id}');
        result.add(msg);
        continue;
      }

      final hasBase64Chars = content.contains('+') ||
                             content.contains('/') ||
                             content.contains('=');
      if (!hasBase64Chars) {
        print('📦 [RoomMedia] 無 Base64 特徵，跳過解密: ${msg.id}');
        result.add(msg);
        continue;
      }

      print('📦 [RoomMedia] 一對一解密: id=${msg.id} type=${msg.type} senderId=${msg.senderId} receiverId=${msg.receiverId}');

      try {
        String? targetPubKey;
        if (msg.senderId == _currentUserId) {
          if (msg.receiverId != null && msg.receiverId!.isNotEmpty) {
            targetPubKey = await cacheService.getPublicKey(msg.receiverId!);
          }
        } else {
          targetPubKey = await cacheService.getPublicKey(msg.senderId);
        }

        if (targetPubKey == null || targetPubKey.isEmpty) {
          print('📦 [RoomMedia] ⚠️ 找不到公鑰: ${msg.id}');
          result.add(msg);
          continue;
        }

        final decryptedContent = await cryptoService.decryptMessage(content, targetPubKey);

        print('📦 [RoomMedia] 一對一解密結果: id=${msg.id} decrypted=${decryptedContent.length > 80 ? '${decryptedContent.substring(0, 80)}...' : decryptedContent}');

        if (decryptedContent.isEmpty || decryptedContent == content) {
          print('📦 [RoomMedia] ⚠️ 解密結果為空或未變: ${msg.id}');
          result.add(msg);
          continue;
        }

        // 🔧 修正：不再只接受 URL 格式的解密結果
        // 對於 link/text 類型，解密後的內容可能是含 URL 的文字，也應該接受
        if (isMedia) {
          // 媒體訊息：解密結果應該是 URL
          final isValidUrl = decryptedContent.startsWith('http://') ||
                            decryptedContent.startsWith('https://') ||
                            decryptedContent.startsWith('/uploads/');
          if (isValidUrl) {
            print('📦 [RoomMedia] ✅ 媒體解密成功 (URL): ${msg.id}');
            result.add(msg.copyWith(content: decryptedContent));
          } else {
            print('📦 [RoomMedia] ⚠️ 媒體解密結果非 URL: ${msg.id} → $decryptedContent');
            result.add(msg);
          }
        } else {
          // link/text 訊息：解密後的內容就是原始文字（可能含 URL）
          print('📦 [RoomMedia] ✅ 文字/連結解密成功: ${msg.id}');
          result.add(msg.copyWith(content: decryptedContent));
        }
      } catch (e) {
        print('⚠️ [RoomMedia] Message ${msg.id} 解密失敗: $e');
        result.add(msg);
      }
    }

    return result;
  }

  List<Message> _filterValidMedia(List<Message> messages) {
    return messages.where((msg) {
      // 🔧 修正：link/text 類型不用 resolveFullUrl 過濾，改用 extractAllUrls
      if (msg.type == MessageType.link || msg.type == MessageType.text) {
        final urls = extractAllUrls(msg.content);
        final pass = urls.isNotEmpty;
        if (!pass) {
          print('📦 [RoomMedia] _filterValidMedia 過濾掉 link/text: id=${msg.id} content=${msg.content.length > 60 ? '${msg.content.substring(0, 60)}...' : msg.content}');
        }
        return pass;
      }
      // 媒體類型用 resolveFullUrl 過濾
      final resolvedUrl = resolveFullUrl(msg.content);
      if (resolvedUrl.isEmpty) {
        print('📦 [RoomMedia] _filterValidMedia 過濾掉 media: id=${msg.id} type=${msg.type} content=${msg.content.length > 60 ? '${msg.content.substring(0, 60)}...' : msg.content}');
      }
      return resolvedUrl.isNotEmpty;
    }).toList();
  }

  Future<void> loadInitial() async {
    if (state.isLoading) return;
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      nextCursor: '',
      messages: [],
      error: null,
    );
    try {
      final result = await _repository.getRoomResources(
        arg.roomId,
        type: arg.type,
        cursor: '',
        limit: 20,
      );
      print('📦 [RoomMedia] loadInitial type=${arg.type}: API 回傳 ${result.messages.length} 筆');
      for (final m in result.messages) {
        print('📦 [RoomMedia]   → id=${m.id} type=${m.type} contentLen=${m.content.length} linkPreview=${m.linkPreview != null}');
      }
      final decrypted = await _decryptMediaContent(result.messages);
      print('📦 [RoomMedia] loadInitial: 解密後 ${decrypted.length} 筆');
      final filtered = _filterValidMedia(decrypted);
      print('📦 [RoomMedia] loadInitial: 過濾後 ${filtered.length} 筆');
      state = state.copyWith(
        isLoading: false,
        messages: filtered,
        nextCursor: result.nextCursor,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true, error: null);
    try {
      final result = await _repository.getRoomResources(
        arg.roomId,
        type: arg.type,
        cursor: state.nextCursor,
        limit: 20,
      );
      final decrypted = await _decryptMediaContent(result.messages);
      final filtered = _filterValidMedia(decrypted);
      final existingIds = state.messages.map((m) => m.id).toSet();
      final merged = [...state.messages];
      for (final msg in filtered) {
        if (!existingIds.contains(msg.id)) {
          merged.add(msg);
        }
      }
      state = state.copyWith(
        isLoadingMore: false,
        messages: merged,
        nextCursor: result.nextCursor,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }
}

final roomMediaProvider =
    NotifierProvider.family<
      RoomMediaNotifier,
      RoomMediaState,
      ({String roomId, String type})
    >(RoomMediaNotifier.new);
