import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/privacy_setting.dart';

/// Unit tests for PrivacySetting model
/// Validates: Requirements 1.1, 1.2

void main() {
  group('testPrivacySettingFromJson', () {
    test('deserializes all fields correctly', () {
      final json = {
        'last_seen_privacy': 1,
        'online_status_privacy': 2,
        'profile_photo_privacy': 0,
        'read_receipts_enabled': false,
      };

      final setting = PrivacySetting.fromJson(json);

      expect(setting.lastSeenPrivacy, equals(1));
      expect(setting.onlineStatusPrivacy, equals(2));
      expect(setting.profilePhotoPrivacy, equals(0));
      expect(setting.readReceiptsEnabled, isFalse);
    });

    test('uses default values when fields are missing', () {
      final setting = PrivacySetting.fromJson({});

      expect(setting.lastSeenPrivacy, equals(0));
      expect(setting.onlineStatusPrivacy, equals(0));
      expect(setting.profilePhotoPrivacy, equals(0));
      expect(setting.readReceiptsEnabled, isTrue);
    });

    test('uses default values when fields are null', () {
      final json = {
        'last_seen_privacy': null,
        'online_status_privacy': null,
        'profile_photo_privacy': null,
        'read_receipts_enabled': null,
      };

      final setting = PrivacySetting.fromJson(json);

      expect(setting.lastSeenPrivacy, equals(0));
      expect(setting.onlineStatusPrivacy, equals(0));
      expect(setting.profilePhotoPrivacy, equals(0));
      expect(setting.readReceiptsEnabled, isTrue);
    });

    test('deserializes privacy level Nobody (2) correctly', () {
      final json = {
        'last_seen_privacy': 2,
        'online_status_privacy': 2,
        'profile_photo_privacy': 2,
        'read_receipts_enabled': false,
      };

      final setting = PrivacySetting.fromJson(json);

      expect(setting.lastSeenPrivacy, equals(2));
      expect(setting.onlineStatusPrivacy, equals(2));
      expect(setting.profilePhotoPrivacy, equals(2));
      expect(setting.readReceiptsEnabled, isFalse);
    });
  });

  group('testPrivacySettingToJson', () {
    test('round-trip: serialize then deserialize yields equal object', () {
      const original = PrivacySetting(
        lastSeenPrivacy: 1,
        onlineStatusPrivacy: 2,
        profilePhotoPrivacy: 0,
        readReceiptsEnabled: false,
      );

      final json = original.toJson();
      final restored = PrivacySetting.fromJson(json);

      expect(restored, equals(original));
    });

    test('round-trip with default values yields equal object', () {
      const original = PrivacySetting();

      final json = original.toJson();
      final restored = PrivacySetting.fromJson(json);

      expect(restored, equals(original));
    });

    test('toJson produces correct keys and values', () {
      const setting = PrivacySetting(
        lastSeenPrivacy: 1,
        onlineStatusPrivacy: 0,
        profilePhotoPrivacy: 2,
        readReceiptsEnabled: true,
      );

      final json = setting.toJson();

      expect(json['last_seen_privacy'], equals(1));
      expect(json['online_status_privacy'], equals(0));
      expect(json['profile_photo_privacy'], equals(2));
      expect(json['read_receipts_enabled'], isTrue);
    });

    test('round-trip preserves all privacy levels (0, 1, 2)', () {
      for (final level in [0, 1, 2]) {
        final original = PrivacySetting(
          lastSeenPrivacy: level,
          onlineStatusPrivacy: level,
          profilePhotoPrivacy: level,
        );
        final restored = PrivacySetting.fromJson(original.toJson());
        expect(restored, equals(original),
            reason: 'Round-trip failed for privacy level $level');
      }
    });
  });
}
