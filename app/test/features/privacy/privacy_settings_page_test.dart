import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/privacy/privacy_settings_page.dart';
import 'package:app/features/privacy/providers/privacy_settings_provider.dart';
import 'package:app/features/privacy/repositories/privacy_setting_repository.dart';
import 'package:app/models/privacy_setting.dart';

/// Widget tests for PrivacySettingsPage.
/// Validates: Requirements 1.4, 6.4

// ─── Fake notifier ────────────────────────────────────────────────────────────

/// Subclass of [PrivacySettingsNotifier] that captures [updateSettings] calls
/// and applies them locally without hitting the network.
class _FakePrivacySettingsNotifier extends PrivacySettingsNotifier {
  _FakePrivacySettingsNotifier(this._initial);

  final PrivacySetting _initial;
  final List<UpdatePrivacySettingRequest> capturedRequests = [];

  @override
  Future<PrivacySetting> build() async => _initial;

  @override
  Future<void> updateSettings(UpdatePrivacySettingRequest req) async {
    capturedRequests.add(req);
    final current = state.valueOrNull ?? _initial;
    state = AsyncData(PrivacySetting(
      lastSeenPrivacy: req.lastSeenPrivacy ?? current.lastSeenPrivacy,
      onlineStatusPrivacy:
          req.onlineStatusPrivacy ?? current.onlineStatusPrivacy,
      profilePhotoPrivacy:
          req.profilePhotoPrivacy ?? current.profilePhotoPrivacy,
      readReceiptsEnabled:
          req.readReceiptsEnabled ?? current.readReceiptsEnabled,
    ));
  }
}

// ─── Test helpers ─────────────────────────────────────────────────────────────

Widget _buildTestApp(_FakePrivacySettingsNotifier notifier) {
  return ProviderScope(
    overrides: [
      privacySettingsProvider.overrideWith(() => notifier),
    ],
    child: const MaterialApp(
      home: PrivacySettingsPage(),
    ),
  );
}

/// Pump the widget with a tall viewport so all list items are rendered.
Future<void> _pumpTall(
  WidgetTester tester,
  _FakePrivacySettingsNotifier notifier,
) async {
  // Use a tall surface so the entire ListView is rendered at once.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_buildTestApp(notifier));
  await tester.pumpAndSettle();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('testPrivacySettingScreen_displaysCurrentValues', () {
    /// Validates: Requirements 1.4

    testWidgets(
      'displays Last Seen radio selection matching repository value',
      (tester) async {
        const settings = PrivacySetting(
          lastSeenPrivacy: 1, // My Contacts
          onlineStatusPrivacy: 0,
          profilePhotoPrivacy: 2,
          readReceiptsEnabled: false,
        );
        final notifier = _FakePrivacySettingsNotifier(settings);
        await _pumpTall(tester, notifier);

        // There are 3 radio groups × 3 options = 9 RadioListTiles total.
        // Last Seen is the first group (indices 0-2).
        final lastSeenRadios = tester
            .widgetList<RadioListTile<int>>(find.byType(RadioListTile<int>))
            .toList();

        expect(lastSeenRadios[0].groupValue, equals(1),
            reason: 'Last Seen group value should be 1 (My Contacts)');
      },
    );

    testWidgets(
      'displays Online Status radio selection matching repository value',
      (tester) async {
        const settings = PrivacySetting(
          lastSeenPrivacy: 0,
          onlineStatusPrivacy: 2, // Nobody
          profilePhotoPrivacy: 0,
          readReceiptsEnabled: true,
        );
        final notifier = _FakePrivacySettingsNotifier(settings);
        await _pumpTall(tester, notifier);

        final radios = tester
            .widgetList<RadioListTile<int>>(find.byType(RadioListTile<int>))
            .toList();

        // Online Status is the second group (indices 3-5).
        expect(radios[3].groupValue, equals(2),
            reason: 'Online Status group value should be 2 (Nobody)');
      },
    );

    testWidgets(
      'displays Profile Photo radio selection matching repository value',
      (tester) async {
        const settings = PrivacySetting(
          lastSeenPrivacy: 0,
          onlineStatusPrivacy: 0,
          profilePhotoPrivacy: 1, // My Contacts
          readReceiptsEnabled: true,
        );
        final notifier = _FakePrivacySettingsNotifier(settings);
        await _pumpTall(tester, notifier);

        final radios = tester
            .widgetList<RadioListTile<int>>(find.byType(RadioListTile<int>))
            .toList();

        // Profile Photo is the third group (indices 6-8).
        expect(radios[6].groupValue, equals(1),
            reason: 'Profile Photo group value should be 1 (My Contacts)');
      },
    );

    testWidgets(
      'displays Read Receipts toggle ON when readReceiptsEnabled=true',
      (tester) async {
        const settings = PrivacySetting(readReceiptsEnabled: true);
        final notifier = _FakePrivacySettingsNotifier(settings);
        await _pumpTall(tester, notifier);

        final switchWidget =
            tester.widget<SwitchListTile>(find.byType(SwitchListTile));
        expect(switchWidget.value, isTrue);
      },
    );

    testWidgets(
      'displays Read Receipts toggle OFF when readReceiptsEnabled=false',
      (tester) async {
        const settings = PrivacySetting(readReceiptsEnabled: false);
        final notifier = _FakePrivacySettingsNotifier(settings);
        await _pumpTall(tester, notifier);

        final switchWidget =
            tester.widget<SwitchListTile>(find.byType(SwitchListTile));
        expect(switchWidget.value, isFalse);
      },
    );

    testWidgets(
      'shows all three privacy level options for each radio group (9 total)',
      (tester) async {
        final notifier =
            _FakePrivacySettingsNotifier(const PrivacySetting());
        await _pumpTall(tester, notifier);

        expect(find.byType(RadioListTile<int>), findsNWidgets(9));
      },
    );
  });

  group('testPrivacySettingScreen_updateCallsRepository', () {
    /// Validates: Requirements 6.4

    testWidgets(
      'tapping a Last Seen option triggers updateSettings with only lastSeenPrivacy set',
      (tester) async {
        const initial = PrivacySetting(lastSeenPrivacy: 0);
        final notifier = _FakePrivacySettingsNotifier(initial);
        await _pumpTall(tester, notifier);

        // Tap "My Contacts" (value=1) in the Last Seen group (index 1).
        final radios = find.byType(RadioListTile<int>);
        await tester.tap(radios.at(1));
        await tester.pumpAndSettle();

        expect(notifier.capturedRequests, hasLength(1));
        final req = notifier.capturedRequests.first;
        expect(req.lastSeenPrivacy, equals(1));
        expect(req.onlineStatusPrivacy, isNull);
        expect(req.profilePhotoPrivacy, isNull);
        expect(req.readReceiptsEnabled, isNull);
      },
    );

    testWidgets(
      'tapping an Online Status option triggers updateSettings with only onlineStatusPrivacy set',
      (tester) async {
        const initial = PrivacySetting(onlineStatusPrivacy: 0);
        final notifier = _FakePrivacySettingsNotifier(initial);
        await _pumpTall(tester, notifier);

        // Online Status group is second (indices 3-5). Index 5 = Nobody (value=2).
        final radios = find.byType(RadioListTile<int>);
        await tester.tap(radios.at(5));
        await tester.pumpAndSettle();

        expect(notifier.capturedRequests, hasLength(1));
        final req = notifier.capturedRequests.first;
        expect(req.onlineStatusPrivacy, equals(2));
        expect(req.lastSeenPrivacy, isNull);
        expect(req.profilePhotoPrivacy, isNull);
        expect(req.readReceiptsEnabled, isNull);
      },
    );

    testWidgets(
      'tapping a Profile Photo option triggers updateSettings with only profilePhotoPrivacy set',
      (tester) async {
        const initial = PrivacySetting(profilePhotoPrivacy: 0);
        final notifier = _FakePrivacySettingsNotifier(initial);
        await _pumpTall(tester, notifier);

        // Profile Photo group is third (indices 6-8). Index 7 = My Contacts (value=1).
        final radios = find.byType(RadioListTile<int>);
        await tester.tap(radios.at(7));
        await tester.pumpAndSettle();

        expect(notifier.capturedRequests, hasLength(1));
        final req = notifier.capturedRequests.first;
        expect(req.profilePhotoPrivacy, equals(1));
        expect(req.lastSeenPrivacy, isNull);
        expect(req.onlineStatusPrivacy, isNull);
        expect(req.readReceiptsEnabled, isNull);
      },
    );

    testWidgets(
      'toggling Read Receipts triggers updateSettings with only readReceiptsEnabled set',
      (tester) async {
        const initial = PrivacySetting(readReceiptsEnabled: true);
        final notifier = _FakePrivacySettingsNotifier(initial);
        await _pumpTall(tester, notifier);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        expect(notifier.capturedRequests, hasLength(1));
        final req = notifier.capturedRequests.first;
        expect(req.readReceiptsEnabled, isFalse);
        expect(req.lastSeenPrivacy, isNull);
        expect(req.onlineStatusPrivacy, isNull);
        expect(req.profilePhotoPrivacy, isNull);
      },
    );

    testWidgets(
      'each field change sends only that field (partial update)',
      (tester) async {
        const initial = PrivacySetting(
          lastSeenPrivacy: 0,
          onlineStatusPrivacy: 0,
          profilePhotoPrivacy: 0,
          readReceiptsEnabled: true,
        );
        final notifier = _FakePrivacySettingsNotifier(initial);
        await _pumpTall(tester, notifier);

        // Change Last Seen to Nobody (index 2, value=2)
        final radios = find.byType(RadioListTile<int>);
        await tester.tap(radios.at(2));
        await tester.pumpAndSettle();

        final req = notifier.capturedRequests.last;
        expect(req.lastSeenPrivacy, equals(2));
        expect(req.onlineStatusPrivacy, isNull);
        expect(req.profilePhotoPrivacy, isNull);
        expect(req.readReceiptsEnabled, isNull);
      },
    );
  });
}
