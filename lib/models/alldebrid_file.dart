/// A single file inside an AllDebrid magnet, flattened from the nested
/// folder structure returned by `/v4/magnet/files`.
///
/// Unlike Premiumize, AllDebrid's [link] is a *locked* link that must be passed
/// through `/v4/link/unlock` to obtain a streamable/downloadable direct URL.
/// This mirrors Real-Debrid's restricted-link → unrestrict flow.
class AllDebridFile {
  /// Path of the file within the torrent (e.g. "Show.S01/E01.mkv").
  final String path;

  /// File size in bytes.
  final int size;

  /// Locked download link. Must be unlocked via
  /// [AllDebridService.unlockLink] before playback/download.
  final String link;

  AllDebridFile({
    required this.path,
    required this.size,
    required this.link,
  });

  /// Bare filename (last path segment).
  String get fileName {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    return segments.isNotEmpty ? segments.last : path;
  }
}
