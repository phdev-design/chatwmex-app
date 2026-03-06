import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/providers/room_label_provider.dart';
import 'package:app/features/chat/ui/room_label_detail_page.dart';

class RoomLabelsSettingsPage extends ConsumerWidget {
  const RoomLabelsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labelsAsync = ref.watch(roomLabelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('分類名單'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateLabelDialog(context, ref),
          ),
        ],
      ),
      body: labelsAsync.when(
        data: (labels) {
          if (labels.isEmpty) {
            return const Center(child: Text('目前沒有自定義分類'));
          }
          return ReorderableListView.builder(
            itemCount: labels.length,
            onReorder: (oldIndex, newIndex) {
              if (oldIndex < newIndex) newIndex -= 1;
              final item = labels.removeAt(oldIndex);
              labels.insert(newIndex, item);
              
              final orderedIds = labels.map((e) => e.id).toList();
              ref.read(roomLabelProvider.notifier).reorderLabels(orderedIds);
            },
            itemBuilder: (context, index) {
              final label = labels[index];
              return Dismissible(
                key: ValueKey(label.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (direction) => _confirmDelete(context, label.name),
                onDismissed: (direction) {
                  ref.read(roomLabelProvider.notifier).deleteLabel(label.id);
                },
                child: ListTile(
                  leading: const Icon(Icons.drag_handle, color: Colors.grey),
                  title: Text(label.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${label.roomIds.length} 個對話'),
                  trailing: Switch(
                    value: label.isEnabled,
                    onChanged: (val) {
                      ref.read(roomLabelProvider.notifier).updateLabel(
                            label.id,
                            label.name,
                            val,
                          );
                    },
                    activeThumbColor: Colors.blueAccent,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RoomLabelDetailPage(label: label),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('載入失敗: $err')),
      ),
    );
  }

  Future<void> _showCreateLabelDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text('新增分類', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '分類名稱',
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  ref.read(roomLabelProvider.notifier).createLabel(text);
                }
                Navigator.pop(context);
              },
              child: const Text('新增', style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('刪除分類', style: TextStyle(color: Colors.white)),
        content: Text('確定要刪除「$name」嗎？', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
