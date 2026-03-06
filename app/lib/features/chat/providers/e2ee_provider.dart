import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class E2EEStateNotifier extends StateNotifier<AsyncValue<bool>> {
  final String contactId;

  E2EEStateNotifier(this.contactId) : super(const AsyncValue.loading()) {
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('e2ee_enabled_$contactId') ?? true; // 預設為 true
      if (mounted) {
        state = AsyncValue.data(isEnabled);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> toggle(bool value) async {
    state = AsyncValue.data(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('e2ee_enabled_$contactId', value);
  }
}

final e2eeEnabledProvider = StateNotifierProvider.family<E2EEStateNotifier, AsyncValue<bool>, String>((ref, contactId) {
  return E2EEStateNotifier(contactId);
});
