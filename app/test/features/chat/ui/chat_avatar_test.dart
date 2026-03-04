import 'package:app/features/chat/ui/widgets/chat_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('顯示空網址時使用 fallback', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ChatAvatar(
          avatarUrl: '',
          radius: 18,
          fallbackText: 'A',
          logTag: 'test_avatar',
        ),
      ),
    );

    expect(find.text('A'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('有網址時建立網路圖片元件', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ChatAvatar(
          avatarUrl: '/uploads/avatars/test.png',
          radius: 18,
          fallbackText: 'A',
          logTag: 'test_avatar',
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('載入失敗時回退到 fallback', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ChatAvatar(
          avatarUrl: 'http://127.0.0.1:1/not_found.png',
          radius: 18,
          fallbackText: 'B',
          logTag: 'test_avatar',
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('B'), findsOneWidget);
  });
}
