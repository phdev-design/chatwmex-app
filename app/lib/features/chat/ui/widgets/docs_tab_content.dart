import 'package:app/features/chat/providers/room_media_provider.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app/features/chat/ui/pdf_preview_screen.dart';

class DocsTabContent extends ConsumerStatefulWidget {
  final String roomId;

  const DocsTabContent({super.key, required this.roomId});

  @override
  ConsumerState<DocsTabContent> createState() => _DocsTabContentState();
}

class _DocsTabContentState extends ConsumerState<DocsTabContent> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    final arg = (roomId: widget.roomId, type: 'doc');
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
      final arg = (roomId: widget.roomId, type: 'doc');
      ref.read(roomMediaProvider(arg).notifier).loadMore();
    }
  }

  String _fileNameFromContent(String content) {
    final resolved = resolveFullUrl(content);
    final uri = Uri.tryParse(resolved);
    if (uri == null) return content;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return content;
    return segments.last;
  }

  String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    if (parts.length > 1) {
      return parts.last.toUpperCase();
    }
    return 'FILE';
  }

  Future<void> _openDoc(BuildContext context, String content) async {
    final resolved = resolveFullUrl(content);
    final uri = Uri.tryParse(resolved);
    if (uri == null) return;

    final fileName = _fileNameFromContent(content);
    if (fileName.toLowerCase().endsWith('.pdf')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PdfPreviewScreen(pdfUrl: resolved, fileName: fileName),
        ),
      );
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final arg = (roomId: widget.roomId, type: 'doc');
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
                Icons.insert_drive_file_outlined,
                size: 48,
                color: cs.onSurface.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '尚無文件',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '此聊天室分享的文件\n會顯示在這裡',
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
      
      // Documents list
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList.builder(
            itemCount: entry.value.length,
            itemBuilder: (context, index) {
              final msg = entry.value[index];
              final resolved = resolveFullUrl(msg.content);
              
              // Check if decryption failed
              if (resolved.isEmpty) {
                return _DecryptionFailedCard(cs: cs);
              }
              
              final fileName = _fileNameFromContent(msg.content);
              final fileExt = _getFileExtension(fileName);
              final isPdf = fileName.toLowerCase().endsWith('.pdf');

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 0,
                  child: InkWell(
                    onTap: () => _openDoc(context, msg.content),
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
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isPdf
                                  ? Colors.red.withValues(alpha: 0.1)
                                  : cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isPdf
                                      ? Icons.picture_as_pdf
                                      : Icons.insert_drive_file,
                                  color: isPdf
                                      ? Colors.red
                                      : cs.onSecondaryContainer,
                                  size: 20,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  fileExt,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w600,
                                    color: isPdf
                                        ? Colors.red
                                        : cs.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fileName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isPdf ? 'PDF 文件' : '文件',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.6),
                                  ),
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
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.lock_outline,
                color: cs.error.withValues(alpha: 0.6),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '檔案未能解密',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '無法讀取此文件',
                    style: TextStyle(
                      fontSize: 12,
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
