import 'package:app/features/chat/providers/room_media_provider.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:app/features/chat/ui/photo_screen.dart';
import 'package:app/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MediaTabContent extends ConsumerStatefulWidget {
  final String roomId;

  const MediaTabContent({super.key, required this.roomId});

  @override
  ConsumerState<MediaTabContent> createState() => _MediaTabContentState();
}

class _MediaTabContentState extends ConsumerState<MediaTabContent> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    final arg = (roomId: widget.roomId, type: 'media');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(roomMediaProvider(arg).notifier).loadInitial();
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      final arg = (roomId: widget.roomId, type: 'media');
      ref.read(roomMediaProvider(arg).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final arg = (roomId: widget.roomId, type: 'media');
    final state = ref.watch(roomMediaProvider(arg));
    final notifier = ref.read(roomMediaProvider(arg).notifier);
    final grouped = notifier.groupedMessages;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Initial loading ──────────────────────────────────────────────────────
    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // ── Empty state ───────────────────────────────────────────────────────────
    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_library_outlined,
                size: 48,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '尚無媒體',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '此聊天室傳送的照片和影片\n會顯示在這裡',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      );
    }

    // ── Grid ──────────────────────────────────────────────────────────────────
    final slivers = <Widget>[];

    for (final entry in grouped.entries) {
      final mediaMessages = entry.value;
      if (mediaMessages.isEmpty) continue;

      // Section header
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Text(
              entry.key,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      );

      // Grid
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final message = mediaMessages[index];
              final url = resolveFullUrl(message.content);
              final heroTag = message.id;
              final isVideo = message.type == MessageType.video;

              if (url.isEmpty) {
                return _DecryptionFailedTile(cs: cs);
              }

              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PhotoScreen(imageUrl: url, heroTag: heroTag),
                    ),
                  );
                },
                child: Hero(
                  tag: heroTag,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Image
                      Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFF0F2F5),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded /
                                          progress.expectedTotalBytes!
                                    : null,
                                color: cs.primary.withValues(alpha: 0.6),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: isDark
                                ? const Color(0xFF2C2C2E)
                                : const Color(0xFFF0F2F5),
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 28,
                              color: cs.onSurface.withValues(alpha: 0.3),
                            ),
                          );
                        },
                      ),
                      // Video play overlay
                      if (isVideo)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }, childCount: mediaMessages.length),
          ),
        ),
      );
    }

    // Load more indicator
    if (state.isLoadingMore) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }

    // Bottom safe area padding
    slivers.add(
      SliverToBoxAdapter(
        child: SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
      ),
    );

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: slivers,
    );
  }
}

// ── Decryption failed tile ───────────────────────────────────────────────────

class _DecryptionFailedTile extends StatelessWidget {
  final ColorScheme cs;

  const _DecryptionFailedTile({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(
          color: cs.error.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 32,
            color: cs.error.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '檔案未能解密',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Placeholder tile (deprecated) ─────────────────────────────────────────────

class _PlaceholderTile extends StatelessWidget {
  final bool isDark;
  final ColorScheme cs;

  const _PlaceholderTile({required this.isDark, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F2F5),
    );
  }
}
