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

    // 使用系統的亮度來決定背景顏色，達到現代通訊軟體的質感
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F6F8);
    final appBarColor = isDark
        ? const Color(0xFF0D0D0D)
        : const Color(0xFFF4F6F8);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text(
          '媒體瀏覽設定',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        backgroundColor: appBarColor,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      body: asyncSetting.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ChatThemeTokens.accentColor),
        ),
        error: (err, stack) => Center(
          child: Text(
            '載入失敗: $err',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        data: (setting) => _MediaSettingsForm(
          roomId: roomId,
          initialSetting: setting,
          isDark: isDark,
        ),
      ),
    );
  }
}

class _MediaSettingsForm extends ConsumerStatefulWidget {
  final String roomId;
  final dynamic initialSetting;
  final bool isDark;

  const _MediaSettingsForm({
    required this.roomId,
    required this.initialSetting,
    required this.isDark,
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

  // 區塊標題與副標題
  Widget _buildSectionHeader(String title, String subtitle, IconData icon) {
    final primaryColor = widget.isDark ? Colors.white : Colors.black87;
    final secondaryColor = widget.isDark ? Colors.white54 : Colors.grey[600]!;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: ChatThemeTokens.accentColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: secondaryColor,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 精緻的 Radio 選項
  Widget _buildRadioOption({
    required String title,
    required String? subtitle,
    required int value,
    required int groupValue,
    required ValueChanged<int?> onChanged,
    bool showDivider = true,
  }) {
    final isSelected = value == groupValue;
    final primaryColor = widget.isDark ? Colors.white : Colors.black87;
    final secondaryColor = widget.isDark ? Colors.white54 : Colors.grey[500]!;
    final dividerColor = widget.isDark
        ? Colors.white12
        : Colors.black.withValues(alpha: 0.05);
    final highlightColor = widget.isDark
        ? ChatThemeTokens.accentColor.withValues(alpha: 0.1)
        : ChatThemeTokens.accentColor.withValues(alpha: 0.05);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(value),
            child: Container(
              color: isSelected ? highlightColor : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 16,
                            fontWeight: isSelected
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Radio<int>.adaptive(
                    value: value,
                    activeColor: ChatThemeTokens.accentColor,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    toggleable: false,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Divider(height: 1, color: dividerColor),
          ),
      ],
    );
  }

  // 統一的設定卡片容器
  Widget _buildSettingsCard({required List<Widget> children}) {
    final cardColor = widget.isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final shadowColor = widget.isDark
        ? Colors.transparent
        : Colors.black.withValues(alpha: 0.04);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(children: children),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // ── 儲存至手機相簿 ───────────────────────────────────────
              _buildSectionHeader(
                '儲存至手機相簿',
                '控制在此聊天室收到的照片和影片是否自動儲存到您的裝置相簿。',
                Icons.photo_library_outlined,
              ),
              _buildSettingsCard(
                children: [
                  RadioGroup<int>(
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _saveToCameraRoll = val);
                      }
                    },
                    child: Column(
                      children: [
                        _buildRadioOption(
                          title: '依全域設定（預設）',
                          subtitle: null,
                          value: 0,
                          groupValue: _saveToCameraRoll,
                          onChanged: (val) =>
                              setState(() => _saveToCameraRoll = val!),
                        ),
                        _buildRadioOption(
                          title: '永遠開啟',
                          subtitle: null,
                          value: 1,
                          groupValue: _saveToCameraRoll,
                          onChanged: (val) =>
                              setState(() => _saveToCameraRoll = val!),
                        ),
                        _buildRadioOption(
                          title: '永遠關閉',
                          subtitle: null,
                          value: 2,
                          groupValue: _saveToCameraRoll,
                          onChanged: (val) =>
                              setState(() => _saveToCameraRoll = val!),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── 自動下載 ──────────────────────────────────────────
              _buildSectionHeader(
                '自動下載',
                '選擇媒體檔案在何種網路環境下會自動下載至您的應用程式。',
                Icons.cloud_download_outlined,
              ),
              _buildSettingsCard(
                children: [
                  RadioGroup<int>(
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _autoDownload = val);
                      }
                    },
                    child: Column(
                      children: [
                        _buildRadioOption(
                          title: '依全域設定（預設）',
                          subtitle: null,
                          value: 0,
                          groupValue: _autoDownload,
                          onChanged: (val) => setState(() => _autoDownload = val!),
                        ),
                        _buildRadioOption(
                          title: '永遠自動下載',
                          subtitle: '包含行動網路與 Wi-Fi',
                          value: 1,
                          groupValue: _autoDownload,
                          onChanged: (val) => setState(() => _autoDownload = val!),
                        ),
                        _buildRadioOption(
                          title: '僅 Wi-Fi 時下載',
                          subtitle: '節省行動數據使用量',
                          value: 2,
                          groupValue: _autoDownload,
                          onChanged: (val) => setState(() => _autoDownload = val!),
                        ),
                        _buildRadioOption(
                          title: '永不自動下載',
                          subtitle: '需要手動點擊才下載',
                          value: 3,
                          groupValue: _autoDownload,
                          onChanged: (val) => setState(() => _autoDownload = val!),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── 媒體畫質 ──────────────────────────────────────────
              _buildSectionHeader(
                '媒體畫質',
                '設定傳送照片與影片的預設網路壓縮品質。',
                Icons.hd_outlined,
              ),
              _buildSettingsCard(
                children: [
                  RadioGroup<int>(
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _mediaQuality = val);
                      }
                    },
                    child: Column(
                      children: [
                        _buildRadioOption(
                          title: '依全域設定（預設）',
                          subtitle: null,
                          value: 0,
                          groupValue: _mediaQuality,
                          onChanged: (val) => setState(() => _mediaQuality = val!),
                        ),
                        _buildRadioOption(
                          title: '高畫質（HD）',
                          subtitle: '保留更多細節，檔案較大',
                          value: 1,
                          groupValue: _mediaQuality,
                          onChanged: (val) => setState(() => _mediaQuality = val!),
                        ),
                        _buildRadioOption(
                          title: '節省數據（壓縮）',
                          subtitle: '較低的畫質以節省網路流量',
                          value: 2,
                          groupValue: _mediaQuality,
                          onChanged: (val) => setState(() => _mediaQuality = val!),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── 底部按鈕 ─────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.isDark ? 0.2 : 0.05,
                ),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52, // 增加按鈕高度
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ChatThemeTokens.accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12), // 圓角與卡片一致
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveSettings,
                  child: _isSaving
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '儲存設定',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
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
