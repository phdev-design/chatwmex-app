# E2EE 金鑰溢出警告功能測試指南

## 測試目標
驗證當歷史金鑰超過 50 把時，系統會正確顯示警告 Banner，並在設定頁面提示用戶。

## 測試步驟

### 1. 手動觸發金鑰輪替（超過 50 次）

在 Flutter 應用中，你可以建立一個測試頁面或使用 Flutter DevTools 執行以下程式碼：

```dart
// 在任何可以存取 CryptoService 的地方執行
final cryptoService = ref.read(cryptoServiceProvider);

// 模擬金鑰輪替 55 次（超過 50 的上限）
for (int i = 0; i < 55; i++) {
  // 生成隨機私鑰並加入歷史
  final randomKey = base64Encode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256))
  );
  await cryptoService._appendToHistoryPrivateKeys(randomKey);
  print('Added key $i');
}

print('Key rotation test completed');
```

### 2. 驗證警告標記寫入

檢查 SecureStorage 中是否寫入了警告標記：

```dart
final cryptoService = ref.read(cryptoServiceProvider);
final hasWarning = await cryptoService.checkAndClearKeyOverflowWarning();
print('Has overflow warning: $hasWarning'); // 應該輸出 true
```

### 3. 重新開啟設定頁面

1. 導航到設定頁面（Settings Page）
2. 應該看到橙色警告 Banner，內容為：
   - 標題：「金鑰淘汰警告」
   - 訊息：「部分舊訊息的解密金鑰已被自動淘汰，這些訊息可能已無法解密。建議立即備份目前的加密金鑰。」
   - 按鈕：「立即備份」

### 4. 驗證 Banner 只顯示一次

1. 點擊「立即備份」按鈕（目前會顯示開發中訊息）
2. 返回並重新進入設定頁面
3. 橙色警告 Banner 應該消失（因為 checkAndClearKeyOverflowWarning 已清除標記）

### 5. 測試接近上限提示（40-49 把金鑰）

清除所有歷史金鑰並重新測試：

```dart
// 清除歷史金鑰（僅測試用）
await _secureStorage.delete(key: 'e2ee_private_key_history');

// 加入 45 把金鑰（80% of 50）
for (int i = 0; i < 45; i++) {
  final randomKey = base64Encode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256))
  );
  await cryptoService._appendToHistoryPrivateKeys(randomKey);
}
```

重新開啟設定頁面，應該看到藍色提示 Banner：
- 標題：「金鑰使用提示」
- 訊息：「加密金鑰歷史紀錄已使用 45/50，建議定期備份金鑰。」
- 按鈕：「了解更多」

## 驗收條件檢查清單

- [ ] 手動觸發金鑰輪替超過 50 次後，SecureStorage 中寫入警告標記
- [ ] 重新開啟設定頁面時出現橙色警告 Banner
- [ ] 點擊「立即備份」按鈕（目前顯示開發中訊息）
- [ ] Banner 只顯示一次（checkAndClearKeyOverflowWarning 讀後即清除）
- [ ] historyKeyCount >= 40 時顯示藍色提示 Banner
- [ ] historyKeyCount < 40 時不顯示任何 Banner

## 注意事項

1. `_appendToHistoryPrivateKeys` 是私有方法，實際測試時需要透過公開的 API 觸發金鑰輪替
2. 目前「立即備份」按鈕導向的頁面尚未實作，顯示「金鑰備份功能開發中」訊息
3. 如需實作完整的金鑰備份頁面，請參考 `app/lib/features/auth/ui/widgets/key_backup_prompt_dialog.dart`

## 相關檔案

- `app/lib/core/crypto/crypto_service.dart` - 金鑰管理核心邏輯
- `app/lib/features/settings/providers/crypto_health_provider.dart` - 金鑰健康狀態 Provider
- `app/lib/features/profile/ui/settings_page.dart` - 設定頁面 UI
