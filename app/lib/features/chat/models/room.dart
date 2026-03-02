import 'package:equatable/equatable.dart';

class Room extends Equatable {
  final String id;
  final String name;
  final String? type; // 'group' or 'dm'
  final DateTime createdAt;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final DateTime? lastReadAt;

  const Room({
    required this.id,
    required this.name,
    this.type,
    required this.createdAt,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.lastReadAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Room',
      type: json['type'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      lastMessage: json['last_message'],
      lastMessageTime: json['last_message_time'] != null 
          ? DateTime.tryParse(json['last_message_time']) 
          : null,
      unreadCount: json['unread_count'] ?? 0,
      lastReadAt: json['last_read_at'] != null
          ? DateTime.tryParse(json['last_read_at'])
          : null,
    );
  }

  Room copyWith({
    String? id,
    String? name,
    String? type,
    DateTime? createdAt,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    DateTime? lastReadAt,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    type,
    createdAt,
    lastMessage,
    lastMessageTime,
    unreadCount,
    lastReadAt,
  ];
}

class User extends Equatable {
  final String id;
  final String username;
  final String email;
  final String? phoneNumber;

  const User({
    required this.id,
    required this.username,
    required this.email,
    this.phoneNumber,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phone_number'],
    );
  }

  @override
  List<Object?> get props => [id, username, email, phoneNumber];
}
