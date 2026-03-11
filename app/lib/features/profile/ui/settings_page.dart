import 'package:flutter/material.dart';
import 'package:app/features/chat/ui/conversations_settings_page.dart';
import 'package:app/features/chat/ui/room_labels_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
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
                  showDivider: false, // 最後一個選項不顯示底線
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RoomLabelsSettingsPage(),
                    ),
                  ),
                ),
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