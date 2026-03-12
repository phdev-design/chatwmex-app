import 'package:app/core/media/media_service.dart';
import 'package:app/features/chat/providers/chat_room_provider.dart';
import 'package:app/features/chat/ui/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for ChatInputBar gesture detection features.
/// 
/// These tests verify the UI behavior for:
/// - Property 1: Slide-to-cancel gesture detection (Requirements 1.1)
/// - Property 2: Visual feedback during slide gesture (Requirements 1.2, 8.1, 8.2)
/// - Property 5: Short recording rejection (Requirements 2.1)
///
/// Note: These tests focus on UI state changes and visual feedback.
/// Full integration testing requires the cancelRecording method to be implemented
/// in ChatRoomProvider (Task 2.1).

/// Mock MediaService for testing
class MockMediaService extends MediaService {
  bool _hasPermission = true;

  void setPermission(bool hasPermission) {
    _hasPermission = hasPermission;
  }

  @override
  Future<bool> checkMicrophonePermission() async => _hasPermission;

  @override
  Future<void> openSettings() async {}

  @override
  Future<String?> startRecording(String path) async => path;

  @override
  Future<String?> stopRecording() async => null;
}

/// Mock ChatRoomNotifier that returns a fixed state
class MockChatRoomNotifier extends ChatRoomNotifier {
  MockChatRoomNotifier(ChatRoomParams params) : super(params);

  @override
  ChatRoomState build(ChatRoomParams arg) => ChatRoomState(
    messages: [],
    hasMore: false,
    isLoading: false,
    isRecording: false,
    isSending: false,
    offset: 0,
  );

  @override
  Future<void> startRecording() async {
    state = state.copyWith(isRecording: true);
  }

  @override
  Future<void> cancelRecording() async {
    state = state.copyWith(isRecording: false);
  }

  @override
  Future<void> stopRecordingAndSend() async {
    state = state.copyWith(isRecording: false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMediaService mockMediaService;

  setUp(() {
    mockMediaService = MockMediaService();
    mockMediaService.setPermission(true);
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        chatRoomProvider(testParams).overrideWith((ref) => MockChatRoomNotifier(testParams)),
        mediaServiceProvider.overrideWithValue(mockMediaService),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  final testParams = ChatRoomParams(
    roomId: 'test-room',
    isRoom: true,
    currentUserId: 'user-1',
    token: 'test-token',
  );

  group('ChatInputBar Gesture Detection Widget Tests', () {
    // Feature: encrypted-audio-messaging-ui-completion, Property 1: Slide-to-cancel gesture detection
    // **Validates: Requirements 1.1**
    testWidgets(
      'Property 1: Slide-to-cancel gesture detection - UI shows cancel state when drag exceeds 100px',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            ChatInputBar(
              params: testParams,
              isRoom: true,
              title: 'Test Room',
              currentUserId: 'user-1',
            ),
          ),
        );

        // Find the microphone button
        final micButton = find.byIcon(Icons.mic_rounded);
        expect(micButton, findsOneWidget);

        // Test multiple drag distances to verify threshold behavior
        final testCases = [
          {'distance': 50.0, 'shouldShowCancel': false, 'description': '50px - below threshold'},
          {'distance': 99.0, 'shouldShowCancel': false, 'description': '99px - just below threshold'},
          {'distance': 101.0, 'shouldShowCancel': true, 'description': '101px - above threshold'},
          {'distance': 150.0, 'shouldShowCancel': true, 'description': '150px - well above threshold'},
          {'distance': 200.0, 'shouldShowCancel': true, 'description': '200px - far above threshold'},
        ];

        for (final testCase in testCases) {
          final distance = testCase['distance'] as double;
          final shouldShowCancel = testCase['shouldShowCancel'] as bool;
          final description = testCase['description'] as String;

          // Start recording with long press
          final gesture = await tester.startGesture(
            tester.getCenter(micButton),
          );
          await tester.pump(const Duration(milliseconds: 100));

          // Simulate horizontal drag
          await gesture.moveBy(Offset(-distance, 0));
          await tester.pump();

          // Verify UI state based on distance
          if (shouldShowCancel) {
            expect(
              find.text('🚫 鬆開取消'),
              findsOneWidget,
              reason: 'Cancel text should appear for $description',
            );
            expect(
              find.text('🔴 正在錄音... ← 滑動取消'),
              findsNothing,
              reason: 'Normal recording text should be hidden for $description',
            );
          } else {
            expect(
              find.text('🔴 正在錄音... ← 滑動取消'),
              findsOneWidget,
              reason: 'Normal recording text should appear for $description',
            );
            expect(
              find.text('🚫 鬆開取消'),
              findsNothing,
              reason: 'Cancel text should not appear for $description',
            );
          }

          // Release the gesture and wait for state to reset
          await gesture.up();
          await tester.pumpAndSettle();
          
          // Wait a bit before next test
          await tester.pump(const Duration(milliseconds: 500));
        }
      },
    );

    // Feature: encrypted-audio-messaging-ui-completion, Property 2: Visual feedback during slide gesture
    // **Validates: Requirements 1.2, 8.1, 8.2**
    testWidgets(
      'Property 2: Visual feedback during slide gesture - displays correct text and styling based on drag distance',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            ChatInputBar(
              params: testParams,
              isRoom: true,
              title: 'Test Room',
              currentUserId: 'user-1',
            ),
          ),
        );

        final micButton = find.byIcon(Icons.mic_rounded);

        // Test visual feedback at different drag distances
        final testCases = [
          {
            'distance': 0.0,
            'expectedText': '🔴 正在錄音... ← 滑動取消',
            'shouldBeRed': false,
            'description': 'Initial state - normal recording text'
          },
          {
            'distance': 50.0,
            'expectedText': '🔴 正在錄音... ← 滑動取消',
            'shouldBeRed': false,
            'description': 'Below threshold - normal recording text'
          },
          {
            'distance': 101.0,
            'expectedText': '🚫 鬆開取消',
            'shouldBeRed': true,
            'description': 'Above threshold - cancel text in red'
          },
          {
            'distance': 150.0,
            'expectedText': '🚫 鬆開取消',
            'shouldBeRed': true,
            'description': 'Well above threshold - cancel text in red'
          },
        ];

        for (final testCase in testCases) {
          final distance = testCase['distance'] as double;
          final expectedText = testCase['expectedText'] as String;
          final shouldBeRed = testCase['shouldBeRed'] as bool;
          final description = testCase['description'] as String;

          // Start recording
          final gesture = await tester.startGesture(
            tester.getCenter(micButton),
          );
          await tester.pump(const Duration(milliseconds: 100));

          // Drag to the specified distance
          if (distance > 0) {
            await gesture.moveBy(Offset(-distance, 0));
            await tester.pump();
          }

          // Verify the correct text is displayed
          expect(
            find.text(expectedText),
            findsOneWidget,
            reason: 'Expected "$expectedText" for $description',
          );

          // Verify text styling for cancel state
          if (shouldBeRed) {
            final textWidget = tester.widget<Text>(find.text(expectedText));
            expect(
              textWidget.style?.color,
              Colors.red,
              reason: 'Cancel text should be red for $description',
            );
            expect(
              textWidget.style?.fontWeight,
              FontWeight.bold,
              reason: 'Cancel text should be bold for $description',
            );
          }

          // Release and reset
          await gesture.up();
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 500));
        }
      },
    );

    // Feature: encrypted-audio-messaging-ui-completion, Property 5: Short recording rejection
    // **Validates: Requirements 2.1**
    testWidgets(
      'Property 5: Short recording rejection - shows toast for recordings under 1 second',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            ChatInputBar(
              params: testParams,
              isRoom: true,
              title: 'Test Room',
              currentUserId: 'user-1',
            ),
          ),
        );

        final micButton = find.byIcon(Icons.mic_rounded);

        // Test various short recording durations
        final testDurations = [
          {'milliseconds': 100, 'description': '0.1 seconds'},
          {'milliseconds': 500, 'description': '0.5 seconds'},
          {'milliseconds': 900, 'description': '0.9 seconds'},
        ];

        for (final testCase in testDurations) {
          final milliseconds = testCase['milliseconds'] as int;
          final description = testCase['description'] as String;

          // Start recording
          final gesture = await tester.startGesture(
            tester.getCenter(micButton),
          );
          await tester.pump(const Duration(milliseconds: 100));

          // Wait for the specified duration (but less than 1 second)
          await tester.pump(Duration(milliseconds: milliseconds));

          // Release the gesture
          await gesture.up();
          await tester.pumpAndSettle();

          // Verify the "錄音時間過短" toast is displayed
          expect(
            find.text('錄音時間過短'),
            findsOneWidget,
            reason: 'Toast should appear for recording of $description',
          );

          // Wait for toast to disappear
          await tester.pumpAndSettle(const Duration(seconds: 3));
        }
      },
    );

    // Additional test: Valid recording duration (≥1 second) should not show rejection toast
    testWidgets(
      'Property 5 complement: Recordings of 1 second or more should not show rejection toast',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            ChatInputBar(
              params: testParams,
              isRoom: true,
              title: 'Test Room',
              currentUserId: 'user-1',
            ),
          ),
        );

        final micButton = find.byIcon(Icons.mic_rounded);

        // Start recording
        final gesture = await tester.startGesture(
          tester.getCenter(micButton),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Wait for 1 second (minimum valid duration)
        // Note: The timer updates every second, so we need to wait for the periodic timer to fire
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 100));

        // Verify timer updated to show 00:01
        expect(find.text('00:01'), findsOneWidget);

        // Release the gesture
        await gesture.up();
        await tester.pumpAndSettle();

        // Verify the "錄音時間過短" toast is NOT displayed
        expect(
          find.text('錄音時間過短'),
          findsNothing,
          reason: 'Toast should not appear for valid recording duration',
        );
      },
    );

    // Additional test: State reset after recording
    testWidgets(
      'Recording state is properly reset after completion or cancellation',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            ChatInputBar(
              params: testParams,
              isRoom: true,
              title: 'Test Room',
              currentUserId: 'user-1',
            ),
          ),
        );

        final micButton = find.byIcon(Icons.mic_rounded);

        // Test 1: Cancel via slide gesture
        var gesture = await tester.startGesture(tester.getCenter(micButton));
        await tester.pump(const Duration(milliseconds: 100));

        await gesture.moveBy(const Offset(-150, 0));
        await tester.pump();
        expect(find.text('🚫 鬆開取消'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();

        // Verify state is reset
        expect(find.text('🚫 鬆開取消'), findsNothing);
        expect(find.text('輸入訊息...'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 500));

        // Test 2: Cancel via short duration
        gesture = await tester.startGesture(tester.getCenter(micButton));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.pump(const Duration(milliseconds: 500));
        await gesture.up();
        await tester.pumpAndSettle();

        // Verify state is reset and toast appears
        expect(find.text('錄音時間過短'), findsOneWidget);
        expect(find.text('輸入訊息...'), findsOneWidget);
      },
    );
  });
}
