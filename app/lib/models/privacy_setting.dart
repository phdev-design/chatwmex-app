import 'package:flutter/foundation.dart';

/// Flutter model for user global privacy settings.
/// Validates: Requirements 1.1, 1.2, 1.3
class PrivacySetting {
  /// 0=Everyone, 1=Contacts, 2=Nobody
  final int lastSeenPrivacy;

  /// 0=Everyone, 1=Contacts, 2=Nobody
  final int onlineStatusPrivacy;

  /// 0=Everyone, 1=Contacts, 2=Nobody
  final int profilePhotoPrivacy;

  final bool readReceiptsEnabled;

  const PrivacySetting({
    this.lastSeenPrivacy = 0,
    this.onlineStatusPrivacy = 0,
    this.profilePhotoPrivacy = 0,
    this.readReceiptsEnabled = true,
  });

  factory PrivacySetting.fromJson(Map<String, dynamic> json) {
    return PrivacySetting(
      lastSeenPrivacy: json['last_seen_privacy'] as int? ?? 0,
      onlineStatusPrivacy: json['online_status_privacy'] as int? ?? 0,
      profilePhotoPrivacy: json['profile_photo_privacy'] as int? ?? 0,
      readReceiptsEnabled: json['read_receipts_enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'last_seen_privacy': lastSeenPrivacy,
      'online_status_privacy': onlineStatusPrivacy,
      'profile_photo_privacy': profilePhotoPrivacy,
      'read_receipts_enabled': readReceiptsEnabled,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrivacySetting &&
        other.lastSeenPrivacy == lastSeenPrivacy &&
        other.onlineStatusPrivacy == onlineStatusPrivacy &&
        other.profilePhotoPrivacy == profilePhotoPrivacy &&
        other.readReceiptsEnabled == readReceiptsEnabled;
  }

  @override
  int get hashCode => Object.hash(
        lastSeenPrivacy,
        onlineStatusPrivacy,
        profilePhotoPrivacy,
        readReceiptsEnabled,
      );

  @override
  String toString() =>
      'PrivacySetting(lastSeenPrivacy: $lastSeenPrivacy, '
      'onlineStatusPrivacy: $onlineStatusPrivacy, '
      'profilePhotoPrivacy: $profilePhotoPrivacy, '
      'readReceiptsEnabled: $readReceiptsEnabled)';
}
