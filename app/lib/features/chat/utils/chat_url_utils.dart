import 'package:app/core/network/network_service.dart';

String resolveFullUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  return NetworkService.resolveUrl(path);
}
