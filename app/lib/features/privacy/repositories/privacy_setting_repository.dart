import 'package:app/core/network/network_service.dart';
import 'package:app/models/privacy_setting.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Partial update DTO — all fields are nullable; only non-null fields are sent.
class UpdatePrivacySettingRequest {
  final int? lastSeenPrivacy;
  final int? onlineStatusPrivacy;
  final int? profilePhotoPrivacy;
  final bool? readReceiptsEnabled;

  const UpdatePrivacySettingRequest({
    this.lastSeenPrivacy,
    this.onlineStatusPrivacy,
    this.profilePhotoPrivacy,
    this.readReceiptsEnabled,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (lastSeenPrivacy != null) map['last_seen_privacy'] = lastSeenPrivacy;
    if (onlineStatusPrivacy != null) map['online_status_privacy'] = onlineStatusPrivacy;
    if (profilePhotoPrivacy != null) map['profile_photo_privacy'] = profilePhotoPrivacy;
    if (readReceiptsEnabled != null) map['read_receipts_enabled'] = readReceiptsEnabled;
    return map;
  }
}

/// Repository for fetching and updating the current user's global privacy settings.
/// Validates: Requirements 6.1, 6.2, 6.3
class PrivacySettingRepository {
  final Dio _client;

  /// Creates a repository using the provided [Dio] client.
  /// In production, pass [NetworkService.client] which auto-attaches the JWT
  /// auth header via its interceptor.
  PrivacySettingRepository(this._client);

  /// GET /api/v1/privacy-settings — returns the current user's PrivacySetting.
  Future<PrivacySetting> getPrivacySetting() async {
    final response = await _client.get('/privacy-settings');
    final data = response.data['data'] as Map<String, dynamic>;
    return PrivacySetting.fromJson(data);
  }

  /// PUT /api/v1/privacy-settings — sends a partial update and returns the
  /// updated [PrivacySetting].
  Future<PrivacySetting> updatePrivacySetting(
    UpdatePrivacySettingRequest req,
  ) async {
    final response = await _client.put(
      '/privacy-settings',
      data: req.toJson(),
    );
    final data = response.data['data'] as Map<String, dynamic>;
    return PrivacySetting.fromJson(data);
  }
}

final privacySettingRepositoryProvider = Provider<PrivacySettingRepository>((ref) {
  final network = ref.watch(networkServiceProvider);
  return PrivacySettingRepository(network.client);
});
