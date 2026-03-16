import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/settings/providers/linked_devices_provider.dart';
import 'package:app/features/settings/qr_scanner_page.dart';

/// 已連結裝置的資料模型（供 UI 使用）
class LinkedDeviceInfo {
  final String id;
  final String deviceName;
  final String platform;
  final DateTime lastActiveAt;

  const LinkedDeviceInfo({
    required this.id,
    required this.deviceName,
    required this.platform,
    required this.lastActiveAt,
  });
}

/// 已連結裝置數量上限
const int maxLinkedDevices = 4;

class LinkedDevicesPage extends ConsumerStatefulWidget {
  const LinkedDevicesPage({super.key});

  @override
  ConsumerState<LinkedDevicesPage> createState() => _LinkedDevicesPageState();
}

class _LinkedDevicesPageState extends ConsumerState<LinkedDevicesPage> {
  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(linkedDevicesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF4F6F8);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          '已連結裝置',
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
        child: devicesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 48,
                    color: isDark ? Colors.white38 : Colors.grey.shade400),
                const SizedBox(height: 12),
                Text('載入失敗',
                    style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white54 : Colors.grey.shade600)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.read(linkedDevicesProvider.notifier).loadDevices(),
                  child: const Text('重試'),
                ),
              ],
            ),
          ),
          data: (devices) {
            final isAtMaxDevices = devices.length >= maxLinkedDevices;
            return RefreshIndicator(
              onRefresh: () => ref.read(linkedDevicesProvider.notifier).loadDevices(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  _buildLinkNewDeviceSection(isDark, isAtMaxDevices: isAtMaxDevices),
                  const SizedBox(height: 24),
                  if (devices.isEmpty)
                    _buildEmptyState(isDark)
                  else
                    _buildDeviceListSection(isDark, devices: devices),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 「連結新裝置」按鈕區塊
  Widget _buildLinkNewDeviceSection(bool isDark, {required bool isAtMaxDevices}) {
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    const primaryColor = Color(0xFF5856D6);

    return Container(
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
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isAtMaxDevices ? null : _onLinkNewDevice,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.qr_code_scanner_rounded,
                      color: isAtMaxDevices
                          ? (isDark ? Colors.white24 : Colors.grey.shade400)
                          : primaryColor,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '連結新裝置',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isAtMaxDevices
                              ? (isDark ? Colors.white38 : Colors.grey.shade400)
                              : primaryColor,
                        ),
                      ),
                    ),
                    if (isAtMaxDevices)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.orange.withValues(alpha: 0.2)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '已達上限',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isAtMaxDevices)
            Padding(
              padding: const EdgeInsets.only(left: 58, right: 16, bottom: 12),
              child: Text(
                '已連結裝置數量已達上限 $maxLinkedDevices 台，請先取消連結其他裝置。',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 空狀態畫面
  Widget _buildEmptyState(bool isDark) {
    const primaryColor = Color(0xFF5856D6);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.devices_rounded,
            size: 72,
            color: isDark ? Colors.white24 : Colors.grey.shade300,
          ),
          const SizedBox(height: 20),
          Text(
            '尚無已連結裝置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '使用手機掃描網頁版 QR Code\n即可在網頁端同步聊天訊息',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _onLinkNewDevice,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: const Text(
                '連結新裝置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 裝置清單區塊
  Widget _buildDeviceListSection(bool isDark, {required List<LinkedDeviceInfo> devices}) {
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 8),
          child: Text(
            '已連結裝置'.toUpperCase(),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              children: List.generate(devices.length, (index) {
                final device = devices[index];
                final isLast = index == devices.length - 1;
                return _buildDismissibleDeviceTile(device, isDark, showDivider: !isLast);
              }),
            ),
          ),
        ),
      ],
    );
  }

  /// 單一裝置項目
  Widget _buildDeviceTile(
    LinkedDeviceInfo device,
    bool isDark, {
    bool showDivider = true,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white54 : Colors.grey[600];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _platformIcon(device.platform),
                  size: 22,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_platformLabel(device.platform)} · ${_formatLastActive(device.lastActiveAt)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 70,
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.07),
          ),
      ],
    );
  }

  /// 包裝 Dismissible 與 GestureDetector 的裝置項目
  Widget _buildDismissibleDeviceTile(
    LinkedDeviceInfo device,
    bool isDark, {
    bool showDivider = true,
  }) {
    return Dismissible(
      key: Key('device_${device.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _showUnlinkConfirmDialog(),
      onDismissed: (_) => _performUnlink(device.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.link_off_rounded, color: Colors.white),
      ),
      child: GestureDetector(
        onLongPress: () => _showUnlinkBottomSheet(device),
        child: _buildDeviceTile(device, isDark, showDivider: showDivider),
      ),
    );
  }

  /// 長按顯示取消連結底部選單
  void _showUnlinkBottomSheet(LinkedDeviceInfo device) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              device.deviceName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.link_off_rounded, color: Colors.red),
              title: const Text(
                '取消連結',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();
                final confirmed = await _showUnlinkConfirmDialog();
                if (confirmed == true) {
                  _performUnlink(device.id);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 確認取消連結對話框，回傳 true 表示確認
  Future<bool?> _showUnlinkConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消連結'),
        content: const Text('確定要取消連結此裝置嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('確認', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 執行取消連結並顯示成功 SnackBar
  Future<void> _performUnlink(String deviceId) async {
    try {
      await ref.read(linkedDevicesProvider.notifier).unlinkDevice(deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('裝置已取消連結')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消連結失敗：$e')),
        );
      }
    }
  }

  // ─── 輔助方法 ─────────────────────────────────────────────────────────────

  void _onLinkNewDevice() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const QrScannerPage(),
      ),
    );
  }

  IconData _platformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'web':
        return Icons.language_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  String _platformLabel(String platform) {
    switch (platform.toLowerCase()) {
      case 'web':
        return 'Web';
      default:
        return platform;
    }
  }

  String _formatLastActive(DateTime lastActive) {
    final now = DateTime.now();
    final diff = now.difference(lastActive);

    if (diff.inMinutes < 1) return '剛剛活躍';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前活躍';
    if (diff.inHours < 24) return '${diff.inHours} 小時前活躍';
    if (diff.inDays < 7) return '${diff.inDays} 天前活躍';
    return '${lastActive.month}/${lastActive.day} 活躍';
  }
}
