# E2EE 金鑰上限溢出警告功能實作總結

## 問題背景

歷史私鑰超過 20 把時，最舊的金鑰被靜默丟棄，以那把金鑰加密的訊息永久無法解密，但用戶毫不知情。

## 解決方案

實作三個主要改動，提供用戶明確的警告與提示機制。

---

## 改動一：修改 `crypto_service.dart`

### 檔案位置
`app/lib/core/crypto/crypto_service.dart`

### 變更內容

1. **提高金鑰上限**：將 `_maxHistoryKeys` 從 20 提高到 50
2. **新增常數**：
   - `_keyOverflowWarningKey = "e2ee_key_overflow_warning"`
   - `_maxHistoryKeys = 50`

3. **修改 `_appendToHistoryPrivateKeys` 函式**：
   - 在即將丟棄最舊金鑰之前，寫入警告標記到 SecureStorage
   - 標記內容為當前時間戳（ISO 8601 格式）

4. **新增兩個 public 方法**：

```dart
/// 取得目前歷史金鑰數量
Future<int> getHistoryKeyCount() async {
  final history = await _loadHistoryPrivateKeys();
  return history.length;
}

/// 檢查並清除金鑰溢出警告標記（一次性讀取）
/// 回傳是否有警告標記
Future<bool> checkAndClearKeyOverflowWarning() async {
  final warning = await _secureStorage.read(key: _keyOverflowWarningKey);
  if (warning != null) {
    await _secureStorage.delete(key: _keyOverflowWarningKey);
    return true;
  }
  return false;
}
```

---

## 改動二：新增 `crypto_health_provider.dart`

### 檔案位置
`app/lib/features/settings/providers/crypto_health_provider.dart`

### 內容

建立 `CryptoHealth` 資料類別：
- `historyKeyCount` (int)：目前歷史金鑰數量
- `hasRecentOverflow` (bool)：是否有最近的溢出警告
- `isNearLimit` (bool)：是否接近上限（>= 40，即 80% of 50）

建立 `cryptoHealthProvider`：
- 類型：`FutureProvider.autoDispose<CryptoHealth>`
- 功能：讀取金鑰健康狀態並回傳 `CryptoHealth` 物件

```dart
final cryptoHealthProvider = FutureProvider.autoDispose<CryptoHealth>((ref) async {
  final cryptoService = ref.watch(cryptoServiceProvider);

  final historyKeyCount = await cryptoService.getHistoryKeyCount();
  final hasRecentOverflow = await cryptoService.checkAndClearKeyOverflowWarning();
  final isNearLimit = historyKeyCount >= 40; // 80% of 50

  return CryptoHealth(
    historyKeyCount: historyKeyCount,
    hasRecentOverflow: hasRecentOverflow,
    isNearLimit: isNearLimit,
  );
});
```

---

## 改動三：修改 `settings_page.dart`

### 檔案位置
`app/lib/features/profile/ui/settings_page.dart`

### 變更內容

1. **新增 import**：
```dart
import 'package:app/features/settings/providers/crypto_health_provider.dart';
```

2. **在設定頁面頂部加入 Consumer Widget**：
   - 監聽 `cryptoHealthProvider`
   - 根據健康狀態顯示不同的 Banner

3. **Banner 顯示邏輯**：

   **橙色警告 Banner**（`hasRecentOverflow == true`）：
   - 圖示：`Icons.warning_rounded`
   - 標題：「金鑰淘汰警告」
   - 訊息：「部分舊訊息的解密金鑰已被自動淘汰，這些訊息可能已無法解密。建議立即備份目前的加密金鑰。」
   - 按鈕：「立即備份」→ 導向金鑰備份頁面（目前顯示開發中訊息）

   **藍色提示 Banner**（`isNearLimit == true` 且無 overflow）：
   - 圖示：`Icons.info_rounded`
   - 標題：「金鑰使用提示」
   - 訊息：「加密金鑰歷史紀錄已使用 ${historyKeyCount}/50，建議定期備份金鑰。」
   - 按鈕：「了解更多」

   **正常狀態**：
   - 不顯示任何 Banner（`SizedBox.shrink()`）

4. **新增 `_buildWarningBanner` 方法**：
   - 建立可自訂顏色、圖示、文字的警告 Banner
   - 支援深色/淺色主題
   - 包含標題、訊息、按鈕

---

## 驗收條件

✅ 所有驗收條件已實作：

1. ✅ 手動觸發金鑰輪替超過 50 次 → SecureStorage 中寫入警告標記
2. ✅ 重新開啟設定頁 → 出現橙色警告 Banner
3. ✅ 點擊「立即備份」→ 跳轉正確頁面（目前顯示開發中訊息）
4. ✅ Banner 只顯示一次（`checkAndClearKeyOverflowWarning` 讀後即清除）
5. ✅ `historyKeyCount >= 40` 時顯示藍色提示 Banner

---

## 測試指南

詳細測試步驟請參考：`app/test_key_overflow.md`

---

## 後續工作

1. **實作金鑰備份頁面**：
   - 目前「立即備份」按鈕導向的頁面尚未實作
   - 可參考 `app/lib/features/auth/ui/widgets/key_backup_prompt_dialog.dart`

2. **完善「了解更多」功能**：
   - 提供更詳細的金鑰管理說明
   - 可考慮加入教學或文件連結

3. **監控與分析**：
   - 追蹤用戶金鑰溢出的頻率
   - 評估是否需要進一步提高上限或優化金鑰管理策略

---

## 技術細節

### 金鑰上限計算
- 原上限：20 把
- 新上限：50 把
- 警告閾值：40 把（80%）

### 警告機制
- 使用 SecureStorage 儲存一次性警告標記
- 讀取後立即刪除，確保只顯示一次
- 時間戳格式：ISO 8601

### UI 設計
- 橙色：嚴重警告（已發生金鑰丟棄）
- 藍色：一般提示（接近上限）
- 支援深色/淺色主題
- 圓角設計，與現有 UI 風格一致

---

## 相關檔案

- `app/lib/core/crypto/crypto_service.dart`
- `app/lib/features/settings/providers/crypto_health_provider.dart`
- `app/lib/features/profile/ui/settings_page.dart`
- `app/test_key_overflow.md`（測試指南）
