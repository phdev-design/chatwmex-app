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

    final result = <Message>[];
    for (final msg in messages) {
      final content = msg.content;
      final isMedia = msg.type == MessageType.image || msg.type == MessageType.video;

      // ========== 明文內容直接通過 ==========
      if (content.startsWith('http://') || content.startsWith('https://')) {
        result.add(msg);
        continue;
      }
      if (content.startsWith('/uploads/')) {
        result.add(msg);
        continue;
      }
      // MongoDB ObjectID
      if (content.length == 24 && RegExp(r'^[a-f0-9]{24}$', caseSensitive: false).hasMatch(content)) {
        result.add(msg);
        continue;
      }

      // ========== 群組媒體解密（fanout） ==========
      final isGroupMsg = msg.roomId != null && msg.roomId!.isNotEmpty;

      if (isGroupMsg) {
        var updated = msg;
        bool decrypted = false;

        // 1. 嘗試從 encryptedContentsFanout 解密 URL
        if (isMedia && msg.encryptedContentsFanout != null &&
            _currentUserId != null &&
            (content.isEmpty || _looksLikeE2EECiphertext(content))) {
          final myEncryptedUrl = msg.encryptedContentsFanout![_currentUserId!];
          if (myEncryptedUrl != null && myEncryptedUrl.isNotEmpty) {
            try {
              final senderPubKey = await cacheService.getPublicKey(msg.senderId);
              if (senderPubKey != null) {
                final decryptedUrl = await cryptoService.decryptMessage(
                  myEncryptedUrl,
                  senderPubKey,
                );
                updated = updated.copyWith(content: decryptedUrl);
                decrypted = true;
              }
            } catch (e) {
              print('⚠️ [RoomMedia] 群組 fanout URL 解密失敗: ${msg.id}');
            }
          }
        }

        // 2. content 是密文（Go routeMessage 裁切後的 raw ciphertext）
        if (!decrypted && isMedia && msg.encryptedContentsFanout == null &&
            _looksLikeE2EECiphertext(content)) {
          final senderPubKey = await cacheService.getPublicKey(msg.senderId);
          if (senderPubKey != null) {
            try {
              final decryptedUrl = await cryptoService.decryptMessage(
                content,
                senderPubKey,
              );
              if (decryptedUrl != content) {
                updated = updated.copyWith(content: decryptedUrl);
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

        result.add(updated);
        continue;
      }

      // ========== 一對一聊天解密 ==========

      if (content.length < 40) {
        result.add(msg);
        continue;
      }

      final isHexOnly = RegExp(r'^[a-f0-9]+$', caseSensitive: false).hasMatch(content);
      if (isHexOnly) {
        result.add(msg);
        continue;
      }

      final hasBase64Chars = content.contains('+') ||
                             content.contains('/') ||
                             content.contains('=');
      if (!hasBase64Chars) {
        result.add(msg);
        continue;
      }

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
          result.add(msg);
          continue;
        }

        final decryptedContent = await cryptoService.decryptMessage(content, targetPubKey);

        if (decryptedContent.isEmpty || decryptedContent == content) {
          result.add(msg);
          continue;
        }

        final isValidUrl = decryptedContent.startsWith('http://') ||
                          decryptedContent.startsWith('https://') ||
                          decryptedContent.startsWith('/uploads/');
        if (isValidUrl) {
          result.add(msg.copyWith(content: decryptedContent));
        } else {
          result.add(msg);
        }
      } catch (e) {
        print('⚠️ [RoomMedia] Message ${msg.id} 解密失敗');
        result.add(msg);
      }
    }

    return result;
  }

  List<Message> _filterValidMedia(List<Message> messages) {
    return messages.where((msg) {
      final resolvedUrl = resolveFullUrl(msg.content);
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
      final decrypted = await _decryptMediaContent(result.messages);
      final filtered = _filterValidMedia(decrypted);
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
