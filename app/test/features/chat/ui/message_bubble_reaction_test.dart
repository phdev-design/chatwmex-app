import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/widgets/message_bubble.dart';
import 'package:app/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  final params = ChatRoomParams(
    roomId: 'room-1',
    isRoom: true,
    currentUserId: 'me',
    token: 'token',
  );

  testWidgets('顯示 reaction bar', (tester) async {
    final msg = Message(
      id: 'm1',
      content: 'hello',
      senderId: 'u1',
      createdAt: DateTime.now(),
      reactions: const {
        '❤️': ['u1'],
        '👍': ['u2', 'u3'],
      },
    );
    const state = ChatRoomState();

    await tester.pumpWidget(
      wrap(
        MessageBubble(
          msg: msg,
          isMe: false,
          state: state,
          params: params,
          isRoom: true,
          currentUserId: 'me',
          title: 'room',
          onScrollToMessage: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('👍'), findsOneWidget);
  });

  testWidgets('長按可開啟表情回覆選單', (tester) async {
    final msg = Message(
      id: 'm2',
      content: 'long press me',
      senderId: 'u1',
      createdAt: DateTime.now(),
    );
    const state = ChatRoomState();

    await tester.pumpWidget(
      wrap(
        MessageBubble(
          msg: msg,
          isMe: false,
          state: state,
          params: params,
          isRoom: true,
          currentUserId: 'me',
          title: 'room',
          onScrollToMessage: (_) async {},
        ),
      ),
    );

    await tester.longPress(find.text('long press me'));
    await tester.pumpAndSettle();

    expect(find.text('回覆'), findsOneWidget);
    expect(find.text('👍'), findsWidgets);
  });

  testWidgets('iPhone SE 尺寸下反應選單不超出邊界', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final msg = Message(
      id: 'm3',
      content: 'small screen check',
      senderId: 'u1',
      createdAt: DateTime.now(),
    );
    const state = ChatRoomState();

    await tester.pumpWidget(
      wrap(
        Align(
          alignment: Alignment.bottomLeft,
          child: MessageBubble(
            msg: msg,
            isMe: false,
            state: state,
            params: params,
            isRoom: true,
            currentUserId: 'me',
            title: 'room',
            onScrollToMessage: (_) async {},
          ),
        ),
      ),
    );

    await tester.longPress(find.text('small screen check'));
    await tester.pumpAndSettle();

    final menuFinder = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      if (widget.constraints == null) return false;
      return widget.constraints!.maxWidth == 240;
    });
    expect(menuFinder, findsOneWidget);

    final rect = tester.getRect(menuFinder);
    expect(rect.left >= 0, true);
    expect(rect.right <= 375, true);
    expect(rect.top >= 0, true);
    expect(rect.bottom <= 667, true);
  });
}
