# Splash Screen Mounted Check 修正

## 問題描述

在 `splash_screen.dart` 的初始化序列中，多個 `async await` 操作後沒有檢查 `mounted` 狀態，導致在 widget dispose 後仍然嘗試使用 `ref` 或 `context`，在重啟/熱重載時出現警告。

## 問題位置

**檔案：** `app/lib/features/splash/ui/splash_screen.dart`

### 原始問題

在 `_loadHeavyDataInBackground()` 函式中，多個 `await` 操作後沒有檢查 `mounted`：

```dart
Future<void> _loadHeavyDataInBackground() async {
  try {
    final storage = ref.read(storageServiceProvider);
    final userId = await storage.read('user_id') ?? '';
    final crypto = ref.read(cryptoServiceProvider);  // ❌ 沒有 mounted 檢查
    
    try {
      final pubKey = await crypto.initialize(userId: userId);
      await ref.read(authRepositoryProvider).updatePublicKey(pubKey);  // ❌ 沒有 mounted 檢查
    } on PrivateKeyNotFoundException catch (_) {
      // ...
    }

    await ref.read(publicKeyCacheServiceProvider).clearAllCache();  // ❌ 沒有 mounted 檢查

    final pendingDeviceId = await storage.read('pending_unregister_device_id');
    final networkService = ref.read(networkServiceProvider);  // ❌ 沒有 mounted 檢查

    // ... 更多沒有 mounted 檢查的 await 操作
  }
}
```

## 修正方案

在每個 `await` 操作後加入 `mounted` 檢查：

```dart
if (!mounted) return;
```

### 修正後的程式碼

```dart
Future<void> _loadHeavyDataInBackground() async {
  try {
    final storage = ref.read(storageServiceProvider);
    final userId = await storage.read('user_id') ?? '';
    
    if (!mounted) return;  // ✅ 加入檢查
    
    final crypto = ref.read(cryptoServiceProvider);
    
    try {
      final pubKey = await crypto.initialize(userId: userId);
      
      if (!mounted) return;  // ✅ 加入檢查
      
      await ref.read(authRepositoryProvider).updatePublicKey(pubKey);
    } on PrivateKeyNotFoundException catch (_) {
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const KeyRecoveryDialog(),
        );
      }
      return;
    }

    if (!mounted) return;  // ✅ 加入檢查

    await ref.read(publicKeyCacheServiceProvider).clearAllCache();

    if (!mounted) return;  // ✅ 加入檢查

    final pendingDeviceId = await storage.read('pending_unregister_device_id');
    
    if (!mounted) return;  // ✅ 加入檢查
    
    final networkService = ref.read(networkServiceProvider);

    // ... 其餘操作都加入了 mounted 檢查
  }
}
```

## 修正位置總結

共加入了 **8 個** `if (!mounted) return;` 檢查：

1. ✅ 第 81 行：`await storage.read('user_id')` 之後
2. ✅ 第 88 行：`await crypto.initialize()` 之後
3. ✅ 第 99 行：`try-catch` 區塊之後
4. ✅ 第 102 行：`await clearAllCache()` 之後
5. ✅ 第 109 行：`await storage.read()` 之後
6. ✅ 第 121 行：`await initOneSignal()` 之後
7. ✅ 第 124 行：`await getSubscriptionId()` 之後
8. ✅ 第 143 行：`await refreshToken()` 之後（在 401 錯誤處理中）

## 為什麼需要這些檢查？

### 問題場景

1. **熱重載（Hot Reload）**
   - 用戶在開發時執行熱重載
   - Splash screen 的 widget 被 dispose
   - 但背景的 `_loadHeavyDataInBackground()` 仍在執行
   - 嘗試使用 `ref` 或 `context` 時會出現警告

2. **快速導航**
   - 用戶在 splash screen 停留時間很短
   - 在背景任務完成前就導航到其他頁面
   - Widget 被 dispose，但背景任務仍在執行

3. **應用重啟**
   - 應用在背景任務執行期間被重啟
   - Widget 生命週期結束，但 Future 仍在執行

### 錯誤訊息範例

```
Warning: A Provider was used after being disposed.
```

或

```
Warning: setState() or markNeedsBuild() called after dispose().
```

## 最佳實踐

### 規則 1：每個 await 後檢查 mounted

```dart
final result = await someAsyncOperation();
if (!mounted) return;  // ✅ 立即檢查
// 繼續使用 result
```

### 規則 2：使用 context 前檢查 mounted

```dart
if (!mounted) return;
context.go('/some-route');  // ✅ 安全使用 context
```

### 規則 3：使用 ref.read() 前檢查 mounted（在 async 函式中）

```dart
if (!mounted) return;
final provider = ref.read(someProvider);  // ✅ 安全使用 ref
```

### 規則 4：在 showDialog 前檢查 mounted

```dart
if (mounted) {  // ✅ 使用 if (mounted) 包裹
  await showDialog(
    context: context,
    builder: (context) => SomeDialog(),
  );
}
```

## 驗證結果

### 編譯檢查
```bash
flutter analyze lib/features/splash/ui/splash_screen.dart
```
結果：✅ No issues found!

### 診斷檢查
```bash
getDiagnostics(["app/lib/features/splash/ui/splash_screen.dart"])
```
結果：✅ No diagnostics found

## 測試建議

1. **熱重載測試**
   - 在 splash screen 顯示時執行熱重載
   - 確認沒有出現 "Provider was used after being disposed" 警告

2. **快速導航測試**
   - 啟動應用後立即點擊返回或導航
   - 確認沒有出現 mounted 相關警告

3. **應用重啟測試**
   - 在 splash screen 顯示時重啟應用
   - 確認沒有出現錯誤或警告

## 相關檔案

- ✅ `app/lib/features/splash/ui/splash_screen.dart` - 已修正

## 其他可能需要檢查的地方

建議搜尋其他可能有類似問題的地方：

```bash
# 搜尋使用 ref.read() 但可能缺少 mounted 檢查的地方
grep -r "await.*ref\.read" app/lib/ | grep -v "if (!mounted)"

# 搜尋使用 context.go 但可能缺少 mounted 檢查的地方
grep -r "await.*context\.go" app/lib/ | grep -v "if (!mounted)"
```

## 結論

已成功修正 splash screen 中所有在 `await` 操作後缺少 `mounted` 檢查的問題。這些修正可以防止在 widget dispose 後仍然嘗試使用 `ref` 或 `context`，避免在開發時出現警告訊息。

雖然這些錯誤不會導致應用 crash，但修正它們可以：
1. ✅ 提升程式碼品質
2. ✅ 避免潛在的記憶體洩漏
3. ✅ 改善開發體驗（減少警告訊息）
4. ✅ 遵循 Flutter 最佳實踐
