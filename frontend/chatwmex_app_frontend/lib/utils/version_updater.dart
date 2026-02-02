import '../config/version_config.dart';

/// 版本更新工具
class VersionUpdater {
  /// 獲取當前版本信息
  static Map<String, String> getCurrentVersion() {
    return VersionConfig.versionInfo;
  }

  /// 獲取版本號
  static String getVersion() {
    return VersionConfig.version;
  }

  /// 獲取構建號
  static String getBuildNumber() {
    return VersionConfig.buildNumber;
  }

  /// 獲取完整版本字符串
  static String getFullVersion() {
    return VersionConfig.fullVersion;
  }

  /// 獲取簡短版本字符串
  static String getShortVersion() {
    return VersionConfig.shortVersion;
  }

  /// 獲取應用名稱
  static String getAppName() {
    return VersionConfig.appName;
  }

  /// 獲取應用描述
  static String getAppDescription() {
    return VersionConfig.appDescription;
  }

  /// 打印版本信息（用於調試）
  static void printVersionInfo() {
    print('=== Chat2MeX 版本信息 ===');
    print('應用名稱: ${getAppName()}');
    print('版本號: ${getVersion()}');
    print('構建號: ${getBuildNumber()}');
    print('完整版本: ${getFullVersion()}');
    print('簡短版本: ${getShortVersion()}');
    print('應用描述: ${getAppDescription()}');
    print('========================');
  }
}
