import 'package:app/features/chat/providers/room_media_provider.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class LinksTabContent extends ConsumerStatefulWidget {
  final String roomId;

  const LinksTabContent({super.key, required this.roomId});

  @override
  ConsumerState<LinksTabContent> createState() => _LinksTabContentState();
}

class _LinksTabContentState extends ConsumerState<LinksTabContent> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    final arg = (roomId: widget.roomId, type: 'link');
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
      final arg = (roomId: widget.roomId, type: 'link');
      ref.read(roomMediaProvider(arg).notifier).loadMore();
    }
  }

  Future<void> _openUrl(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final arg = (roomId: widget.roomId, type: 'link');
    final state = ref.watch(roomMediaProvider(arg));
    final grouped = ref.read(roomMediaProvider(arg).notifier).groupedMessages;
    final cs = Theme.of(context).colorScheme;

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
                Icons.link,
                size: 48,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '尚無連結',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '此聊天室分享的連結\n會顯示在這裡',
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

    // ── List ──────────────────────────────────────────────────────────────────
    final slivers = <Widget>[];
    
    for (final entry in grouped.entries) {
      final allUrlsInGroup = <String>[];
      final failedDecryptions = <int>[];
      
      for (final message in entry.value) {
        final urls = extractAllUrls(message.content);
        // Check if content is encrypted but failed to decrypt
        if (urls.isEmpty && message.content.length >= 40 && 
            (message.content.contains('+') || message.content.contains('/') || message.content.contains('='))) {
          failedDecryptions.add(allUrlsInGroup.length);
          allUrlsInGroup.add(''); // Placeholder for failed decryption
        } else {
          allUrlsInGroup.addAll(urls);
        }
      }
      
      if (allUrlsInGroup.isEmpty) continue;
      
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
      
      // Links list
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList.builder(
            itemCount: allUrlsInGroup.length,
            itemBuilder: (context, index) {
              final url = allUrlsInGroup[index];
              
              // Check if this is a failed decryption
              if (failedDecryptions.contains(index) || url.isEmpty) {
                return _DecryptionFailedCard(cs: cs);
              }
              
              final uri = Uri.tryParse(url);
              final domain = uri?.host ?? '';
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 0,
                  child: InkWell(
                    onTap: () => _openUrl(url),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.link,
                              color: cs.onPrimaryContainer,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (domain.isNotEmpty)
                                  Text(
                                    domain,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                const SizedBox(height: 2),
                                Text(
                                  url,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface.withValues(alpha: 0.6),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.open_in_new,
                            size: 18,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
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

// ── Decryption failed card ────────────────────────────────────────────────────

class _DecryptionFailedCard extends StatelessWidget {
  final ColorScheme cs;

  const _DecryptionFailedCard({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border.all(
            color: cs.error.withValues(alpha: 0.2),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.lock_outline,
                color: cs.error.withValues(alpha: 0.6),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '連結未能解密',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '無法讀取此連結',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.error_outline,
              size: 18,
              color: cs.error.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
