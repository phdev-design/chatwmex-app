/// 金鑰備份檔案資料模型
///
/// 定義僅包含加密私鑰的輕量級備份檔案結構（chatwmex_key_backup.json）
class KeyBackupFile {
  /// 備份檔案格式版本
  final String version;

  /// 加密後的私鑰（Base64 編碼）
  final String encryptedKey;

  /// 加密用的鹽值（Base64 編碼）
  final String salt;

  /// 初始化向量（Base64 編碼）
  final String iv;

  /// 加密演算法名稱
  final String algorithm;

  /// 備份時間戳記
  final DateTime timestamp;

  /// 建立 KeyBackupFile 實例
  const KeyBackupFile({
    required this.version,
    required this.encryptedKey,
    required this.salt,
    required this.iv,
    required this.algorithm,
    required this.timestamp,
  });

  /// 從 JSON 反序列化
  factory KeyBackupFile.fromJson(Map<String, dynamic> json) {
    return KeyBackupFile(
      version: json['version'] as String,
      encryptedKey: json['encryptedKey'] as String,
      salt: json['salt'] as String,
      iv: json['iv'] as String? ?? '',
      algorithm: json['algorithm'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// 序列化為 JSON
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'encryptedKey': encryptedKey,
      'salt': salt,
      'iv': iv,
      'algorithm': algorithm,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// 驗證檔案格式是否有效
  ///
  /// 檢查必要欄位是否存在且加密演算法是否為 AES-GCM-256
  bool isValid() {
    return version.isNotEmpty &&
        encryptedKey.isNotEmpty &&
        salt.isNotEmpty &&
        algorithm == 'AES-GCM-256';
  }
}
