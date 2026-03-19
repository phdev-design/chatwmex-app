/// YouTube URL 偵測與解析工具類
class YouTubeDetector {
  static final _youtubeRegex = RegExp(
    r'(?:(?:www\.|m\.)?youtube\.com/(?:watch\?v=|shorts/)|youtu\.be/)([A-Za-z0-9_-]{11})',
    caseSensitive: false,
  );

  /// 從訊息內容中提取 YouTube Video ID
  ///
  /// 支援格式：
  ///   - https://www.youtube.com/watch?v={videoId}
  ///   - https://youtu.be/{videoId}
  ///   - https://youtube.com/watch?v={videoId}
  ///   - https://m.youtube.com/watch?v={videoId}
  ///   - https://www.youtube.com/shorts/{videoId}
  ///
  /// 返回 11 字元的 videoId，或 null（無效/不存在）
  static String? extractVideoId(String content) {
    final match = _youtubeRegex.firstMatch(content);
    if (match == null) return null;

    final videoId = match.group(1);
    if (videoId == null || videoId.length != 11) return null;

    return videoId;
  }

  /// 從 videoId 建構縮圖 URL
  static String thumbnailUrl(String videoId) {
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }
}
