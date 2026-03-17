import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/privacy/repositories/privacy_setting_repository.dart';
import 'package:app/models/privacy_setting.dart';

/// Unit tests for PrivacySettingRepository
/// Validates: Requirements 6.1, 6.2

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Dio [HttpClientAdapter] that returns a canned response without touching
/// the network.
class _FakeAdapter implements HttpClientAdapter {
  final int statusCode;
  final String body;
  final List<RequestOptions>? capturedRequests;

  _FakeAdapter({
    required this.statusCode,
    required this.body,
    this.capturedRequests,
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequests?.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Builds a [PrivacySettingRepository] backed by a fake Dio whose adapter
/// returns [responseData] for any request.
PrivacySettingRepository _makeRepo({
  required Map<String, dynamic> responseData,
  int statusCode = 200,
  List<RequestOptions>? capturedRequests,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080/api/v1'));
  dio.httpClientAdapter = _FakeAdapter(
    statusCode: statusCode,
    body: jsonEncode(responseData),
    capturedRequests: capturedRequests,
  );
  return PrivacySettingRepository(dio);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PrivacySettingRepository.getPrivacySetting', () {
    test('parses a full response correctly', () async {
      final repo = _makeRepo(responseData: {
        'data': {
          'last_seen_privacy': 1,
          'online_status_privacy': 2,
          'profile_photo_privacy': 0,
          'read_receipts_enabled': false,
        },
      });

      final result = await repo.getPrivacySetting();

      expect(result.lastSeenPrivacy, equals(1));
      expect(result.onlineStatusPrivacy, equals(2));
      expect(result.profilePhotoPrivacy, equals(0));
      expect(result.readReceiptsEnabled, isFalse);
    });

    test('uses default values when fields are missing from response', () async {
      final repo = _makeRepo(responseData: {'data': {}});

      final result = await repo.getPrivacySetting();

      expect(result.lastSeenPrivacy, equals(0));
      expect(result.onlineStatusPrivacy, equals(0));
      expect(result.profilePhotoPrivacy, equals(0));
      expect(result.readReceiptsEnabled, isTrue);
    });

    test('sends GET request to /privacy-settings', () async {
      final captured = <RequestOptions>[];
      final repo = _makeRepo(
        responseData: {'data': {}},
        capturedRequests: captured,
      );

      await repo.getPrivacySetting();

      expect(captured, hasLength(1));
      expect(captured.first.method, equals('GET'));
      expect(captured.first.path, contains('/privacy-settings'));
    });

    test('returns a PrivacySetting equal to the one built from the same JSON',
        () async {
      const json = {
        'last_seen_privacy': 2,
        'online_status_privacy': 1,
        'profile_photo_privacy': 0,
        'read_receipts_enabled': true,
      };
      final repo = _makeRepo(responseData: {'data': json});

      final result = await repo.getPrivacySetting();

      expect(result, equals(PrivacySetting.fromJson(json)));
    });
  });

  group('PrivacySettingRepository.updatePrivacySetting', () {
    test('sends correct JSON body for a full update', () async {
      const updatedJson = {
        'last_seen_privacy': 1,
        'online_status_privacy': 0,
        'profile_photo_privacy': 2,
        'read_receipts_enabled': false,
      };
      final captured = <RequestOptions>[];
      final repo = _makeRepo(
        responseData: {'data': updatedJson},
        capturedRequests: captured,
      );

      const req = UpdatePrivacySettingRequest(
        lastSeenPrivacy: 1,
        onlineStatusPrivacy: 0,
        profilePhotoPrivacy: 2,
        readReceiptsEnabled: false,
      );
      await repo.updatePrivacySetting(req);

      expect(captured, hasLength(1));
      expect(captured.first.method, equals('PUT'));
      expect(captured.first.path, contains('/privacy-settings'));

      final sentBody = captured.first.data as Map<String, dynamic>;
      expect(sentBody['last_seen_privacy'], equals(1));
      expect(sentBody['online_status_privacy'], equals(0));
      expect(sentBody['profile_photo_privacy'], equals(2));
      expect(sentBody['read_receipts_enabled'], isFalse);
    });

    test('returns the updated PrivacySetting parsed from the response',
        () async {
      const updatedJson = {
        'last_seen_privacy': 2,
        'online_status_privacy': 2,
        'profile_photo_privacy': 2,
        'read_receipts_enabled': false,
      };
      final repo = _makeRepo(responseData: {'data': updatedJson});

      const req = UpdatePrivacySettingRequest(
        lastSeenPrivacy: 2,
        onlineStatusPrivacy: 2,
        profilePhotoPrivacy: 2,
        readReceiptsEnabled: false,
      );
      final result = await repo.updatePrivacySetting(req);

      expect(result, equals(PrivacySetting.fromJson(updatedJson)));
    });

    test('only sends non-null fields in a partial update', () async {
      final captured = <RequestOptions>[];
      final repo = _makeRepo(
        responseData: {
          'data': {
            'last_seen_privacy': 1,
            'online_status_privacy': 0,
            'profile_photo_privacy': 0,
            'read_receipts_enabled': true,
          },
        },
        capturedRequests: captured,
      );

      // Only update lastSeenPrivacy
      const req = UpdatePrivacySettingRequest(lastSeenPrivacy: 1);
      await repo.updatePrivacySetting(req);

      final sentBody = captured.first.data as Map<String, dynamic>;
      expect(sentBody.containsKey('last_seen_privacy'), isTrue);
      expect(sentBody.containsKey('online_status_privacy'), isFalse);
      expect(sentBody.containsKey('profile_photo_privacy'), isFalse);
      expect(sentBody.containsKey('read_receipts_enabled'), isFalse);
    });

    test('sends PUT request to /privacy-settings', () async {
      final captured = <RequestOptions>[];
      final repo = _makeRepo(
        responseData: {'data': {}},
        capturedRequests: captured,
      );

      await repo.updatePrivacySetting(const UpdatePrivacySettingRequest());

      expect(captured.first.method, equals('PUT'));
      expect(captured.first.path, contains('/privacy-settings'));
    });
  });

  group('UpdatePrivacySettingRequest.toJson', () {
    test('empty request produces empty map', () {
      const req = UpdatePrivacySettingRequest();
      expect(req.toJson(), isEmpty);
    });

    test('only includes non-null fields', () {
      const req = UpdatePrivacySettingRequest(readReceiptsEnabled: true);
      final json = req.toJson();
      expect(json, equals({'read_receipts_enabled': true}));
    });

    test('full request includes all fields', () {
      const req = UpdatePrivacySettingRequest(
        lastSeenPrivacy: 0,
        onlineStatusPrivacy: 1,
        profilePhotoPrivacy: 2,
        readReceiptsEnabled: false,
      );
      final json = req.toJson();
      expect(json['last_seen_privacy'], equals(0));
      expect(json['online_status_privacy'], equals(1));
      expect(json['profile_photo_privacy'], equals(2));
      expect(json['read_receipts_enabled'], isFalse);
    });
  });
}
