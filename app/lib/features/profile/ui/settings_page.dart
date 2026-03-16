import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/ui/conversations_settings_page.dart';
import 'package:app/features/chat/ui/room_labels_settings_page.dart';
import 'package:app/features/settings/linked_devices_page.dart';
import 'package:app/features/settings/providers/linked_devices_provider.dart';
import 'package:app/core/backup/backup_manager.dart';
import 'package:app/features/settings/providers/crypto_health_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backupState = ref.watch(backupManagerProvider);
    
    // 與其他頁面保持一致的背景色配置
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F6F8);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          '設定 (Settings)',
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
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // E2EE 金鑰健康狀態 Banner
            Consumer(
              builder: (context, ref, child) {
                final cryptoHealthAsync = ref.watch(cryptoHealthProvider);
                
                return cryptoHealthAsync.when(
                  data: (health) {
                    // 有溢出警告 - 顯示橙色警告 Banner
                    if (health.hasRecentOverflow) {
                      return _buildWarningBanner(
                        context: context,
                        isDark: isDark,
                        color: Colors.orange,
                        icon: Icons.warning_rounded,
                        title: '金鑰淘汰警告',
                        message: '部分舊訊息的解密金鑰已被自動淘汰，這些訊息可能已無法解密。建議立即備份目前的加密金鑰。',
                        buttonText: '立即備份',
                        onPressed: () {
                          // TODO: 導向金鑰備份頁面
                          // Navigator.of(context).push(
                          //   MaterialPageRoute(
                          //     builder: (_) => const KeyBackupPage(),
                          //   ),
                          // );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('金鑰備份功能開發中')),
                          );
                        },
                      );
                    }
                    
                    // 接近上限 - 顯示藍色提示 Banner
                    if (health.isNearLimit) {
                      return _buildWarningBanner(
                        context: context,
                        isDark: isDark,
                        color: Colors.blue,
                        icon: Icons.info_rounded,
                        title: '金鑰使用提示',
                        message: '加密金鑰歷史紀錄已使用 ${health.historyKeyCount}/50，建議定期備份金鑰。',
                        buttonText: '了解更多',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('定期備份金鑰可確保訊息安全')),
                          );
                        },
                      );
                    }
                    
                    // 正常狀態 - 不顯示
                    return const SizedBox.shrink();
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
            
            _buildSectionGroup(
              title: '一般設定',
              isDark: isDark,
              items: [
                _buildSettingsTile(
                  icon: Icons.chat_bubble_rounded,
                  iconBgColor: const Color(0xFF34C759), // 綠色 Icon 底色
                  title: '對話 (Conversations)',
                  isDark: isDark,
                  showDivider: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ConversationsSettingsPage(),
                    ),
                  ),
                ),
                _buildSettingsTile(
                  icon: Icons.label_rounded,
                  iconBgColor: const Color(0xFF007AFF), // 藍色 Icon 底色
                  title: '分類名單 (Room Labels)',
                  isDark: isDark,
                  showDivider: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RoomLabelsSettingsPage(),
                    ),
                  ),
                ),
                _buildLinkedDevicesTile(context, ref, isDark),
              ],
            ),
            
            // 未來如果需要新增區塊，可以直接複製 _buildSectionGroup 往下加：
            // _buildSectionGroup(
            //   title: '關於',
            //   isDark: isDark,
            //   items: [ ... ],
            // ),
          ],
        ),
      ),
    );
  }

  /// 建立大區塊（包含小標題與白/黑底卡片）
  Widget _buildSectionGroup({
    required String title,
    required bool isDark,
    required List<Widget> items,
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
          child: Column(
            children: items,
          ),
        ),
        const SizedBox(height: 24), // 區塊間距
      ],
    );
  }

  /// 建立警告或提示 Banner
  Widget _buildWarningBanner({
    required BuildContext context,
    required bool isDark,
    required Color color,
    required IconData icon,
    required String title,
    required String message,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.4 : 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 建立「已連結裝置」設定項目，含數量徽章
  Widget _buildLinkedDevicesTile(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    // 使用 linkedDeviceCountProvider 取得已連結裝置數量
    final int deviceCount = ref.watch(linkedDeviceCountProvider);

    final textColor = isDark ? Colors.white : Colors.black87;
    final chevronColor = isDark ? Colors.white24 : Colors.black26;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LinkedDevicesPage(),
                ),
              );
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5856D6), // 紫色 Icon 底色
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.devices, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '已連結裝置 (Linked Devices)',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (deviceCount > 0) _buildCountBadge(deviceCount),
                  if (deviceCount > 0) const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: chevronColor),
                ],
              ),
            ),
          ),
        ),
        // 最後一個選項不顯示底線
      ],
    );
  }

  /// 建立數量徽章
  Widget _buildCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF5856D6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 建立設定選項（帶有圓角 Icon 背景、文字及向右箭頭）
  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required bool isDark,
    required VoidCallback onTap,
    bool showDivider = true,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final chevronColor = isDark ? Colors.white24 : Colors.black26;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: chevronColor),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 60, // 對齊文字的起點 (16邊距 + 30圖示 + 14間距)
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.07),
          ),
      ],
    );
  }
}