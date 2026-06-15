/// A single file returned by Premiumize's `/transfer/directdl` endpoint.
///
/// Premiumize hands back ready-to-use direct links for every file in a torrent
/// in one response, so [link] is immediately playable/downloadable — no
/// per-file unrestrict step is required (unlike Real-Debrid/Torbox).
class PremiumizeFile {
  /// Path of the file within the torrent (e.g. "Show.S01/E01.mkv").
  final String path;

  /// File size in bytes.
  final int size;

  /// Direct download URL (ready to use).
  final String link;

  /// Optional transcoded HLS stream URL.
  final String? streamLink;

  PremiumizeFile({
    required this.path,
    required this.size,
    required this.link,
    this.streamLink,
  });

  /// Bare filename (last path segment).
  String get fileName {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isNotEmpty ? segments.last : path;
  }

  factory PremiumizeFile.fromJson(Map<String, dynamic> json) {
    final stream = json['stream_link']?.toString();
    return PremiumizeFile(
      path: json['path']?.toString() ?? '',
      size: _asInt(json['size']),
      link: json['link']?.toString() ?? '',
      streamLink: (stream != null && stream.isNotEmpty) ? stream : null,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is num) return value.toInt();
    return 0;
  }
}
