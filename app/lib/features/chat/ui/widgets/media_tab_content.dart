import 'package:app/features/chat/providers/room_media_provider.dart';
import 'package:app/features/chat/utils/chat_url_utils.dart';
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

    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (grouped.isEmpty) {
      return const Center(child: Text('No media yet'));
    }

    final slivers = <Widget>[];
    for (final entry in grouped.entries) {
      final mediaMessages = entry.value
          .where(
            (m) => m.type == MessageType.image || m.type == MessageType.video,
          )
          .toList();
      if (mediaMessages.isEmpty) continue;
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
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final message = mediaMessages[index];
              final url = resolveFullUrl(message.content);
              if (url.isEmpty) {
                return Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    );
                  },
                ),
              );
            }, childCount: mediaMessages.length),
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
