import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/features/chat/models/room_label.dart';

class RoomLabelNotifier extends AsyncNotifier<List<RoomLabel>> {
  @override
  Future<List<RoomLabel>> build() async {
    return _fetchLabels();
  }

  Future<List<RoomLabel>> _fetchLabels() async {
    final network = ref.read(networkServiceProvider);
    final response = await network.client.get('/labels');
    if (response.statusCode == 200) {
      final data = response.data; // Dio already parses JSON
      if (data['data'] != null) {
        final List<dynamic> listBytes = data['data'];
        final labels = listBytes.map((e) => RoomLabel.fromJson(e)).toList();
        labels.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return labels;
      }
    }
    return [];
  }

  Future<void> createLabel(String name) async {
    final network = ref.read(networkServiceProvider);
    final response = await network.client.post(
      '/labels',
      data: {'name': name},
    );
    if (response.statusCode == 200) {
      ref.invalidateSelf();
    } else {
      throw Exception('Failed to create label: ${response.data}');
    }
  }

  Future<void> updateLabel(String id, String name, bool isEnabled) async {
    final network = ref.read(networkServiceProvider);
    final response = await network.client.put(
      '/labels/$id',
      data: {'name': name, 'is_enabled': isEnabled},
    );
    if (response.statusCode == 200) {
      ref.invalidateSelf();
    } else {
      throw Exception('Failed to update label: ${response.data}');
    }
  }

  Future<void> deleteLabel(String id) async {
    final network = ref.read(networkServiceProvider);
    final response = await network.client.delete('/labels/$id');
    if (response.statusCode == 200) {
      ref.invalidateSelf();
    } else {
      throw Exception('Failed to delete label: ${response.data}');
    }
  }

  Future<void> reorderLabels(List<String> orderedIds) async {
    // Optimistic Update
    final prev = state.valueOrNull;
    if (prev != null) {
      final map = {for (var item in prev) item.id: item};
      final newList = <RoomLabel>[];
      for (int i = 0; i < orderedIds.length; i++) {
        final id = orderedIds[i];
        if (map.containsKey(id)) {
           // We keep the object, but essentially the list order is what matters
           newList.add(map[id]!);
        }
      }
      state = AsyncValue.data(newList);
    }

    final network = ref.read(networkServiceProvider);
    final response = await network.client.put(
      '/labels/reorder',
      data: {'ordered_ids': orderedIds},
    );
    if (response.statusCode != 200) {
       ref.invalidateSelf(); // Revert on failure
       throw Exception('Failed to reorder labels: ${response.data}');
    }
  }

  Future<void> addRoomToLabel(String labelId, String roomId) async {
    final network = ref.read(networkServiceProvider);
    final response = await network.client.post(
      '/labels/$labelId/rooms',
      data: {'room_id': roomId},
    );
    if (response.statusCode == 200) {
       ref.invalidateSelf();
    } else {
       throw Exception('Failed to add room to label: ${response.data}');
    }
  }

  Future<void> removeRoomFromLabel(String labelId, String roomId) async {
    final network = ref.read(networkServiceProvider);
    final response = await network.client.delete(
      '/labels/$labelId/rooms/$roomId',
    );
    if (response.statusCode == 200) {
       ref.invalidateSelf();
    } else {
       throw Exception('Failed to remove room from label: ${response.data}');
    }
  }
}

final roomLabelProvider = AsyncNotifierProvider<RoomLabelNotifier, List<RoomLabel>>(
  RoomLabelNotifier.new,
);
