import 'package:app/features/chat/ui/widgets/docs_tab_content.dart';
import 'package:app/features/chat/ui/widgets/links_tab_content.dart';
import 'package:app/features/chat/ui/widgets/media_tab_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RoomMediaPage extends ConsumerStatefulWidget {
  final String roomId;

  const RoomMediaPage({super.key, required this.roomId});

  @override
  ConsumerState<RoomMediaPage> createState() => _RoomMediaPageState();
}

class _RoomMediaPageState extends ConsumerState<RoomMediaPage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('媒體、連結和文件'),
          bottom: TabBar(
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
            indicatorColor: cs.primary,
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            tabs: const [
              Tab(text: '媒體'),
              Tab(text: '連結'),
              Tab(text: '文件'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            MediaTabContent(roomId: widget.roomId),
            LinksTabContent(roomId: widget.roomId),
            DocsTabContent(roomId: widget.roomId),
          ],
        ),
      ),
    );
  }
}
