import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/network/network_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/settings/linked_devices_page.dart';

/// 已連結裝置清單狀態管理
class LinkedDevicesNotifier extends AsyncNotifier<List<LinkedDeviceInfo>> {
  @override
  Future<List<LinkedDeviceInfo>> build() async {
    return _fetchDevices();
  }

  /// 從後端取得已連結裝置清單
  Future<List<LinkedDeviceInfo>> _fetchDevices() async {
    final network = ref.read(networkServiceProvider);
    final response = await network.client.get('/devices/linked');
    if (response.statusCode == 200) {
      final data = response.data;
      if (data['data'] != null) {
        final List<dynamic> list = data['data'];
        return list.map((e) => _parseDevice(e)).toList();
      }
    }
    return [];
  }

  /// 重新載入裝置清單
  Future<void> loadDevices() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchDevices());
  }

  /// 取消連結指定裝置
  Future<void> unlinkDevice(String deviceId) async {
    final network = ref.read(networkServiceProvider);
    final response = await network.client.delete('/devices/linked/$deviceId');
    if (response.statusCode == 200) {
      // 🔑 取消連結後，為剩餘裝置重新分發 Session Key
      await _redistributeSessionKeys(network);
      // 成功後重新載入清單
      ref.invalidateSelf();
    } else {
      throw Exception('取消連結失敗: ${response.data}');
    }
  }

  /// 🔑 為所有剩餘已連結裝置產生並分發新的 Session Key
  Future<void> _redistributeSessionKeys(NetworkService network) async {
    try {
      final crypto = ref.read(cryptoServiceProvider);
      // 重新取得剩餘裝置清單
      final remainingDevices = await _fetchDevices();
      if (remainingDevices.isEmpty) return;

      final sessionKey = await crypto.generateSessionKey();

      // 取得每個裝置的公鑰並分發加密的 Session Key
      final devicesResponse = await network.client.get('/devices/linked');
      if (devicesResponse.statusCode == 200 && devicesResponse.data['data'] != null) {
        final List<dynamic> list = devicesResponse.data['data'];
        for (final deviceJson in list) {
          final deviceId = deviceJson['id'] as String?;
          final publicKey = deviceJson['public_key'] as String?;
          if (deviceId != null && publicKey != null && publicKey.isNotEmpty) {
            final encryptedKey = await crypto.encryptSessionKeyForDevice(
              sessionKey,
              publicKey,
            );
            await network.client.post(
              '/devices/session-key',
              data: {
                'device_id': deviceId,
                'encrypted_session_key': encryptedKey,
              },
            );
          }
        }
      }
    } catch (e) {
      // 金鑰重新分發失敗不應阻擋取消連結流程
      // ignore: avoid_print
      print('⚠️ Session Key 重新分發失敗: $e');
    }
  }

  /// 刷新（供 RefreshIndicator 使用）
  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  /// 解析後端回傳的裝置 JSON
  static LinkedDeviceInfo _parseDevice(Map<String, dynamic> json) {
    return LinkedDeviceInfo(
      id: json['id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? 'Unknown Device',
      platform: json['platform'] as String? ?? 'web',
      lastActiveAt: json['last_active_at'] != null
          ? DateTime.parse(json['last_active_at'] as String)
          : DateTime.now(),
    );
  }
}

/// 已連結裝置清單 Provider
final linkedDevicesProvider =
    AsyncNotifierProvider<LinkedDevicesNotifier, List<LinkedDeviceInfo>>(
  LinkedDevicesNotifier.new,
);

/// 已連結裝置數量 Provider（供設定頁面徽章使用）
final linkedDeviceCountProvider = Provider<int>((ref) {
  return ref.watch(linkedDevicesProvider).valueOrNull?.length ?? 0;
});
