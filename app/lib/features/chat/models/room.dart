import 'package:equatable/equatable.dart';

class Room extends Equatable {
  final String id;
  final String name;
  final String? type; // 'group' or 'dm'
  final String? avatarUrl;
  final String? ownerId; // 👉 新增這個欄位
  final DateTime createdAt;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final String? lastMessageType; // 👉 新增這個欄位
  final DateTime? lastReadAt;

  const Room({
    required this.id,
    required this.name,
    this.type,
    this.avatarUrl,
    this.ownerId,
    required this.createdAt,
    this.lastMessage,
    this.lastMessageType, // 👉 加入建構子
    this.lastMessageTime,
    this.unreadCount = 0,
    this.lastReadAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Room',
      type: json['type'],
      avatarUrl: json['avatar_url'],
      ownerId: json['owner_id'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      lastMessage: json['last_message'],
      lastMessageType: json['last_message_type'], // 👉 加入映射
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
    String? avatarUrl,
    String? ownerId,
    DateTime? createdAt,
    String? lastMessage,
    String? lastMessageType, // 👉 加入映射
    DateTime? lastMessageTime,
    int? unreadCount,
    DateTime? lastReadAt,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageType: lastMessageType ?? this.lastMessageType, // 👉 加入映射
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
    avatarUrl,
    ownerId,
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
  final String? firstName;
  final String? lastName;
  final String? bio;
  final String? avatarUrl;

  const User({
    required this.id,
    required this.username,
    required this.email,
    this.phoneNumber,
    this.firstName,
    this.lastName,
    this.bio,
    this.avatarUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phone_number'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      bio: json['bio'],
      avatarUrl: json['avatar_url'],
    );
  }

  @override
  List<Object?> get props => [
    id,
    username,
    email,
    phoneNumber,
    firstName,
    lastName,
    bio,
    avatarUrl,
  ];
}
