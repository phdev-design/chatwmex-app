import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/providers/chat_setting_provider.dart';

// ChatThemeTokens matched from contact_info_page
class ChatThemeTokens {
  static const Color primaryTextColor = Colors.white;
  static const Color secondaryTextColor = Color(0xFFA0AAB0);
  static const Color accentColor = Color(0xFF00A884);
  static const Color surfaceColor = Color(0xFF111B21);
}

class MediaVisibilitySettingsPage extends ConsumerWidget {
  final String roomId;

  const MediaVisibilitySettingsPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSetting = ref.watch(chatSettingProvider(roomId));

    return Scaffold(
      backgroundColor: ChatThemeTokens.surfaceColor,
      appBar: AppBar(
        title: const Text('媒體瀏覽設定'),
        backgroundColor: ChatThemeTokens.surfaceColor,
        foregroundColor: ChatThemeTokens.primaryTextColor,
        elevation: 0,
      ),
      body: asyncSetting.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ChatThemeTokens.accentColor),
        ),
        error: (err, stack) => Center(
          child: Text('載入失敗: $err', style: const TextStyle(color: Colors.red)),
        ),
        data: (setting) =>
            _MediaSettingsForm(roomId: roomId, initialSetting: setting),
      ),
    );
  }
}

class _MediaSettingsForm extends ConsumerStatefulWidget {
  final String roomId;
  final dynamic initialSetting;

  const _MediaSettingsForm({
    required this.roomId,
    required this.initialSetting,
  });

  @override
  ConsumerState<_MediaSettingsForm> createState() => _MediaSettingsFormState();
}

class _MediaSettingsFormState extends ConsumerState<_MediaSettingsForm> {
  late int _saveToCameraRoll;
  late int _autoDownload;
  late int _mediaQuality;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _saveToCameraRoll = widget.initialSetting.saveToCameraRoll ?? 0;
    _autoDownload = widget.initialSetting.autoDownload ?? 0;
    _mediaQuality = widget.initialSetting.mediaQuality ?? 0;
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(chatSettingServiceProvider)
          .updateMediaSettings(
            widget.roomId,
            _saveToCameraRoll,
            _autoDownload,
            _mediaQuality,
          );
      ref.invalidate(chatSettingProvider(widget.roomId));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('儲存失敗：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 24, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: ChatThemeTokens.secondaryTextColor,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildRadioOption({
    required String title,
    required int value,
    required int groupValue,
    required ValueChanged<int?> onChanged,
  }) {
    return RadioListTile<int>(
      title: Text(
        title,
        style: const TextStyle(
          color: ChatThemeTokens.primaryTextColor,
          fontSize: 16,
        ),
      ),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      activeColor: ChatThemeTokens.accentColor,
      controlAffinity: ListTileControlAffinity.trailing,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              _buildSectionTitle('儲存至手機相簿'),
              _buildRadioOption(
                title: '依全域設定（預設）',
                value: 0,
                groupValue: _saveToCameraRoll,
                onChanged: (val) => setState(() => _saveToCameraRoll = val!),
              ),
              _buildRadioOption(
                title: '永遠開啟',
                value: 1,
                groupValue: _saveToCameraRoll,
                onChanged: (val) => setState(() => _saveToCameraRoll = val!),
              ),
              _buildRadioOption(
                title: '永遠關閉',
                value: 2,
                groupValue: _saveToCameraRoll,
                onChanged: (val) => setState(() => _saveToCameraRoll = val!),
              ),
              const Divider(color: Colors.white10),

              _buildSectionTitle('自動下載'),
              _buildRadioOption(
                title: '依全域設定（預設）',
                value: 0,
                groupValue: _autoDownload,
                onChanged: (val) => setState(() => _autoDownload = val!),
              ),
              _buildRadioOption(
                title: '永遠自動下載',
                value: 1,
                groupValue: _autoDownload,
                onChanged: (val) => setState(() => _autoDownload = val!),
              ),
              _buildRadioOption(
                title: '僅 Wi-Fi 時下載',
                value: 2,
                groupValue: _autoDownload,
                onChanged: (val) => setState(() => _autoDownload = val!),
              ),
              _buildRadioOption(
                title: '永不自動下載',
                value: 3,
                groupValue: _autoDownload,
                onChanged: (val) => setState(() => _autoDownload = val!),
              ),
              const Divider(color: Colors.white10),

              _buildSectionTitle('媒體畫質'),
              _buildRadioOption(
                title: '依全域設定（預設）',
                value: 0,
                groupValue: _mediaQuality,
                onChanged: (val) => setState(() => _mediaQuality = val!),
              ),
              _buildRadioOption(
                title: '高畫質（HD）',
                value: 1,
                groupValue: _mediaQuality,
                onChanged: (val) => setState(() => _mediaQuality = val!),
              ),
              _buildRadioOption(
                title: '節省數據（壓縮）',
                value: 2,
                groupValue: _mediaQuality,
                onChanged: (val) => setState(() => _mediaQuality = val!),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChatThemeTokens.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isSaving ? null : _saveSettings,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '儲存',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
