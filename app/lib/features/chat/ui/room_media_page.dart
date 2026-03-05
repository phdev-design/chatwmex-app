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
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media, Links, and Docs'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Media'),
              Tab(text: 'Links'),
              Tab(text: 'Docs'),
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
