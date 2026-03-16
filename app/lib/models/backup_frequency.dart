/// 自動備份頻率列舉
enum BackupFrequency {
  daily,
  weekly,
  monthly;

  String get displayName {
    switch (this) {
      case BackupFrequency.daily:
        return '每天';
      case BackupFrequency.weekly:
        return '每週';
      case BackupFrequency.monthly:
        return '每月';
    }
  }

  String get description {
    switch (this) {
      case BackupFrequency.daily:
        return '每天自動備份一次';
      case BackupFrequency.weekly:
        return '每週自動備份一次';
      case BackupFrequency.monthly:
        return '每月自動備份一次';
    }
  }

  static BackupFrequency fromString(String value) {
    return BackupFrequency.values.firstWhere(
      (f) => f.name == value,
      orElse: () => BackupFrequency.daily,
    );
  }
}
