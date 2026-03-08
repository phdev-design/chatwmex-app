import 'package:equatable/equatable.dart';

class Friend extends Equatable {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final String? firstName;
  final String? lastName;
  final String? bio;

  const Friend({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    this.firstName,
    this.lastName,
    this.bio,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      avatarUrl: json['avatar_url'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      bio: json['bio'],
    );
  }

  Friend copyWith({
    String? id,
    String? username,
    String? email,
    String? avatarUrl,
    String? firstName,
    String? lastName,
    String? bio,
  }) {
    return Friend(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      bio: bio ?? this.bio,
    );
  }

  @override
  List<Object?> get props => [id, username, email, avatarUrl, firstName, lastName, bio];
}

enum FriendRequestStatus { pending, accepted, rejected }

class FriendRequest extends Equatable {
  final String id;
  final String senderId;
  final String senderUsername;
  final String receiverId;
  final FriendRequestStatus status;
  final DateTime createdAt;

  const FriendRequest({
    required this.id,
    required this.senderId,
    this.senderUsername = '',
    required this.receiverId,
    required this.status,
    required this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderUsername: json['sender_username'] ?? '',
      receiverId: json['receiver_id'] ?? '',
      status: _parseStatus(json['status']),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  static FriendRequestStatus _parseStatus(String? status) {
    switch (status) {
      case 'accepted':
        return FriendRequestStatus.accepted;
      case 'rejected':
        return FriendRequestStatus.rejected;
      default:
        return FriendRequestStatus.pending;
    }
  }

  @override
  List<Object?> get props => [id, senderId, senderUsername, receiverId, status, createdAt];
}
