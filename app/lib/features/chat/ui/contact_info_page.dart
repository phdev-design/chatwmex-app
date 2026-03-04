import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app/core/network/network_service.dart';

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
    // 取得當前主題色彩，為了符合深色模式的 WhatsApp 風格，可以寫死或沿用 Theme
    final Color bgColor = const Color(0xFF0B141A);
    final Color surfaceColor = const Color(0xFF111B21);
    final Color accentColor = const Color(0xFF53BDEB);
    final Color dangerColor = const Color(0xFFF15C6D);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: surfaceColor,
            expandedHeight: 320.0,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
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
                        Hero(
                          tag: 'avatar_$roomId',
                          child: _buildAvatar(),
                        ),
                        const SizedBox(height: 12),
                        // 如果需要顯示電話號碼或 ID，可以放這裡
                        if (!isRoom)
                          Text(
                            '+886 912 345 678', // 這裡先用假資料
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade400,
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
                  title: const Text(
                    '媒體、連結與文件',
                    style: TextStyle(color: Colors.white),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '0',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, color: Colors.grey.shade400),
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
                      leading: Icon(Icons.notifications_off, color: Colors.grey.shade400),
                      title: const Text('將通知靜音', style: TextStyle(color: Colors.white)),
                      trailing: Switch(
                        value: false,
                        onChanged: (val) {},
                        activeColor: accentColor,
                      ),
                    ),
                    const Divider(height: 1, color: Colors.black26),
                    ListTile(
                      leading: Icon(Icons.music_note, color: Colors.grey.shade400),
                      title: const Text('自訂通知', style: TextStyle(color: Colors.white)),
                      onTap: () {},
                    ),
                    const Divider(height: 1, color: Colors.black26),
                    ListTile(
                      leading: Icon(Icons.image, color: Colors.grey.shade400),
                      title: const Text('媒體瀏覽設定', style: TextStyle(color: Colors.white)),
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
                      leading: Icon(Icons.lock, color: Colors.grey.shade400),
                      title: const Text('加密', style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '訊息和通話都受到端對端加密。點按以確認。',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      ),
                      onTap: () {},
                    ),
                    const Divider(height: 1, color: Colors.black26),
                    ListTile(
                      leading: Icon(Icons.av_timer, color: Colors.grey.shade400),
                      title: const Text('自動刪除的訊息', style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '關閉',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
                      title: Text('封鎖 $title', style: TextStyle(color: dangerColor)),
                      onTap: () {},
                    ),
                    const Divider(height: 1, color: Colors.black26),
                    ListTile(
                      leading: Icon(Icons.thumb_down_alt_outlined, color: dangerColor),
                      title: Text('檢舉 $title', style: TextStyle(color: dangerColor)),
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
    final defaultAvatar = CircleAvatar(
      radius: 60,
      backgroundColor: const Color(0xFF2A3942),
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '?',
        style: const TextStyle(fontSize: 48, color: Colors.white),
      ),
    );
    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return defaultAvatar;
    }
    return ClipOval(
      child: Image.network(
        NetworkService.resolveUrl(avatarUrl!),
        width: 120,
        height: 120,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return defaultAvatar;
        },
      ),
    );
  }
}
