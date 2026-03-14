# E2EE 自己發送訊息解密失敗修復 - 快速參考

## 問題

黑色手機（test2）生成新密鑰對後：
- ✅ 能解密對方發來的訊息
- ❌ 無法解密自己發送的訊息

## 原因

接收訊息時儲存了密文而不是明文：

```dart
// ❌ 錯誤代碼
LocalDbService().insertMessages([rawMessage]);  // 儲存密文
```

## 修復

修改 `app/lib/features/chat/providers/chat_room_provider.dart` line 158-180：

```dart
// ✅ 修復後
} else if (event == 'chat_message') {
  final rawMessage = Message.fromJson(payload);
  _tryDecryptMessage(rawMessage).then((message) async {  // 改為 async
    _addMessage(message);
    await LocalDbService().insertMessages([message]);  // 儲存明文
    // ...
  });
}
```

## 關鍵變更

1. `.then((message) {` → `.then((message) async {`
2. `insertMessages([rawMessage])` → `insertMessages([message])`
3. `Future(() => ...)` → `await ...`

## 測試

```bash
cd app
flutter test
```

驗證：
1. 發送訊息後 LocalDB 儲存明文
2. Re-encrypt flow 能讀取明文
3. 金鑰遺失後能恢復自己的訊息

## 影響

- 所有訊息（包括自己發送的）都儲存明文
- Re-encrypt flow 可以正常工作
- 符合 E2EE 標準做法（WhatsApp、Signal）
