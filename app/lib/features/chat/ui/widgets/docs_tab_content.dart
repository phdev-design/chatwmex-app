import 'package:app/features/chat/providers/room_media_provider.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _openDoc(String content) async {
    final resolved = resolveFullUrl(content);
    final uri = Uri.tryParse(resolved);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final arg = (roomId: widget.roomId, type: 'doc');
    final state = ref.watch(roomMediaProvider(arg));
    final grouped = ref.read(roomMediaProvider(arg).notifier).groupedMessages;

    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (grouped.isEmpty) {
      return const Center(child: Text('No docs yet'));
    }

    final slivers = <Widget>[];
    for (final entry in grouped.entries) {
      if (entry.value.isEmpty) continue;
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(
              entry.key,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList.builder(
            itemCount: entry.value.length,
            itemBuilder: (context, index) {
              final msg = entry.value[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(
                    _fileNameFromContent(msg.content),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    resolveFullUrl(msg.content),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _openDoc(msg.content),
                ),
              );
            },
          ),
        ),
      );
    }

    if (state.isLoadingMore) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }
    return CustomScrollView(controller: _scrollController, slivers: slivers);
  }
}
