/// Chat2MeX 應用版本配置
class VersionConfig {
  // 🔥 統一版本號管理
  static const String version = '1.0.31';
  static const String buildNumber = '1';
  static const String appName = 'Chat2MeX';
  static const String appDescription = 'Chat2MeX - 一個現代化的即時通訊應用';

  // 版本信息
  static const Map<String, String> versionInfo = {
    'version': version,
    'buildNumber': buildNumber,
    'appName': appName,
    'description': appDescription,
  };

  // 獲取完整版本字符串
  static String get fullVersion => '$appName v$version (Build $buildNumber)';

  // 獲取簡短版本字符串
  static String get shortVersion => 'v$version';

  // 獲取版本號（用於比較）
  static String get versionNumber => version;

  // 獲取構建號
  static String get build => buildNumber;
}
