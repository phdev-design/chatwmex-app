import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/chat/providers/room_label_provider.dart';
import 'package:app/features/chat/ui/room_label_detail_page.dart';

class RoomLabelsSettingsPage extends ConsumerStatefulWidget {
  const RoomLabelsSettingsPage({super.key});

  @override
  ConsumerState<RoomLabelsSettingsPage> createState() =>
      _RoomLabelsSettingsPageState();
}

class _RoomLabelsSettingsPageState
    extends ConsumerState<RoomLabelsSettingsPage> {
  // 本地狀態：模擬預設分類的開關 (未來可與你的設定 Provider 綁定)
  bool _isUnreadEnabled = false; // 預設未加入，展示「加入」按鈕
  bool _isFavoritesEnabled = true;

  @override
  Widget build(BuildContext context) {
    final labelsAsync = ref.watch(roomLabelProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 完美對標 iOS / 參考圖片的背景與卡片配色
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          '聊天室分類',
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
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // ─── 推薦分類 (RECOMMENDED FOLDERS) ───
            _buildSectionTitle('推薦分類', isDark),
            _buildSystemLabelsCard(cardColor, textColor, isDark),

            const SizedBox(height: 32),

            // ─── 自定義分類 (FOLDERS) ───
            _buildSectionTitle('分類名單', isDark),
            _buildCustomLabelsCard(labelsAsync, cardColor, textColor, isDark),
            
            // 底部說明文字
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 12, bottom: 32),
              child: Text(
                '建立自定義分類以分類您的聊天室。長按聊天室即可將其加入特定分類。',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── UI 區塊構造 ─────────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white54 : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildSystemLabelsCard(Color cardColor, Color textColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _buildSystemTile(
            icon: Icons.mark_chat_unread_rounded,
            iconBgColor: const Color(0xFF007AFF), // iOS 藍色
            title: '未讀',
            subtitle: '包含所有未讀訊息的對話',
            value: _isUnreadEnabled,
            onChanged: (val) => setState(() => _isUnreadEnabled = val),
            isDark: isDark,
            showDivider: true,
            textColor: textColor,
          ),
          _buildSystemTile(
            icon: Icons.star_rounded,
            iconBgColor: const Color(0xFFFF9500), // iOS 橘黃色
            title: '最愛群組',
            subtitle: '您標記為最愛的聯絡人與群組',
            value: _isFavoritesEnabled,
            onChanged: (val) => setState(() => _isFavoritesEnabled = val),
            isDark: isDark,
            showDivider: false,
            textColor: textColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSystemTile({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
    required bool showDivider,
    required Color textColor,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          title: Text(
            title,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w500, color: textColor),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.grey[600]),
            ),
          ),
          trailing: GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: value 
                    ? (isDark ? Colors.white12 : Colors.grey.shade200) 
                    : const Color(0xFF007AFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                value ? '移除' : '加入',
                style: TextStyle(
                  color: value 
                      ? (isDark ? Colors.white70 : Colors.grey.shade700) 
                      : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 68,
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
          ),
      ],
    );
  }

  Widget _buildCustomLabelsCard(AsyncValue labelsAsync, Color cardColor,
      Color textColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            // ─── 新增按鈕 (Create New Folder) ───
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.add_circle_rounded, color: Color(0xFF007AFF), size: 28),
              title: const Text(
                '建立新分類',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF007AFF),
                ),
              ),
              onTap: () => _showCreateLabelDialog(context, ref),
            ),
            
            // ─── 自定義清單 ───
            labelsAsync.when(
              data: (labels) {
                if (labels.isEmpty) return const SizedBox.shrink();
                
                return Column(
                  children: [
                    Divider(
                      height: 1,
                      indent: 60,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: labels.length,
                      onReorder: (oldIndex, newIndex) {
                        if (oldIndex < newIndex) newIndex -= 1;
                        final item = labels.removeAt(oldIndex);
                        labels.insert(newIndex, item);

                        final orderedIds = labels.map((e) => e.id).toList();
                        ref.read(roomLabelProvider.notifier).reorderLabels(orderedIds);
                      },
                      itemBuilder: (context, index) {
                        final label = labels[index];
                        final isLast = index == labels.length - 1;

                        return Dismissible(
                          key: ValueKey(label.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: const Color(0xFFFF3B30),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: Colors.white),
                          ),
                          confirmDismiss: (direction) =>
                              _confirmDelete(context, label.name),
                          onDismissed: (direction) {
                            ref.read(roomLabelProvider.notifier).deleteLabel(label.id);
                          },
                          child: Container(
                            color: cardColor, // 背景必須給定，確保拖曳無殘影
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: ReorderableDragStartListener(
                                    index: index,
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                                      size: 28,
                                    ),
                                  ),
                                  title: Text(
                                    label.name,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                        color: textColor),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '${label.roomIds.length} 個對話',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? Colors.white54 : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                  trailing: Icon(
                                    Icons.chevron_right_rounded,
                                    color: isDark ? Colors.white24 : Colors.grey.shade400,
                                  ),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            RoomLabelDetailPage(label: label),
                                      ),
                                    );
                                  },
                                ),
                                if (!isLast)
                                  Divider(
                                    height: 1,
                                    indent: 60, // 對齊文字
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.black.withValues(alpha: 0.05),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '載入失敗: $err',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 彈出視窗 (支援 Light/Dark 模式) ──────────────────────────────────────────

  Future<void> _showCreateLabelDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final primaryBlue = const Color(0xFF007AFF);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: dialogBgColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('新增分類', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: '輸入分類名稱...',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
              filled: true,
              fillColor: isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primaryBlue, width: 1.5),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  ref.read(roomLabelProvider.notifier).createLabel(text);
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('新增', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: dialogBgColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('刪除分類', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        content: Text(
          '確定要刪除「$name」嗎？\n(這不會刪除群組本身，只會移除分類標籤)',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey[600])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定刪除', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}