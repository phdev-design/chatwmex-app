import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/models/room_label.dart';
import 'package:app/features/chat/providers/room_label_provider.dart';
import 'package:app/features/chat/providers/room_list_provider.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';

class RoomLabelDetailPage extends ConsumerStatefulWidget {
  final RoomLabel label;

  const RoomLabelDetailPage({super.key, required this.label});

  @override
  ConsumerState<RoomLabelDetailPage> createState() =>
      _RoomLabelDetailPageState();
}

class _RoomLabelDetailPageState extends ConsumerState<RoomLabelDetailPage> {
  late TextEditingController _nameController;
  late bool _isEnabled;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.label.name);
    _isEnabled = widget.label.isEnabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveBasicSettings() {
    final newName = _nameController.text.trim();
    if (newName.isNotEmpty) {
      ref
          .read(roomLabelProvider.notifier)
          .updateLabel(widget.label.id, newName, _isEnabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Current live status of the label
    final allLabels = ref.watch(roomLabelProvider).valueOrNull ?? [];
    final currentLabel = allLabels.firstWhere(
      (l) => l.id == widget.label.id,
      orElse: () => widget.label,
    );

    final roomListState = ref.watch(roomListViewModelProvider);
    final rooms = roomListState.rooms;

    return Scaffold(
      appBar: AppBar(title: const Text('編輯分類')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '基本設定',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            color: const Color(0xFF1C1C1E),
            child: Column(
              children: [
                ListTile(
                  title: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '分類名稱',
                      border: InputBorder.none,
                    ),
                    onEditingComplete: () {
                      FocusScope.of(context).unfocus();
                      _saveBasicSettings();
                    },
                  ),
                ),
                const Divider(height: 1, color: Colors.white24),
                SwitchListTile(
                  title: const Text('啟用此分類'),
                  value: _isEnabled,
                  activeThumbColor: Colors.blueAccent,
                  onChanged: (val) {
                    setState(() => _isEnabled = val);
                    _saveBasicSettings();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '包含的對話',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            color: const Color(0xFF1C1C1E),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                final isIncluded = currentLabel.roomIds.contains(room.id);

                return CheckboxListTile(
                  secondary: ChatAvatar(
                    avatarUrl: room.avatarUrl,
                    radius: 16,
                    fallbackText: room.name.isNotEmpty
                        ? room.name[0].toUpperCase()
                        : '?',
                    fallbackIcon: room.type == 'group' ? Icons.group : null,
                    logTag: 'label_detail',
                  ),
                  title: Text(
                    room.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  activeColor: Colors.blueAccent,
                  value: isIncluded,
                  onChanged: (val) {
                    if (val == true) {
                      ref
                          .read(roomLabelProvider.notifier)
                          .addRoomToLabel(currentLabel.id, room.id);
                    } else {
                      ref
                          .read(roomLabelProvider.notifier)
                          .removeRoomFromLabel(currentLabel.id, room.id);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
