/// 備份檔案類型列舉
enum BackupType {
  /// 完整備份（對話紀錄 + 媒體 + 私鑰）
  full,

  /// 僅金鑰備份
  keyOnly,
}

/// 備份檔案資訊
///
/// 用於顯示 Google Drive 中的備份檔案列表
class BackupFileInfo {
  /// 檔案 ID（Google Drive 檔案 ID）
  final String id;

  /// 檔案名稱
  final String name;

  /// 建立時間
  final DateTime? createdTime;

  /// 檔案大小（位元組）
  final String? size;

  /// 備份類型
  final BackupType type;

  /// 建立 BackupFileInfo 實例
  BackupFileInfo({
    required this.id,
    required this.name,
    this.createdTime,
    this.size,
    required this.type,
  });

  /// 取得備份類型的顯示名稱
  String get displayName {
    switch (type) {
      case BackupType.full:
        return '完整備份';
      case BackupType.keyOnly:
        return '金鑰備份';
    }
  }

  /// 取得格式化的檔案大小
  ///
  /// 將位元組數轉換為人類可讀的格式（B, KB, MB）
  String get displaySize {
    if (size == null) return '未知';
    final bytes = int.tryParse(size!) ?? 0;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
