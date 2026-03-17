import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/privacy/providers/privacy_settings_provider.dart';
import 'package:app/features/privacy/repositories/privacy_setting_repository.dart';
import 'package:app/models/privacy_setting.dart';

/// Privacy settings page — lets the user control who can see their
/// Last Seen, Online Status, Profile Photo, and Read Receipts.
class PrivacySettingsPage extends ConsumerWidget {
  const PrivacySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(privacySettingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F6F8);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          '隱私設定 (Privacy)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: textColor,
          ),
        ),
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: settingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            isDark: isDark,
            onRetry: () => ref.invalidate(privacySettingsProvider),
          ),
          data: (settings) => _PrivacySettingsBody(
            settings: settings,
            isDark: isDark,
          ),
        ),
      ),
    );
  }
}

// ─── Body ────────────────────────────────────────────────────────────────────

class _PrivacySettingsBody extends ConsumerWidget {
  const _PrivacySettingsBody({
    required this.settings,
    required this.isDark,
  });

  final PrivacySetting settings;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _buildSection(
          title: '最後上線時間 (Last Seen)',
          isDark: isDark,
          child: _PrivacyRadioGroup(
            key: const Key('lastSeen'),
            value: settings.lastSeenPrivacy,
            isDark: isDark,
            onChanged: (v) => _update(ref, context,
                UpdatePrivacySettingRequest(lastSeenPrivacy: v)),
          ),
        ),
        _buildSection(
          title: '在線狀態 (Online Status)',
          isDark: isDark,
          child: _PrivacyRadioGroup(
            key: const Key('onlineStatus'),
            value: settings.onlineStatusPrivacy,
            isDark: isDark,
            onChanged: (v) => _update(ref, context,
                UpdatePrivacySettingRequest(onlineStatusPrivacy: v)),
          ),
        ),
        _buildSection(
          title: '個人頭像 (Profile Photo)',
          isDark: isDark,
          child: _PrivacyRadioGroup(
            key: const Key('profilePhoto'),
            value: settings.profilePhotoPrivacy,
            isDark: isDark,
            onChanged: (v) => _update(ref, context,
                UpdatePrivacySettingRequest(profilePhotoPrivacy: v)),
          ),
        ),
        _buildSection(
          title: '已讀回條 (Read Receipts)',
          isDark: isDark,
          child: _ReadReceiptsToggle(
            key: const Key('readReceipts'),
            value: settings.readReceiptsEnabled,
            isDark: isDark,
            onChanged: (v) => _update(ref, context,
                UpdatePrivacySettingRequest(readReceiptsEnabled: v)),
          ),
        ),
      ],
    );
  }

  Future<void> _update(
    WidgetRef ref,
    BuildContext context,
    UpdatePrivacySettingRequest req,
  ) async {
    try {
      await ref.read(privacySettingsProvider.notifier).updateSettings(req);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更新失敗，請稍後再試')),
        );
      }
    }
  }

  Widget _buildSection({
    required String title,
    required bool isDark,
    required Widget child,
  }) {
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: isDark ? Colors.white38 : Colors.grey[500],
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ─── Radio group (Everyone / My Contacts / Nobody) ───────────────────────────

class _PrivacyRadioGroup extends StatelessWidget {
  const _PrivacyRadioGroup({
    super.key,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  final int value;
  final bool isDark;
  final ValueChanged<int> onChanged;

  static const _options = [
    (label: '所有人 (Everyone)', value: 0),
    (label: '我的聯絡人 (My Contacts)', value: 1),
    (label: '沒人 (Nobody)', value: 2),
  ];

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.07);

    return Column(
      children: List.generate(_options.length, (i) {
        final opt = _options[i];
        final isLast = i == _options.length - 1;
        return Column(
          children: [
            RadioListTile<int>(
              value: opt.value,
              groupValue: value,
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
              title: Text(
                opt.label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
              activeColor: const Color(0xFF007AFF),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            if (!isLast)
              Divider(height: 1, indent: 60, color: dividerColor),
          ],
        );
      }),
    );
  }
}

// ─── Read Receipts toggle ─────────────────────────────────────────────────────

class _ReadReceiptsToggle extends StatelessWidget {
  const _ReadReceiptsToggle({
    super.key,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white54 : Colors.grey[600];

    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(
        '顯示已讀回條',
        style: TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
      subtitle: Text(
        '關閉後，對方將看不到你的已讀狀態（群組訊息不受影響）',
        style: TextStyle(fontSize: 13, color: subtitleColor),
      ),
      activeColor: const Color(0xFF34C759),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.isDark, required this.onRetry});

  final bool isDark;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: isDark ? Colors.white38 : Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            '載入失敗',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white54 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('重試'),
          ),
        ],
      ),
    );
  }
}
