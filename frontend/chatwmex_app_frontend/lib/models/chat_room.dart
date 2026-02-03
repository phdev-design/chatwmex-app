import 'dart:convert';

class ChatRoom {
  final String id;
  final String name;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final String? avatarUrl;
  final bool isGroup;
  final List<String> participants;

  ChatRoom({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.avatarUrl,
    this.isGroup = false,
    this.participants = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime.toIso8601String(),
      'unread_count': unreadCount,
      'avatar_url': avatarUrl,
      'is_group': isGroup ? 1 : 0, // SQLite doesn't have boolean
      'participants': jsonEncode(participants),
    };
  }

  factory ChatRoom.fromMap(Map<String, dynamic> map) {
    return ChatRoom(
      id: map['id'],
      name: map['name'],
      lastMessage: map['last_message'],
      lastMessageTime: DateTime.parse(map['last_message_time']),
      unreadCount: map['unread_count'],
      avatarUrl: map['avatar_url'],
      isGroup: map['is_group'] == 1,
      participants: List<String>.from(jsonDecode(map['participants'])),
    );
  }

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      lastMessage: json['last_message'] ?? '',
      lastMessageTime: DateTime.parse(json['last_message_time'] ?? DateTime.now().toIso8601String()),
      unreadCount: json['unread_count'] ?? 0,
      avatarUrl: json['avatar_url'],
      isGroup: json['is_group'] ?? false,
      participants: List<String>.from(json['participants'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime.toIso8601String(),
      'unread_count': unreadCount,
      'avatar_url': avatarUrl,
      'is_group': isGroup,
      'participants': participants,
    };
  }

  ChatRoom copyWith({
    String? id,
    String? name,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    String? avatarUrl,
    bool? isGroup,
    List<String>? participants,
  }) {
    return ChatRoom(
      id: id ?? this.id,
      name: name ?? this.name,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isGroup: isGroup ?? this.isGroup,
      participants: participants ?? this.participants,
    );
  }
}