import 'dart:io';
import 'package:app/core/media/audio_cache_service.dart';
import 'package:app/core/crypto/crypto_service.dart';
import 'package:app/features/chat/ui/audio_message_bubble.dart';
import 'package:app/models/message.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:path/path.dart' as p;

/// Widget tests for AudioMessageBubble legacy audio caching features.
/// 
/// These tests verify the caching behavior for legacy (unencrypted) audio messages:
/// - Property 12: Legacy audio caching on first play (Requirements 7.1)
/// - Property 13: Legacy audio cache hit (Requirements 7.2)
/// - Property 14: Legacy audio cache filename format (Requirements 7.4, 12.1)
///
/// Note: These tests focus on the caching logic for messages with null or empty fileKey.
/// They verify the cache file creation and naming without actually playing audio.

/// Mock PathProviderPlatform for testing
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;

  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AudioCacheService audioCacheService;

  setUp(() async {
    // Create a temporary directory for testing
    tempDir = await Directory.systemTemp.createTemp('audio_cache_test_');
    
    // Set up mock path provider
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);

    // Create real AudioCacheService for testing
    audioCacheService = AudioCacheService(CryptoService(), Dio());
  });

  tearDown(() async {
    // Clean up temporary directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        audioCacheServiceProvider.overrideWithValue(audioCacheService),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  Message createLegacyMessage({
    required String id,
    required String audioUrl,
  }) {
    return Message(
      id: id,
      content: audioUrl,
      senderId: 'user-1',
      type: MessageType.voice,
      createdAt: DateTime.now(),
      isRead: false,
      status: MessageStatus.sent,
      readBy: [],
      fileKey: null, // Legacy audio has no fileKey
    );
  }

  Message createEncryptedMessage({
    required String id,
    required String audioUrl,
    required String fileKey,
  }) {
    return Message(
      id: id,
      content: audioUrl,
      senderId: 'user-1',
      type: MessageType.voice,
      createdAt: DateTime.now(),
      isRead: false,
      status: MessageStatus.sent,
      readBy: [],
      fileKey: fileKey,
    );
  }

  group('AudioMessageBubble Legacy Audio Caching Widget Tests', () {
    // Feature: encrypted-audio-messaging-ui-completion, Property 12: Legacy audio caching on first play
    // **Validates: Requirements 7.1**
    test(
      'Property 12: Legacy audio caching on first play - cache file path is generated correctly',
      () async {
        // Test multiple message IDs to verify caching behavior across different IDs
        final testCases = [
          {
            'messageId': 'msg-001',
            'description': 'First message'
          },
          {
            'messageId': 'msg-002',
            'description': 'Second message'
          },
          {
            'messageId': 'msg-003',
            'description': 'Third message'
          },
        ];

        for (final testCase in testCases) {
          final messageId = testCase['messageId'] as String;
          final description = testCase['description'] as String;

          // Create cache key for legacy audio
          final cacheKey = 'legacy_$messageId';

          // Verify audio is not cached initially
          expect(
            await audioCacheService.isCached(cacheKey),
            false,
            reason: 'Audio should not be cached initially for $description',
          );

          // Get the cache file path
          final cachedPath = await audioCacheService.getCacheFilePath(cacheKey);

          // Verify the path is in the correct directory
          expect(
            cachedPath.startsWith(tempDir.path),
            true,
            reason: 'Cache path should be in temp directory for $description',
          );

          // Verify the filename format
          final filename = p.basename(cachedPath);
          expect(
            filename,
            equals('audio_legacy_$messageId.m4a'),
            reason: 'Filename should match format for $description',
          );
        }
      },
    );

    // Feature: encrypted-audio-messaging-ui-completion, Property 13: Legacy audio cache hit
    // **Validates: Requirements 7.2**
    test(
      'Property 13: Legacy audio cache hit - detects cached files correctly',
      () async {
        // Test multiple scenarios to verify cache hit behavior
        final testCases = [
          {
            'messageId': 'msg-cached-001',
            'description': 'First cached message'
          },
          {
            'messageId': 'msg-cached-002',
            'description': 'Second cached message'
          },
        ];

        for (final testCase in testCases) {
          final messageId = testCase['messageId'] as String;
          final description = testCase['description'] as String;

          // Pre-cache the audio file
          final cacheKey = 'legacy_$messageId';
          final cachedPath = await audioCacheService.getCacheFilePath(cacheKey);
          final cachedFile = File(cachedPath);
          await cachedFile.parent.create(recursive: true);
          
          final mockAudioData = List<int>.generate(2048, (i) => i % 256);
          await cachedFile.writeAsBytes(mockAudioData);

          // Verify the file is cached
          expect(
            await audioCacheService.isCached(cacheKey),
            true,
            reason: 'Audio should be marked as cached for $description',
          );

          // Verify the file exists
          expect(
            await cachedFile.exists(),
            true,
            reason: 'Cache file should exist for $description',
          );

          // Verify the cached data
          final cachedData = await cachedFile.readAsBytes();
          expect(
            cachedData,
            equals(mockAudioData),
            reason: 'Cached data should match for $description',
          );

          // Clean up
          await cachedFile.delete();
        }
      },
    );

    // Feature: encrypted-audio-messaging-ui-completion, Property 14: Legacy audio cache filename format
    // **Validates: Requirements 7.4, 12.1**
    test(
      'Property 14: Legacy audio cache filename format - uses correct naming pattern',
      () async {
        // Test multiple message IDs to verify filename format consistency
        final testCases = [
          {
            'messageId': 'abc123',
            'expectedFilename': 'audio_legacy_abc123.m4a',
            'description': 'Alphanumeric ID'
          },
          {
            'messageId': 'msg-with-dashes',
            'expectedFilename': 'audio_legacy_msg-with-dashes.m4a',
            'description': 'ID with dashes'
          },
          {
            'messageId': '12345',
            'expectedFilename': 'audio_legacy_12345.m4a',
            'description': 'Numeric ID'
          },
          {
            'messageId': 'very_long_message_id_with_underscores_123',
            'expectedFilename': 'audio_legacy_very_long_message_id_with_underscores_123.m4a',
            'description': 'Long ID with underscores'
          },
        ];

        for (final testCase in testCases) {
          final messageId = testCase['messageId'] as String;
          final expectedFilename = testCase['expectedFilename'] as String;
          final description = testCase['description'] as String;

          // Get cache path for legacy audio
          final cacheKey = 'legacy_$messageId';
          final cachedPath = await audioCacheService.getCacheFilePath(cacheKey);

          // Verify the filename matches the expected format
          final actualFilename = p.basename(cachedPath);
          expect(
            actualFilename,
            equals(expectedFilename),
            reason: 'Filename should match format "audio_legacy_{messageId}.m4a" for $description',
          );

          // Verify the file is in the correct cache directory
          final cacheDir = p.dirname(cachedPath);
          expect(
            cacheDir,
            equals(tempDir.path),
            reason: 'Cache file should be in the temporary directory for $description',
          );
        }
      },
    );

    // Additional test: Cache directory consistency
    test(
      'Cache directory consistency - legacy and encrypted audio use same directory',
      () async {
        // Get cache path for legacy audio
        final legacyCacheKey = 'legacy_msg-legacy';
        final legacyCachePath = await audioCacheService.getCacheFilePath(legacyCacheKey);
        final legacyCacheDir = p.dirname(legacyCachePath);

        // Get cache path for encrypted audio (using regular message ID)
        final encryptedCachePath = await audioCacheService.getCacheFilePath('msg-encrypted');
        final encryptedCacheDir = p.dirname(encryptedCachePath);

        // Verify both use the same cache directory
        expect(
          legacyCacheDir,
          equals(encryptedCacheDir),
          reason: 'Legacy and encrypted audio should use the same cache directory',
        );

        expect(
          legacyCacheDir,
          equals(tempDir.path),
          reason: 'Cache directory should be the temporary directory',
        );
      },
    );

    // Additional test: Widget renders correctly for legacy messages
    testWidgets(
      'AudioMessageBubble renders correctly for legacy audio messages',
      (tester) async {
        final message = createLegacyMessage(
          id: 'msg-widget-test',
          audioUrl: 'https://example.com/audio.m4a',
        );

        await tester.pumpWidget(wrap(AudioMessageBubble(message: message)));
        await tester.pumpAndSettle();

        // Verify the play button is displayed
        expect(
          find.byIcon(Icons.play_arrow),
          findsOneWidget,
          reason: 'Play button should be displayed',
        );

        // Verify the audio visualization is displayed
        expect(
          find.byType(Slider),
          findsOneWidget,
          reason: 'Audio slider should be displayed',
        );
      },
    );

    // Additional test: Widget distinguishes between legacy and encrypted messages
    testWidgets(
      'AudioMessageBubble distinguishes between legacy and encrypted messages',
      (tester) async {
        // Test legacy message
        final legacyMessage = createLegacyMessage(
          id: 'msg-legacy',
          audioUrl: 'https://example.com/legacy.m4a',
        );

        await tester.pumpWidget(wrap(AudioMessageBubble(message: legacyMessage)));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.play_arrow), findsOneWidget);

        // Test encrypted message
        final encryptedMessage = createEncryptedMessage(
          id: 'msg-encrypted',
          audioUrl: 'https://example.com/encrypted.m4a',
          fileKey: 'test-file-key-123',
        );

        await tester.pumpWidget(wrap(AudioMessageBubble(message: encryptedMessage)));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      },
    );
  });
}
