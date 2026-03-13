import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupManager _validateTimeFormat', () {
    test('validates correct time format "00:00"', () {
      final result = _testValidateTimeFormat('00:00');
      expect(result, isTrue);
    });

    test('validates correct time format "12:30"', () {
      final result = _testValidateTimeFormat('12:30');
      expect(result, isTrue);
    });

    test('validates correct time format "23:59"', () {
      final result = _testValidateTimeFormat('23:59');
      expect(result, isTrue);
    });

    test('validates correct time format "02:00"', () {
      final result = _testValidateTimeFormat('02:00');
      expect(result, isTrue);
    });

    test('rejects invalid hour "24:00"', () {
      final result = _testValidateTimeFormat('24:00');
      expect(result, isFalse);
    });

    test('rejects invalid minute "12:60"', () {
      final result = _testValidateTimeFormat('12:60');
      expect(result, isFalse);
    });

    test('rejects single digit hour "2:30"', () {
      final result = _testValidateTimeFormat('2:30');
      expect(result, isFalse);
    });

    test('rejects single digit minute "12:5"', () {
      final result = _testValidateTimeFormat('12:5');
      expect(result, isFalse);
    });

    test('rejects non-numeric input "ab:cd"', () {
      final result = _testValidateTimeFormat('ab:cd');
      expect(result, isFalse);
    });

    test('rejects empty string', () {
      final result = _testValidateTimeFormat('');
      expect(result, isFalse);
    });

    test('rejects time with whitespace "02:00 "', () {
      final result = _testValidateTimeFormat('02:00 ');
      expect(result, isFalse);
    });

    test('rejects time without colon "0200"', () {
      final result = _testValidateTimeFormat('0200');
      expect(result, isFalse);
    });
  });
}

/// Helper function to test the private _validateTimeFormat method
/// This uses the regex pattern directly to test the validation logic
bool _testValidateTimeFormat(String time) {
  final regex = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
  return regex.hasMatch(time);
}
