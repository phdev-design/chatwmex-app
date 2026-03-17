import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/privacy/repositories/privacy_setting_repository.dart';
import 'package:app/models/privacy_setting.dart';

/// AsyncNotifier that loads and updates the current user's privacy settings.
class PrivacySettingsNotifier extends AsyncNotifier<PrivacySetting> {
  @override
  Future<PrivacySetting> build() async {
    final repo = ref.read(privacySettingRepositoryProvider);
    return repo.getPrivacySetting();
  }

  /// Update a single field and refresh state with the server response.
  Future<void> updateSettings(UpdatePrivacySettingRequest req) async {
    final repo = ref.read(privacySettingRepositoryProvider);
    state = await AsyncValue.guard(() => repo.updatePrivacySetting(req));
  }
}

final privacySettingsProvider =
    AsyncNotifierProvider<PrivacySettingsNotifier, PrivacySetting>(
  PrivacySettingsNotifier.new,
);
