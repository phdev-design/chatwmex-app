import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/version_config.dart'; // 🔥 新增：版本配置

class DeviceInfoService {
  static final DeviceInfoService _instance = DeviceInfoService._internal();
  factory DeviceInfoService() => _instance;
  DeviceInfoService._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// 獲取設備信息
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final Map<String, dynamic> deviceInfo = {};

      // 獲取平台信息
      deviceInfo['platform'] = Platform.operatingSystem;
      deviceInfo['platform_version'] = Platform.operatingSystemVersion;

      // 獲取應用信息
      final packageInfo = await PackageInfo.fromPlatform();
      deviceInfo['app_version'] = packageInfo.version;
      deviceInfo['app_build_number'] = packageInfo.buildNumber;
      deviceInfo['app_package_name'] = packageInfo.packageName;

      // 獲取網絡連接信息
      final connectivityResult = await Connectivity().checkConnectivity();
      deviceInfo['connection_type'] = connectivityResult.toString();

      // 根據平台獲取具體設備信息
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceInfo['device_model'] = androidInfo.model;
        deviceInfo['device_brand'] = androidInfo.brand;
        deviceInfo['device_manufacturer'] = androidInfo.manufacturer;
        deviceInfo['device_id'] = androidInfo.id;
        deviceInfo['android_version'] = androidInfo.version.release;
        deviceInfo['android_sdk_int'] = androidInfo.version.sdkInt;
        deviceInfo['device_type'] = 'Android';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceInfo['device_model'] = iosInfo.model;
        deviceInfo['device_name'] = iosInfo.name;
        deviceInfo['device_system_name'] = iosInfo.systemName;
        deviceInfo['device_system_version'] = iosInfo.systemVersion;
        deviceInfo['device_identifier'] = iosInfo.identifierForVendor;
        deviceInfo['device_type'] = 'iOS';
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        deviceInfo['device_model'] = windowsInfo.computerName;
        deviceInfo['device_type'] = 'Windows';
      } else if (Platform.isMacOS) {
        // 簡化 macOS 信息獲取
        deviceInfo['device_model'] = 'Mac';
        deviceInfo['device_name'] = 'Mac';
        deviceInfo['device_type'] = 'macOS';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfo.linuxInfo;
        deviceInfo['device_model'] = linuxInfo.name;
        deviceInfo['device_type'] = 'Linux';
      }

      // 獲取 Flutter 和 Dart 版本
      deviceInfo['flutter_version'] = '3.13.0'; // 固定版本
      deviceInfo['dart_version'] = Platform.version;

      // 獲取時間戳
      deviceInfo['timestamp'] = DateTime.now().toIso8601String();
      deviceInfo['timezone'] = DateTime.now().timeZoneName;
      deviceInfo['timezone_offset'] = DateTime.now().timeZoneOffset.inHours;

      return deviceInfo;
    } catch (e) {
      print('獲取設備信息失敗: $e');
      // 返回基本信息
      return {
        'platform': Platform.operatingSystem,
        'platform_version': Platform.operatingSystemVersion,
        'device_type': Platform.operatingSystem,
        'timestamp': DateTime.now().toIso8601String(),
        'error': e.toString(),
      };
    }
  }

  /// 獲取簡化的設備信息（用於登入）
  Future<Map<String, dynamic>> getLoginDeviceInfo() async {
    try {
      final deviceInfo = await getDeviceInfo();

      // 只返回登入時需要的基本信息
      return {
        'device_type': deviceInfo['device_type'] ?? Platform.operatingSystem,
        'device_model': deviceInfo['device_model'] ?? 'Unknown',
        'platform': deviceInfo['platform'] ?? Platform.operatingSystem,
        'platform_version':
            deviceInfo['platform_version'] ?? Platform.operatingSystemVersion,
        'app_version':
            deviceInfo['app_version'] ?? VersionConfig.version, // 🔥 使用版本配置
        'connection_type': deviceInfo['connection_type'] ?? 'unknown',
        'timestamp':
            deviceInfo['timestamp'] ?? DateTime.now().toIso8601String(),
        'timezone': deviceInfo['timezone'] ?? DateTime.now().timeZoneName,
      };
    } catch (e) {
      print('獲取登入設備信息失敗: $e');
      return {
        'device_type': Platform.operatingSystem,
        'device_model': 'Unknown',
        'platform': Platform.operatingSystem,
        'platform_version': Platform.operatingSystemVersion,
        'app_version': VersionConfig.version, // 🔥 使用版本配置
        'connection_type': 'unknown',
        'timestamp': DateTime.now().toIso8601String(),
        'timezone': DateTime.now().timeZoneName,
        'error': e.toString(),
      };
    }
  }

  /// 獲取用戶代理字符串
  String getUserAgent() {
    final deviceInfo = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    return '${VersionConfig.appName}/${VersionConfig.version} ($deviceInfo $version) Flutter/3.13.0'; // 🔥 使用版本配置
  }
}
