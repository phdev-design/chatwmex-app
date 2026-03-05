import 'package:app/core/network/network_service.dart';

String resolveFullUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  return NetworkService.resolveUrl(path);
}

List<String> extractAllUrls(String content) {
  final regex = RegExp(r'https?://[^\s]+', caseSensitive: false);
  return regex
      .allMatches(content)
      .map((m) => m.group(0) ?? '')
      .where((u) => u.isNotEmpty)
      .toList();
}
