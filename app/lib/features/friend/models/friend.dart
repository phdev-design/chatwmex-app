import 'package:equatable/equatable.dart';

class Friend extends Equatable {
  final String id;
  final String username;
  final String email;

  const Friend({
    required this.id,
    required this.username,
    required this.email,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
    );
  }

  @override
  List<Object?> get props => [id, username, email];
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
