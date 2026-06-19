/// A saved direct-download link in the user's AllDebrid account, returned by
/// `/v4/user/links` (the "web downloads" library — individual host links the
/// user has saved, distinct from magnets).
///
/// Like [AllDebridFile], the [link] is the original *locked* host URL and must
/// be passed through `/v4/link/unlock` ([AllDebridService.unlockLink]) before
/// playback/download.
class AllDebridLink {
  /// Original host link (e.g. https://host.example/file). Unlock before use.
  final String link;

  /// File name reported by AllDebrid (may be empty for some hosts).
  final String filename;

  /// File size in bytes (0 if unknown).
  final int size;

  /// Unix timestamp (seconds) when the link was saved.
  final int date;

  /// Host name (e.g. "1fichier.com").
  final String host;

  const AllDebridLink({
    required this.link,
    required this.filename,
    required this.size,
    required this.date,
    required this.host,
  });

  /// Display name: the saved filename, falling back to the link's basename.
  String get fileName {
    if (filename.isNotEmpty) return filename;
    final uri = Uri.tryParse(link);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.isNotEmpty) return last;
    }
    return link;
  }

  factory AllDebridLink.fromJson(Map<String, dynamic> json) {
    return AllDebridLink(
      link: json['link']?.toString() ?? '',
      filename: json['filename']?.toString() ?? '',
      size: _asInt(json['size']),
      date: _asInt(json['date']),
      host: json['host']?.toString() ?? '',
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
