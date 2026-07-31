import '../models/iptv_playlist.dart';

/// Catalog identity: the string a cacheable IPTV source is stored under.
///
/// These exact strings key the `catalogs`/`channels` rows in
/// `iptv_catalog.db`, so "is this source cacheable?" and "which rows belong to
/// it?" are the same question everywhere — the page, the parse workers and the
/// settings screen's invalidation paths.
///
/// The format predates the catalog database: it was the disk-snapshot cache's
/// filename key. That cache is gone, but the strings are deliberately
/// unchanged — they identify rows already on disk, and changing the format
/// would orphan every stored catalog.
class IptvCatalogKey {
  const IptvCatalogKey._();

  /// The content types an Xtream login exposes, each stored separately.
  static const xtreamContentTypes = ['live', 'vod', 'series'];

  static String forXtream(
    String serverUrl,
    String username,
    String contentType,
  ) => 'xc|$serverUrl|$username|$contentType';

  static String forUrl(String url) => 'm3u|$url';

  /// Every key an Xtream login can be stored under (one per content type) —
  /// what invalidation has to sweep when the credentials change.
  static List<String> allForXtream(String serverUrl, String username) => [
    for (final type in xtreamContentTypes) forXtream(serverUrl, username, type),
  ];

  /// The key for this playlist + content type, or null when the source isn't
  /// cacheable at all. Virtual shelves (favorites, continue-watching), Stremio
  /// addons and local files have no stable remote identity, so they stay
  /// materialized in memory instead of living as rows.
  static String? forPlaylist(IptvPlaylist playlist, String contentType) {
    if (playlist.isFavorites ||
        playlist.isContinueWatching ||
        playlist.isStremioAddon ||
        playlist.isLocalFile) {
      return null;
    }
    if (playlist.isXtreamCodes) {
      return forXtream(
        playlist.serverUrl!,
        playlist.username ?? '',
        contentType,
      );
    }
    if (playlist.url.isEmpty) return null;
    return forUrl(playlist.url);
  }
}
