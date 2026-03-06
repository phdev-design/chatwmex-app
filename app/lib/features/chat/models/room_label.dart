class RoomLabel {
  final String id;
  final String name;
  final int sortOrder;
  final List<String> roomIds;
  final bool isEnabled;

  const RoomLabel({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.roomIds,
    required this.isEnabled,
  });

  factory RoomLabel.fromJson(Map<String, dynamic> json) => RoomLabel(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    sortOrder: json['sort_order'] ?? 0,
    roomIds: List<String>.from(json['room_ids'] ?? []),
    isEnabled: json['is_enabled'] ?? true,
  );

  RoomLabel copyWith({String? name, bool? isEnabled, List<String>? roomIds}) =>
    RoomLabel(
      id: id,
      name: name ?? this.name,
      sortOrder: sortOrder,
      roomIds: roomIds ?? this.roomIds,
      isEnabled: isEnabled ?? this.isEnabled,
    );
}
