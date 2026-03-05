import 'package:app/features/chat/utils/chat_url_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractAllUrls', () {
    test('空字串回傳空陣列', () {
      expect(extractAllUrls(''), isEmpty);
    });

    test('無網址的純文字回傳空陣列', () {
      expect(extractAllUrls('Hello world'), isEmpty);
    });

    test('單一網址可正確擷取', () {
      expect(
        extractAllUrls('Check this https://google.com'),
        equals(['https://google.com']),
      );
    });

    test('多個網址可全部擷取', () {
      expect(
        extractAllUrls('Here is https://google.com and http://apple.com'),
        equals(['https://google.com', 'http://apple.com']),
      );
    });

    test('大小寫混合協議可擷取', () {
      expect(
        extractAllUrls('Visit HtTpS://Flutter.DEV now'),
        equals(['HtTpS://Flutter.DEV']),
      );
    });

    test('緊鄰標點符號仍可擷取', () {
      expect(
        extractAllUrls('Go to https://example.com/!'),
        equals(['https://example.com/!']),
      );
    });
  });
}
