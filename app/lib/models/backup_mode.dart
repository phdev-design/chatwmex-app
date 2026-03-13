/// 備份模式列舉
///
/// 定義三種備份模式：
/// - [full]: 完整備份（對話紀錄 + 媒體 + 私鑰）
/// - [keyOnly]: 僅備份私鑰
/// - [none]: 不備份
enum BackupMode {
  /// 完整備份（對話紀錄 + 媒體 + 私鑰）
  full,

  /// 僅備份私鑰
  keyOnly,

  /// 不備份
  none;

  /// 取得備份模式的顯示名稱
  String get displayName {
    switch (this) {
      case BackupMode.full:
        return '完整備份';
      case BackupMode.keyOnly:
        return '僅備份金鑰';
      case BackupMode.none:
        return '不備份';
    }
  }

  /// 取得備份模式的詳細說明
  String get description {
    switch (this) {
      case BackupMode.full:
        return '備份所有對話紀錄、媒體檔案與加密金鑰。還原時可完整恢復所有資料。';
      case BackupMode.keyOnly:
        return '僅備份您的加密身分金鑰。速度最快，不佔空間。對話紀錄將在您換機登入時從伺服器同步並解密。';
      case BackupMode.none:
        return '不進行任何備份。換機時將無法還原歷史資料。';
    }
  }

  /// 從字串轉換為 BackupMode
  ///
  /// 如果字串不匹配任何模式，預設回傳 [BackupMode.full]
  static BackupMode fromString(String value) {
    return BackupMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => BackupMode.full,
    );
  }
}
