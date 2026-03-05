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

    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (grouped.isEmpty) {
      return const Center(child: Text('No links yet'));
    }

    final slivers = <Widget>[];
    for (final entry in grouped.entries) {
      final allUrlsInGroup = <String>[];
      for (final message in entry.value) {
        allUrlsInGroup.addAll(extractAllUrls(message.content));
      }
      if (allUrlsInGroup.isEmpty) continue;
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
            itemCount: allUrlsInGroup.length,
            itemBuilder: (context, index) {
              final url = allUrlsInGroup[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(
                    url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _openUrl(url),
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
