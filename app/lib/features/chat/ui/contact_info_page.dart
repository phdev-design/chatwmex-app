import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app/features/chat/ui/theme/chat_theme_tokens.dart';
import 'package:app/features/chat/ui/widgets/chat_avatar.dart';

class ContactInfoPage extends StatelessWidget {
  final String roomId;
  final String title;
  final bool isRoom;
  final String? avatarUrl;

  const ContactInfoPage({
    super.key,
    required this.roomId,
    required this.title,
    this.isRoom = false,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final tokens = resolveChatSurfaceTokens(
      colorScheme: colorScheme,
      brightness: brightness,
    );
    final Color bgColor = isDark
        ? const Color(0xFF0B141A)
        : colorScheme.surface;
    final Color surfaceColor = isDark
        ? const Color(0xFF111B21)
        : colorScheme.surfaceContainerHighest;
    final Color accentColor = tokens.accent;
    final Color dangerColor = colorScheme.error;
    final Color primaryTextColor = colorScheme.onSurface;
    final Color secondaryTextColor = colorScheme.onSurfaceVariant;
    final Color dividerColor = colorScheme.outlineVariant.withValues(
      alpha: 0.35,
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: surfaceColor,
            expandedHeight: 320.0,
            pinned: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: primaryTextColor),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.more_vert, color: primaryTextColor),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                title,
                style: TextStyle(
                  color: primaryTextColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                ),
              ),
              background: Container(
                color: surfaceColor,
                // 使用 Center + SingleChildScrollView 避免往上捲動壓縮高度時發生 RenderFlex Overflow
                child: Center(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        Hero(tag: 'avatar_$roomId', child: _buildAvatar()),
                        const SizedBox(height: 12),
                        // 如果需要顯示電話號碼或 ID，可以放這裡
                        if (!isRoom)
                          Text(
                            '+886 912 345 678', // 這裡先用假資料
                            style: TextStyle(
                              fontSize: 16,
                              color: secondaryTextColor,
                            ),
                          ),
                        const SizedBox(height: 40), // 預留空間給底部的 title，避免文字重疊
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 12),

              // === 媒體、連結與文件 ===
              Container(
                color: surfaceColor,
                child: ListTile(
                  title: Text(
                    '媒體、連結與文件',
                    style: TextStyle(color: primaryTextColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('0', style: TextStyle(color: secondaryTextColor)),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: secondaryTextColor),
                    ],
                  ),
                  onTap: () {},
                ),
              ),
              const SizedBox(height: 12),

              // === 通知設定區塊 ===
              Container(
                color: surfaceColor,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.notifications_off,
                        color: secondaryTextColor,
                      ),
                      title: Text(
                        '將通知靜音',
                        style: TextStyle(color: primaryTextColor),
                      ),
                      trailing: Switch(
                        value: false,
                        onChanged: (val) {},
                        activeThumbColor: accentColor,
                      ),
                    ),
                    Divider(height: 1, color: dividerColor),
                    ListTile(
                      leading: Icon(
                        Icons.music_note,
                        color: secondaryTextColor,
                      ),
                      title: Text(
                        '自訂通知',
                        style: TextStyle(color: primaryTextColor),
                      ),
                      onTap: () {},
                    ),
                    Divider(height: 1, color: dividerColor),
                    ListTile(
                      leading: Icon(Icons.image, color: secondaryTextColor),
                      title: Text(
                        '媒體瀏覽設定',
                        style: TextStyle(color: primaryTextColor),
                      ),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // === 隱私設定區塊 ===
              Container(
                color: surfaceColor,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.lock, color: secondaryTextColor),
                      title: Text(
                        '加密',
                        style: TextStyle(color: primaryTextColor),
                      ),
                      subtitle: Text(
                        '訊息和通話都受到端對端加密。點按以確認。',
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () {},
                    ),
                    Divider(height: 1, color: dividerColor),
                    ListTile(
                      leading: Icon(Icons.av_timer, color: secondaryTextColor),
                      title: Text(
                        '自動刪除的訊息',
                        style: TextStyle(color: primaryTextColor),
                      ),
                      subtitle: Text(
                        '關閉',
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // === 封鎖與檢舉區塊 ===
              Container(
                color: surfaceColor,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.block, color: dangerColor),
                      title: Text(
                        '封鎖 $title',
                        style: TextStyle(color: dangerColor),
                      ),
                      onTap: () {},
                    ),
                    Divider(height: 1, color: dividerColor),
                    ListTile(
                      leading: Icon(
                        Icons.thumb_down_alt_outlined,
                        color: dangerColor,
                      ),
                      title: Text(
                        '檢舉 $title',
                        style: TextStyle(color: dangerColor),
                      ),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return ChatAvatar(
      avatarUrl: avatarUrl,
      radius: 60,
      fallbackText: title.isNotEmpty ? title[0].toUpperCase() : '?',
      logTag: 'contact_info',
    );
  }
}
