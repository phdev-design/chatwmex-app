import 'package:equatable/equatable.dart';

class Room extends Equatable {
  final String id;
  final String name;
  final String? type; // 'group' or 'dm'
  final DateTime createdAt;

  const Room({
    required this.id,
    required this.name,
    this.type,
    required this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Room',
      type: json['type'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, name, type, createdAt];
}

class User extends Equatable {
  final String id;
  final String username;
  final String email;

  const User({
    required this.id,
    required this.username,
    required this.email,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
    );
  }

  @override
  List<Object?> get props => [id, username, email];
}
