import 'package:app/features/chat/utils/youtube_detector.dart';
import 'package:glados/glados.dart';

/// Feature: youtube-inline-player
///
/// 屬性測試與單元測試：YouTubeDetector

// ─── 自訂 Generator ───────────────────────────────────────────────────────────

/// 有效 YouTube Video ID 的字元集（11 個字元，由 [A-Za-z0-9_-] 組成）
const _videoIdChars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';

/// 從 seed 產生一個長度為 11 的有效 Video ID
String _seedToVideoId(int seed) {
  final chars = <String>[];
  var s = seed.abs();
  for (var i = 0; i < 11; i++) {
    chars.add(_videoIdChars[s % _videoIdChars.length]);
    s = (s ~/ _videoIdChars.length) + (i + 1) * 31;
  }
  return chars.join();
}

/// 從 seed 產生一個格式錯誤的 YouTube URL（Video ID 長度不足 11）
String _seedToInvalidYoutubeUrl(int seed) {
  final length = (seed.abs() % 10); // 0..10，確保 < 11
  final chars = <String>[];
  var s = seed.abs();
  for (var i = 0; i < length; i++) {
    chars.add(_videoIdChars[s % _videoIdChars.length]);
    s = (s ~/ _videoIdChars.length) + (i + 1) * 17;
  }
  final shortId = chars.join();
  return 'https://www.youtube.com/watch?v=$shortId';
}

/// 從 seed 產生各種非 YouTube 字串（純文字、其他 URL、空字串等）
String _seedToNonYoutubeString(int seed) {
  final options = [
    '',
    'Hello world',
    'https://google.com',
    'https://example.com/watch?v=dQw4w9WgXcQ',
    'not a url at all',
    'youtube',
    'youtu.be',
    'http://vimeo.com/12345678901',
    seed.toString(),
    'random text ${seed % 999}',
  ];
  return options[seed.abs() % options.length];
}

// ─── Property 1：YouTube URL Round-Trip 解析 ─────────────────────────────────

/// Feature: youtube-inline-player, Property 1: YouTube URL round-trip 解析
///
/// **Validates: Requirements 1.1, 1.2, 5.1, 5.2**
void _property1Tests() {
  group('Property 1: YouTube URL Round-Trip 解析', () {
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      '對任意有效 videoId，組合成各支援格式 URL 後解析應得到相同 videoId',
      (seed) {
        final videoId = _seedToVideoId(seed);
        final formats = [
          'https://www.youtube.com/watch?v=$videoId',
          'https://youtu.be/$videoId',
          'https://youtube.com/watch?v=$videoId',
          'https://m.youtube.com/watch?v=$videoId',
          'https://www.youtube.com/shorts/$videoId',
        ];
        for (final url in formats) {
          final result = YouTubeDetector.extractVideoId(url);
          expect(
            result,
            equals(videoId),
            reason: 'URL: $url 應解析出 videoId=$videoId，但得到 $result',
          );
          expect(
            result?.length,
            equals(11),
            reason: '解析出的 videoId 長度應為 11',
          );
        }
      },
    );
  });
}

// ─── Property 2：非 YouTube 輸入的安全性 ─────────────────────────────────────

/// Feature: youtube-inline-player, Property 2: 非 YouTube 輸入的安全性
///
/// **Validates: Requirements 1.3, 5.3, 5.4**
void _property2Tests() {
  group('Property 2: 非 YouTube 輸入的安全性', () {
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      '對任意字串輸入，extractVideoId 不應拋出例外',
      (seed) {
        final input = _seedToNonYoutubeString(seed);
        expect(
          () => YouTubeDetector.extractVideoId(input),
          returnsNormally,
          reason: '輸入 "$input" 不應拋出例外',
        );
      },
    );
  });
}

// ─── Property 3：無效 YouTube URL 返回 null ───────────────────────────────────

/// Feature: youtube-inline-player, Property 3: 無效 YouTube URL 返回 null
///
/// **Validates: Requirements 1.4**
void _property3Tests() {
  group('Property 3: 無效 YouTube URL 返回 null', () {
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      '對 Video ID 長度不足 11 的 YouTube URL，extractVideoId 應返回 null',
      (seed) {
        final url = _seedToInvalidYoutubeUrl(seed);
        final result = YouTubeDetector.extractVideoId(url);
        expect(
          result,
          isNull,
          reason: 'URL: $url 的 Video ID 長度不足 11，應返回 null',
        );
      },
    );
  });
}

// ─── Property 4：縮圖 URL 格式正確性 ─────────────────────────────────────────

/// Feature: youtube-inline-player, Property 4: 縮圖 URL 格式正確性
///
/// **Validates: Requirements 2.2**
void _property4Tests() {
  group('Property 4: 縮圖 URL 格式正確性', () {
    Glados(any.intInRange(0, 1 << 30), ExploreConfig(numRuns: 100)).test(
      '對任意有效 videoId，thumbnailUrl 應包含 videoId 且格式正確',
      (seed) {
        final videoId = _seedToVideoId(seed);
        final url = YouTubeDetector.thumbnailUrl(videoId);
        expect(
          url,
          contains(videoId),
          reason: 'thumbnailUrl 應包含 videoId=$videoId',
        );
        expect(
          url,
          startsWith('https://img.youtube.com/vi/'),
          reason: 'thumbnailUrl 應以 https://img.youtube.com/vi/ 開頭',
        );
        expect(
          url,
          endsWith('/hqdefault.jpg'),
          reason: 'thumbnailUrl 應以 /hqdefault.jpg 結尾',
        );
      },
    );
  });
}

// ─── 單元測試（具體範例）────────────────────────────────────────────────────

void _unitTests() {
  group('YouTubeDetector 單元測試', () {
    group('extractVideoId - 支援的 URL 格式', () {
      test('解析 www.youtube.com/watch?v= 格式', () {
        expect(
          YouTubeDetector.extractVideoId(
              'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          equals('dQw4w9WgXcQ'),
        );
      });

      test('解析 youtu.be/ 格式', () {
        expect(
          YouTubeDetector.extractVideoId('https://youtu.be/dQw4w9WgXcQ'),
          equals('dQw4w9WgXcQ'),
        );
      });

      test('解析 youtube.com/watch?v= 格式（無 www）', () {
        expect(
          YouTubeDetector.extractVideoId(
              'https://youtube.com/watch?v=dQw4w9WgXcQ'),
          equals('dQw4w9WgXcQ'),
        );
      });

      test('解析 m.youtube.com/watch?v= 格式', () {
        expect(
          YouTubeDetector.extractVideoId(
              'https://m.youtube.com/watch?v=dQw4w9WgXcQ'),
          equals('dQw4w9WgXcQ'),
        );
      });

      test('解析 www.youtube.com/shorts/ 格式', () {
        expect(
          YouTubeDetector.extractVideoId(
              'https://www.youtube.com/shorts/dQw4w9WgXcQ'),
          equals('dQw4w9WgXcQ'),
        );
      });

      test('訊息文字中夾帶 YouTube URL 也能解析', () {
        expect(
          YouTubeDetector.extractVideoId(
              '看看這個影片 https://youtu.be/dQw4w9WgXcQ 很好看'),
          equals('dQw4w9WgXcQ'),
        );
      });
    });

    group('extractVideoId - 邊界條件', () {
      test('空字串返回 null', () {
        expect(YouTubeDetector.extractVideoId(''), isNull);
      });

      test('純文字返回 null', () {
        expect(YouTubeDetector.extractVideoId('Hello world'), isNull);
      });

      test('非 YouTube URL 返回 null', () {
        expect(
          YouTubeDetector.extractVideoId('https://google.com'),
          isNull,
        );
      });

      test('Video ID 長度不足 11 返回 null', () {
        expect(
          YouTubeDetector.extractVideoId(
              'https://www.youtube.com/watch?v=short'),
          isNull,
        );
      });

      test('Video ID 恰好 11 字元可正確解析', () {
        expect(
          YouTubeDetector.extractVideoId(
              'https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
          equals('dQw4w9WgXcQ'),
        );
      });
    });

    group('thumbnailUrl', () {
      test('回傳正確格式的縮圖 URL', () {
        expect(
          YouTubeDetector.thumbnailUrl('dQw4w9WgXcQ'),
          equals('https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg'),
        );
      });
    });
  });
}

void main() {
  _property1Tests();
  _property2Tests();
  _property3Tests();
  _property4Tests();
  _unitTests();
}
